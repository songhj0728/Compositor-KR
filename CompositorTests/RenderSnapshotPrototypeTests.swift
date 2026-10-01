import Foundation
import CoreGraphics
import Testing
@testable import Compositor

/// Test-only bridge to the C++ experiment compiled in the hosted test target.
/// No app call site uses it; no external process or runtime compilation is needed.
@MainActor
struct RenderSnapshotPrototypeTests {
    private struct Token {
        let instance = UUID()
        let state = UUID()
        var generation: UInt64 = 7
    }
    private struct Projection {
        let header: [String]
        let rows: [[String]]
        let drawn: [String]
    }

    private func fixtureInput(_ document: CanvasDocument, token: Token, expected: Token? = nil) -> String {
        let expected = expected ?? token
        var lines = [["H", token.instance.uuidString, token.state.uuidString, String(token.generation),
            document.id.uuidString, String(document.width), String(document.height),
            expected.instance.uuidString, String(expected.generation)].joined(separator: "\t")]
        for layer in document.layers {
            let p = layer.transform
            let kind = layer.isGroup ? "group" : layer.adjustment != nil ? "adjustment" : layer.text != nil ? "text"
                : layer.shape != nil ? "shape" : layer.asset != nil ? "pixel" : "empty"
            let fields = ["N", layer.id.uuidString, layer.parentID?.uuidString ?? "-", layer.maskSourceID?.uuidString ?? "-",
                kind, layer.isVisible ? "1" : "0", String(layer.opacity), String(layer.effects?.fill ?? 1), layer.blendMode.rawValue,
                String(Double(p.origin.x)), String(Double(p.origin.y)), String(Double(p.size.width)), String(Double(p.size.height)),
                String(Double(p.rotation)), p.flipX ? "1" : "0", p.flipY ? "1" : "0", p.sampling.rawValue,
                layer.effects == nil ? "0" : "1", layer.mask?.isEnabled == true ? "1" : "0"]
            lines.append(fields.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func run(_ input: String) -> String {
        RenderProjectionFixture.project(input)
    }

    private func projection(_ document: CanvasDocument, token: Token) throws -> Projection {
        let lines = run(fixtureInput(document, token: token))
            .split(separator: "\n").map { String($0).components(separatedBy: "\t") }
        let header = try #require(lines.first)
        try #require(header.first == "H" && header.count == 7)
        let rows = lines.filter { $0.first == "N" }
        try #require(rows.allSatisfy { $0.count == 37 })
        let drawn = try #require(lines.first { $0.first == "D" })
        return Projection(header: header, rows: rows, drawn: drawn[1] == "-" ? [] : drawn[1].components(separatedBy: ","))
    }

    private func layer(_ name: String, parent: UUID? = nil, group: Bool = false) -> ImageLayer {
        var layer = ImageLayer(name: name, blankSize: CGSize(width: 8, height: 8))
        layer.parentID = parent; layer.isGroup = group
        return layer
    }

    private func fixtures() -> [(String, CanvasDocument)] {
        let single = layer("single"), sibling = layer("sibling")
        var hidden = layer("hidden", group: true); hidden.isVisible = false
        let hiddenChild = layer("child", parent: hidden.id)
        var outer = layer("outer", group: true); outer.opacity = 0.5
        var inner = layer("inner", parent: outer.id, group: true); inner.opacity = 0.4
        var leaf = layer("leaf", parent: inner.id); leaf.opacity = 0.3
        let base = layer("base")
        var clipped = layer("clipped"); clipped.maskSourceID = base.id
        var hiddenBase = base; hiddenBase.isVisible = false
        let group = layer("group", group: true)
        var cross = clipped; cross.parentID = group.id
        var filled = layer("fill"); filled.opacity = 0.6
        var effects = LayerEffects(); effects.fillOpacity = 0.2; filled.effects = effects
        filled.blendMode = .multiply
        var moved = layer("transformed")
        moved.transform = LayerTransform(origin: CGPoint(x: 10, y: 20), size: CGSize(width: 30, height: 40),
            rotation: 90, flipX: true, flipY: false, sampling: .nearest)
        var released = [clipped, base]
        EditorSession.releaseDetachedClipping(in: &released)
        var chained = layer("chained"); chained.maskSourceID = clipped.id
        let inputs: [(String, [ImageLayer])] = [
            ("single", [single]), ("siblings", [single, sibling]),
            ("hidden group", [hidden, hiddenChild]), ("nested opacity", [leaf, outer, inner]),
            ("clipping pair", [base, clipped]), ("hidden base", [hiddenBase, clipped]),
            ("reordered link", [clipped, hiddenBase]), ("reordered after existing unlink", released),
            ("cross-group source", [hiddenBase, group, cross]), ("fill and opacity", [filled]),
            ("transformed", [moved]), ("clipping chain", [base, clipped, chained]),
        ]
        return inputs.map { ($0.0, CanvasDocument(width: 100, height: 80, layers: $0.1)) }
    }

    @Test func actualModelFixturesMatchExistingRenderInterpretation() throws {
        for (_, document) in fixtures() {
            let token = Token()
            let snapshot = try projection(document, token: token)
            #expect(snapshot.header[1] == token.instance.uuidString && snapshot.header[2] == token.state.uuidString)
            #expect(snapshot.header[3] == String(token.generation) && snapshot.header[4] == document.id.uuidString)
            #expect(snapshot.rows.map { $0[1] } == document.hierarchy.order.map(\.uuidString))
            #expect(snapshot.drawn == document.renderLayers.map { $0.id.uuidString })
            let byID = Dictionary(uniqueKeysWithValues: document.layers.map { ($0.id, $0) })
            let depth = Dictionary(uniqueKeysWithValues: LayerHierarchy.entries(document.layers.map(\.hierarchyRecord)).map { ($0.layer.id, $0.depth) })
            // Small reference interpretation of the private stack classification
            // in LiveMaskRenderer.prepareStacks and CanvasView's GPU path.
            let drawn = document.renderLayers
            var stacks: [UUID: UUID] = [:]
            for (index, base) in drawn.enumerated() where base.maskSourceID == nil && base.adjustment == nil {
                for child in drawn.dropFirst(index + 1) {
                    guard child.maskSourceID == base.id, child.parentID == base.parentID else { break }
                    stacks[child.id] = base.id
                }
            }
            for row in snapshot.rows {
                let id = try #require(UUID(uuidString: row[1]))
                let layer = try #require(byID[id])
                #expect(row[2] == (layer.parentID?.uuidString ?? "-") && row[3] == (layer.maskSourceID?.uuidString ?? "-"))
                #expect(Int(row[5]) == depth[id])
                #expect((row[6] == "1") == layer.isVisible)
                #expect((row[7] == "1") == document.effectiveVisibleIDs.contains(id))
                #expect(try #require(Double(row[8])) == layer.opacity)
                #expect(abs(try #require(Double(row[9])) - layer.effectiveOpacity(in: byID)) < 1e-12)
                #expect(try #require(Double(row[10])) == (layer.effects?.fill ?? 1))
                #expect(row[11] == layer.blendMode.rawValue)
                #expect(row[12] == (stacks[id] != nil ? "stack" : layer.maskSourceID != nil ? "independent" : "none"))
                #expect(row[13] == (stacks[id]?.uuidString ?? "-"))
                #expect(row[21] == layer.transform.sampling.rawValue)
                #expect((row[22] == "1") == (layer.effects != nil))
                #expect((row[23] == "1") == (layer.mask?.isEnabled == true))
                let map = layer.transform.unitToDocument
                let native = [map.a, map.b, map.c, map.d, map.tx, map.ty].map { Double($0) }
                for (value, field) in zip(native, row[24...29]) {
                    #expect(abs(value - (try #require(Double(field)))) < 1e-9)
                }
                let corners = [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)].map { $0.applying(map) }
                let xs = corners.map { Double($0.x) }, ys = corners.map { Double($0.y) }
                let expected = [xs.min()!, ys.min()!, xs.max()! - xs.min()!, ys.max()! - ys.min()!]
                for (value, field) in zip(expected, row[30...33]) {
                    #expect(abs(value - (try #require(Double(field)))) < 1e-9)
                }
                var ancestors: [String] = [], parent = layer.parentID
                while let current = parent { ancestors.append(current.uuidString); parent = byID[current]?.parentID }
                let orderedAncestors = ancestors.reversed()
                #expect(row[34] == (ancestors.isEmpty ? "-" : orderedAncestors.joined(separator: ",")))
                var chain: [String] = [], source = layer.maskSourceID
                while let current = source { chain.append(current.uuidString); source = byID[current]?.maskSourceID }
                #expect(row[36] == (chain.isEmpty ? "-" : chain.joined(separator: ",")))
            }
        }
    }

    @Test func oldProjectionSurvivesActualSourceEdits() throws {
        var document = CanvasDocument(width: 100, height: 80, layers: [layer("a"), layer("b")])
        var token = Token()
        let before = try projection(document, token: token)
        let savedRows = before.rows
        document.layers[0].isVisible = false; document.layers[0].opacity = 0.25
        document.layers.reverse(); token.generation += 1
        let after = try projection(document, token: token)
        #expect(before.rows == savedRows && before.header[3] == "7")
        #expect(before.rows[0][7] == "1" && before.rows[0][8] == "1")
        #expect(before.rows[0][1] == document.layers[1].id.uuidString)
        #expect(after.header[3] == "8" && after.rows.map { $0[1] } == document.layers.map { $0.id.uuidString })
        #expect(after.rows[1][7] == "0" && after.rows[1][8] == "0.25")
    }

    @Test func invalidActualGraphsAndStaleTokenReturnErrors() throws {
        let a = layer("a")
        var missing = a; missing.parentID = UUID()
        var clipping = a; clipping.maskSourceID = UUID()
        var group = layer("g", group: true); group.parentID = group.id
        var cycle = a; cycle.maskSourceID = a.id
        let token = Token()
        for (layers, code) in [([a, a], "duplicateID"), ([missing], "missingParent"),
            ([clipping], "invalidClippingBase"), ([group], "parentCycle"), ([cycle], "clippingCycle")] {
            let output = run(fixtureInput(CanvasDocument(width: 8, height: 8, layers: layers), token: token))
            #expect(output.hasPrefix("E\t\(code)\t"))
        }
        var newer = token; newer.generation += 1
        let output = run(fixtureInput(CanvasDocument(width: 8, height: 8, layers: [a]), token: token, expected: newer))
        #expect(output.hasPrefix("E\tstalePublication\t"))
    }
}
