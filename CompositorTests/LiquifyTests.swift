import AppKit
import Testing
@testable import Compositor

// Serialized, so the timing below isn't sharing the cores with the other tests.
@MainActor @Suite(.serialized)
struct LiquifyTests {
    /// Left half red, right half blue.
    private func splitImage(width: Int = 200, height: Int = 200) throws -> CGImage {
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try #require(context.makeImage())
    }
    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        let count = image.width * image.height * 4
        return Array(UnsafeBufferPointer(start: try #require(context.data).bindMemory(to: UInt8.self, capacity: count), count: count))
    }
    private func changed(_ a: [UInt8], _ b: [UInt8]) -> Int { zip(a, b).filter { $0 != $1 }.count }
    /// Diagonal, so the tools that move pixels across the stroke (Push Left) cross the colors' edge too.
    private func stroke(_ mode: LiquifyMode, on field: LiquifyField) {
        for i in 0..<20 {
            field.dab(mode, from: CGPoint(x: 80 + Double(i), y: 80 + Double(i)), to: CGPoint(x: 81 + Double(i), y: 81 + Double(i)),
                      diameter: 60, hardness: 0.5, strength: 1)
        }
    }
    private func result(_ field: LiquifyField) throws -> [UInt8] {
        _ = field.renderChanges()
        return try bytes(try #require(field.context.makeImage()))
    }

    @Test(arguments: [LiquifyMode.forwardWarp, .pushLeft, .twirlClockwise, .pucker, .bloat])
    func everyToolMovesPixels(mode: LiquifyMode) throws {
        let source = try splitImage()
        let field = try LiquifyField(image: source, width: 200, height: 200)
        stroke(mode, on: field)
        #expect(changed(try bytes(source), try result(field)) > 0)
    }

    @Test func reconstructBringsThePixelsBack() throws {
        let source = try splitImage()
        let base = try bytes(source)
        let field = try LiquifyField(image: source, width: 200, height: 200)
        stroke(.forwardWarp, on: field)
        #expect(changed(base, try result(field)) > 0)
        for _ in 0..<80 {
            field.dab(.reconstruct, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 100, y: 100), diameter: 160, hardness: 0.9, strength: 1)
        }
        #expect(changed(base, try result(field)) == 0)
    }

    /// Each stroke is one step: undo takes strokes back newest first, redo puts them back, and a new stroke
    /// after an undo drops what could have been redone.
    @Test func undoAndRedoGoStrokeByStroke() throws {
        let session = EditorSession()
        session.createDocument(width: 300, height: 300)
        let image = try splitImage()
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Split"))
        session.beginLiquify()
        let edit = try #require(session.liquify)
        func drag(_ y: Double) {
            edit.begin(at: CGPoint(x: 80, y: y))
            edit.drag(to: CGPoint(x: 130, y: y))
            edit.end()
        }
        func shown() throws -> [UInt8] { _ = edit.takeImage(); return try bytes(edit.current) }
        let base = try bytes(edit.before)
        #expect(!edit.canUndo && !edit.canRedo)
        drag(50)
        let afterFirst = try shown()
        drag(150)
        let afterSecond = try shown()
        #expect(edit.undoSteps.count == 2)

        edit.undo()
        #expect(changed(try shown(), afterFirst) == 0)
        edit.undo()
        #expect(changed(try shown(), base) == 0)
        #expect(!edit.canUndo && edit.canRedo && !edit.hasChanges)
        edit.redo()
        edit.redo()
        #expect(changed(try shown(), afterSecond) == 0)
        #expect(!edit.canRedo)

        edit.undo()
        drag(100)
        #expect(!edit.canRedo)
        #expect(edit.undoSteps.count == 2)
        session.cancelLiquify()
    }

    /// OK renders the layer at full size through the smaller copy's field; it should land where the copy showed it.
    @Test func fullSizeRenderMatchesTheSmallerCopy() throws {
        let small = try splitImage(width: 100, height: 100), large = try splitImage(width: 400, height: 400)
        let field = try LiquifyField(image: small, width: 100, height: 100)
        for i in 0..<10 {
            field.dab(.forwardWarp, from: CGPoint(x: 40 + Double(i) * 2, y: 50), to: CGPoint(x: 42 + Double(i) * 2, y: 50),
                      diameter: 40, hardness: 0.5, strength: 1)
        }
        let preview = try result(field)
        let full = try bytes(try LiquifyField.render(large, displacements: field.displacements, fieldWidth: 100, fieldHeight: 100))
        // Red has been pushed right, past the middle, at the stroke's row in both.
        #expect(preview[(50 * 100 + 55) * 4] > 200)
        #expect(full[(200 * 400 + 220) * 4] > 200)
        // Away from the stroke nothing moved.
        #expect(full[(10 * 400 + 220) * 4] < 50)
    }

    @Test func applyReplacesTheLayerAsOneUndoStepAndCancelLeavesIt() async throws {
        let session = EditorSession()
        session.createDocument(width: 300, height: 300)
        let image = try splitImage()
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Split"))
        let before = try #require(session.activeLayer?.asset?.image)

        session.beginLiquify()
        let edit = try #require(session.liquify)
        edit.begin(at: CGPoint(x: 80, y: 100))
        edit.drag(to: CGPoint(x: 120, y: 100))
        edit.end()
        session.cancelLiquify()
        #expect(session.liquify == nil)
        #expect(session.activeLayer?.asset?.image === before)

        session.beginLiquify()
        let again = try #require(session.liquify)
        again.begin(at: CGPoint(x: 80, y: 100))
        again.drag(to: CGPoint(x: 120, y: 100))
        again.end()
        await session.commitLiquify()
        #expect(session.liquify == nil)
        let after = try #require(session.activeLayer?.asset?.image)
        #expect(after !== before)
        #expect(changed(try bytes(before), try bytes(after)) > 0)
        session.undo()
        #expect(session.activeLayer?.asset?.image === before)
    }

    /// A big brush dragged far over a 2048-pixel copy stays well inside a frame's time per mouse event.
    @Test func largeStrokesStayQuick() throws {
        let source = try splitImage(width: 2048, height: 2048)
        let field = try LiquifyField(image: source, width: 2048, height: 2048)
        // Warm up: the first dab also faults the field's pages in and starts the worker threads.
        field.dab(.forwardWarp, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 101, y: 100), diameter: 600, hardness: 0.5, strength: 1)
        _ = field.renderChanges()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            // One very fast mouse event's worth: 800 pixels with a 600-pixel brush, a dab every 8% of it.
            for i in 0..<17 {
                let x = 600 + Double(i) * 48
                field.dab(.forwardWarp, from: CGPoint(x: x, y: 1000), to: CGPoint(x: x + 48, y: 1000), diameter: 600, hardness: 0.5, strength: 1)
            }
            _ = field.renderChanges()
        }
        #expect(elapsed < .milliseconds(100))
    }
}
