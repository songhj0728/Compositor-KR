import AppKit
import Testing
@testable import Compositor

/// Photoshop's Layer Style: the effects it adds (Bevel & Emboss, Satin, Pattern Overlay), blend modes, Fill Opacity,
/// and the dialog that edits them as one undo step.
@MainActor
struct LayerStyleTests {
    /// A white square of `inner` pixels in the middle of a transparent `size` square.
    private func square(size: Int = 60, inner: Int = 30, color: PaletteColor = .white) throws -> CGImage {
        let context = try BrushRaster.context(width: size, height: size, mask: false)
        context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1))
        let offset = (size - inner) / 2
        context.fill(CGRect(x: offset, y: offset, width: inner, height: inner))
        return try #require(context.makeImage())
    }

    @Test func bevelPreviewRefinesAfterQuickFeedback() async throws {
        let session = EditorSession()
        session.createDocument(width: 900, height: 900)
        let image = try square(size: 900, inner: 500)
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Preview"))
        let id = try #require(session.activeLayerID)
        session.setEffects(LayerEffects(bevel: BevelEffect()), on: id)
        let layer = try #require(session.document?.layers.first { $0.id == id })
        let cache = EffectsPreviewCache()
        cache.prepare(layers: [layer])
        defer { cache.prepare(layers: []) }
        var widths: [Int] = []
        _ = cache.preview(for: layer, mask: nil, transform: layer.transform, maskPlacement: nil) {
            if let result = cache.rendered(id) { widths.append(result.image.width) }
        }
        let deadline = ContinuousClock.now + .seconds(30)
        while widths.count < 2 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(widths.count == 2, "The quick preview must be followed by a refined result")
        if widths.count == 2 {
            #expect(widths[0] <= 768)
            #expect(widths[1] > widths[0])
            let expected = try LayerEffectsRenderer.render(image, mask: nil, effects: try #require(layer.effects))
            #expect(widths[1] == expected.image.width, "Refinement restores the existing preview quality")
            let actualData = try #require(cache.rendered(id)?.image.dataProvider?.data) as Data
            let expectedData = try #require(expected.image.dataProvider?.data) as Data
            #expect(actualData == expectedData, "The refined pixels must equal a direct render")
        }
    }

    @Test(arguments: [false, true]) func paintedMaskPreviewDoesNotFlattenItsFullRaster(placed: Bool) async throws {
        let session = EditorSession()
        session.createDocument(width: 900, height: 900)
        let image = try square(size: 900, inner: 500)
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Masked bevel"))
        let id = try #require(session.activeLayerID)
        session.setEffects(LayerEffects(bevel: BevelEffect()), on: id)
        session.addLayerMask()
        if placed, let index = session.document?.layers.firstIndex(where: { $0.id == id }) {
            var placement = session.document!.layers[index].transform
            placement.origin.x += 40
            placement.rotation = 12
            session.document!.layers[index].mask?.placement = placement
            session.document!.layers[index].mask?.isLinked = false
        }
        session.selectTool(.brush)
        session.maskPaintWhite = false
        session.brushSettings.diameter = 120
        session.beginBrush(at: CGPoint(x: 450, y: 450))
        session.continueBrush(at: CGPoint(x: 550, y: 450))
        #expect(session.finishBrushImmediately())
        let layer = try #require(session.activeLayer)
        let raster = try #require(layer.mask?.asset.raster)
        #expect(!raster.hasMaterializedPixels)
        let cache = EffectsPreviewCache()
        cache.prepare(layers: [layer])
        defer { cache.prepare(layers: []) }
        var completions = 0
        let start = ContinuousClock.now
        _ = cache.preview(for: layer, mask: nil, transform: layer.transform, maskPlacement: layer.mask?.placement, usesOwnedMask: true) {
            completions += 1
            if completions == 1 { print("Mask stroke first preview (placed=\(placed)): \(start.duration(to: .now))") }
        }
        let deadline = ContinuousClock.now + .seconds(30)
        while completions < 2 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(completions == 2)
        #expect(!raster.hasMaterializedPixels, "Neither preview pass may assemble the original-size painted mask")
        let mask = layer.mask?.clipImage(placement: layer.mask?.placement, over: layer.transform,
            width: image.width, height: image.height)
        let expected = try LayerEffectsRenderer.render(image, mask: mask, effects: try #require(layer.effects))
        let actual = try #require(cache.rendered(id)?.image)
        #expect(actual.width == expected.image.width && actual.height == expected.image.height)
        let actualData = try #require(actual.dataProvider?.data) as Data
        let expectedData = try #require(expected.image.dataProvider?.data) as Data
        #expect(actualData.count == expectedData.count)
        // Independent tile interpolation can differ slightly at tile edges after rotation.
        let differences = zip(actualData, expectedData).map { abs(Int($0) - Int($1)) }
        #expect(Double(differences.reduce(0, +)) / Double(differences.count) < 0.5)
    }

    @Test func changingSuppliedMaskInvalidatesTheEffectsPreview() async throws {
        let image = try square()
        var layer = ImageLayer(asset: ImportedImage(image: image, thumbnail: image, name: "Mask preview"), origin: .zero)
        layer.effects = LayerEffects(bevel: BevelEffect())
        let cache = EffectsPreviewCache()
        cache.prepare(layers: [layer])
        defer { cache.prepare(layers: []) }
        var completions = 0
        for revealing in [true, false] {
            let mask = try #require(LayerMask.solid(revealing: revealing))
            let target = completions + 1
            _ = cache.preview(for: layer, mask: mask.asset.image, transform: layer.transform, maskPlacement: nil) {
                completions += 1
            }
            let deadline = ContinuousClock.now + .seconds(10)
            while completions < target && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(completions == target)
        }
        let hidden = try #require(cache.rendered(layer.id)?.image)
        #expect(try pixel(hidden, hidden.width / 2, hidden.height / 2).alpha == 0)
    }

    @Test func cancelledStyleRenderingDoesNotReturnAnImage() throws {
        let image = try square()
        var checks = 0
        do {
            _ = try LayerEffectsRenderer.render(image, mask: nil, effects: LayerEffects(bevel: BevelEffect()), isCancelled: {
                checks += 1
                return checks >= 4
            })
            Issue.record("Cancelled rendering returned a completed image")
        } catch is CancellationError {
            #expect(checks == 4)
        }
    }

    /// The pixel's straight (not premultiplied) RGBA, 0–255.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let context = try BrushRaster.copy(image)
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let at = y * context.bytesPerRow + x * 4
        let alpha = Int(data[at + 3])
        func straight(_ value: UInt8) -> Int { alpha == 0 ? 0 : min(255, Int((Double(value) * 255 / Double(alpha)).rounded())) }
        return (straight(data[at]), straight(data[at + 1]), straight(data[at + 2]), alpha)
    }

    /// A project is saved in the oldest format version that holds it: without Layer Style it stays at the version
    /// older copies of the app open (and they check that number, on disk, before anything else); with it, it moves to
    /// the new one, which keeps them from opening it and dropping the style unseen.
    @Test func savesInTheOldestVersionThatHoldsTheProject() async throws {
        let session = EditorSession()
        session.createDocument(width: 60, height: 60)
        let image = try square()
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Square"))
        let id = try #require(session.activeLayerID)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Versions-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        func saved() async throws -> (onDisk: Int?, loaded: ProjectSnapshot) {
            try await ProjectStore.shared.save(try #require(session.projectSnapshot()), to: url)
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("manifest.json")))
            return ((json as? [String: Any])?["version"] as? Int, try await ProjectStore.shared.load(from: url))
        }

        let plain = try await saved()
        #expect(plain.onDisk == ProjectManifest.compatible)
        // The effects older copies know stay at that version too.
        session.setEffects(LayerEffects(stroke: StrokeEffect(), shadow: ShadowEffect()), on: id)
        let older = try await saved()
        #expect(older.onDisk == ProjectManifest.compatible)
        #expect(older.loaded.manifest.layers.first { $0.id == id }?.effects?.stroke != nil)

        var styled = LayerEffects(stroke: StrokeEffect())
        styled.bevel = BevelEffect()
        session.setEffects(styled, on: id)
        let new = try await saved()
        #expect(new.onDisk == 12)
        #expect(new.loaded.manifest.layers.first { $0.id == id }?.effects?.bevel != nil)

        // Taking the style off again lets the project go back to the older version.
        session.setEffects(LayerEffects(stroke: StrokeEffect()), on: id)
        #expect(try await saved().onDisk == ProjectManifest.compatible)
    }

    @Test func legacyEffectsStayOnTheGPUPassAndNewOnesDoNot() {
        var effects = LayerEffects(stroke: StrokeEffect(), shadow: ShadowEffect(), colorOverlay: ColorOverlayEffect())
        #expect(!effects.needsStyleRenderer)
        effects.shadow?.blendMode = .normal
        #expect(!effects.needsStyleRenderer, "an explicit Normal is what the GPU pass draws")
        effects.shadow?.blendMode = .multiply
        #expect(effects.needsStyleRenderer)
        #expect(LayerEffects(bevel: BevelEffect()).needsStyleRenderer)
        #expect(LayerEffects(satin: SatinEffect()).needsStyleRenderer)
        #expect(LayerEffects(patternOverlay: PatternOverlayEffect()).needsStyleRenderer)
        #expect(LayerEffects(fillOpacity: 0.5).needsStyleRenderer)
        #expect(!LayerEffects(fillOpacity: 0.5).isEmpty && LayerEffects(fillOpacity: 1).isEmpty)
    }

    @Test func newFieldsRoundTripAndOlderRecordsStillRead() throws {
        var effects = LayerEffects()
        var bevel = BevelEffect()
        bevel.style = .pillowEmboss
        bevel.technique = .chiselHard
        bevel.usesContour = true
        bevel.contour = .ring
        bevel.usesTexture = true
        bevel.texture = .dots
        effects.bevel = bevel
        effects.satin = SatinEffect()
        effects.patternOverlay = PatternOverlayEffect(pattern: .grid, scale: 250)
        effects.fillOpacity = 0.25
        effects.shadow = ShadowEffect(spread: 30, contour: .cone, blendMode: .multiply)
        let decoded = try JSONDecoder().decode(LayerEffects.self, from: JSONEncoder().encode(effects))
        #expect(decoded == effects && decoded.isValid)
        let older = "{\"stroke\":{\"size\":4,\"red\":0,\"green\":0,\"blue\":0,\"opacity\":1,\"inside\":false}}"
        let read = try JSONDecoder().decode(LayerEffects.self, from: Data(older.utf8))
        #expect(read.stroke?.blendMode == nil && read.stroke?.centered == nil && read.bevel == nil && read.fill == 1)
    }

    @Test func fillOpacityFadesThePixelsButNotTheOverlay() throws {
        let image = try square()
        var effects = LayerEffects(fillOpacity: 0)
        var result = try LayerEffectsRenderer.render(image, mask: nil, effects: effects)
        let inset = Int(result.inset)
        #expect(try pixel(result.image, inset + 30, inset + 30).alpha == 0, "no fill leaves nothing of the pixels")
        effects.colorOverlay = ColorOverlayEffect(red: 1, green: 0, blue: 0, opacity: 1)
        result = try LayerEffectsRenderer.render(image, mask: nil, effects: effects)
        let middle = try pixel(result.image, inset + 30, inset + 30)
        #expect(middle.alpha == 255 && middle.red == 255 && middle.green == 0, "the overlay keeps its strength")
    }

    @Test func blendModesMixWithThePixelsUnderneath() throws {
        let image = try square(color: PaletteColor(red: 1, green: 0.5, blue: 0))
        let effects = LayerEffects(colorOverlay: ColorOverlayEffect(red: 0.5, green: 0.5, blue: 1, opacity: 1, blendMode: .multiply))
        let result = try LayerEffectsRenderer.render(image, mask: nil, effects: effects)
        let middle = try pixel(result.image, Int(result.inset) + 30, Int(result.inset) + 30)
        #expect(abs(middle.red - 128) <= 2 && abs(middle.green - 64) <= 2 && middle.blue == 0)
        #expect(LayerStyleBlend.apply(.screen, backdrop: SIMD3(0.5, 0.5, 0.5), source: SIMD3(0.5, 0.5, 0.5)).x == 0.75)
        #expect(LayerStyleBlend.apply(.difference, backdrop: SIMD3(1, 0, 0.5), source: SIMD3(0.25, 0.25, 0.5)) == SIMD3(0.75, 0.25, 0))
    }

    /// Light from the top left brightens the top and left edges of a raised bevel and darkens the bottom and right.
    @Test func innerBevelLightsOneSideAndShadesTheOther() throws {
        let image = try square(color: PaletteColor(red: 0.5, green: 0.5, blue: 0.5))
        var bevel = BevelEffect()
        bevel.size = 8
        bevel.angle = 135
        bevel.highlightOpacity = 1
        bevel.shadowOpacity = 1
        bevel.highlightMode = .normal
        bevel.shadowMode = .normal
        let result = try LayerEffectsRenderer.render(image, mask: nil, effects: LayerEffects(bevel: bevel))
        let inset = Int(result.inset)
        let topLeft = try pixel(result.image, inset + 17, inset + 17)
        let bottomRight = try pixel(result.image, inset + 42, inset + 42)
        let middle = try pixel(result.image, inset + 30, inset + 30)
        #expect(topLeft.red > middle.red + 20, "top-left edge is lit: \(topLeft) vs \(middle)")
        #expect(bottomRight.red + 20 < middle.red, "bottom-right edge is shaded: \(bottomRight) vs \(middle)")
        #expect(abs(middle.red - 128) <= 3, "the flat top keeps its color")
        #expect(try pixel(result.image, 2, 2).alpha == 0, "an inner bevel stays inside")

        bevel.style = .outerBevel
        let outer = try LayerEffectsRenderer.render(image, mask: nil, effects: LayerEffects(bevel: bevel))
        let outside = Int(outer.inset) + 13
        #expect(try pixel(outer.image, outside, Int(outer.inset) + 30).alpha > 0, "an outer bevel reaches outside")
    }

    @Test func oversizedBevelUsesTheLayerSizeWithoutEffectPadding() throws {
        let image = try square(size: 20, inner: 20, color: PaletteColor(red: 0.5, green: 0.5, blue: 0.5))
        var bevel = BevelEffect()
        bevel.size = 80
        bevel.style = .outerBevel
        let effects = LayerEffects(bevel: bevel)
        let result = try LayerEffectsRenderer.render(image, mask: nil, effects: effects)
        let context = try BrushRaster.context(width: result.image.width, height: result.image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: result.inset, y: result.inset, width: 20, height: 20),
                         mask: false, context: context)
        let padded = try #require(context.makeImage())
        let expected = try LayerStyleRenderer.render(padded, effects: effects,
            origin: CGPoint(x: -result.inset, y: -result.inset), fullSize: CGSize(width: 20, height: 20))
        let actualPixels = try BrushRaster.copy(result.image)
        let expectedPixels = try BrushRaster.copy(expected)
        let actualData = try #require(actualPixels.data)
        let expectedData = try #require(expectedPixels.data)
        #expect(Data(bytes: actualData, count: actualPixels.bytesPerRow * actualPixels.height)
            == Data(bytes: expectedData, count: expectedPixels.bytesPerRow * expectedPixels.height))
    }

    @Test(arguments: BevelEffect.Technique.allCases)
    func smallShapeKeepsAFlatCenter(technique: BevelEffect.Technique) throws {
        let image = try square(size: 24, inner: 24, color: PaletteColor(red: 0.5, green: 0.5, blue: 0.5))
        var bevel = BevelEffect()
        bevel.technique = technique
        bevel.size = 250
        let result = try LayerEffectsRenderer.render(image, mask: nil, effects: LayerEffects(bevel: bevel))
        let inset = Int(result.inset)
        let middle = try pixel(result.image, inset + 12, inset + 12)
        #expect(abs(middle.red - 128) <= 5)
        #expect(middle.alpha == 255)
    }

    @Test func layerLockPreventsEditsAndSurvivesSaving() async throws {
        let session = EditorSession()
        session.createDocument(width: 60, height: 60)
        let image = try square()
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Square"))
        let id = try #require(session.activeLayerID)
        let original = try #require(session.activeLayer)
        session.toggleSelectedLayerLock()
        #expect(session.canSelectLayers && !session.canEditLayers)
        session.nudgeLayer(dx: 10, dy: 10)
        session.setLayerOpacity(0.2)
        session.deleteSelectedLayers()
        #expect(session.activeLayer?.transform == original.transform)
        #expect(session.activeLayer?.opacity == original.opacity)
        #expect(session.activeLayer?.id == id)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Locked-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(try #require(session.projectSnapshot()), to: url)
        let loaded = try await ProjectStore.shared.load(from: url)
        #expect(loaded.manifest.version == 13)
        let reopened = EditorSession()
        reopened.installProject(loaded, from: url)
        #expect(reopened.activeLayer?.isLocked == true && !reopened.canEditLayers)
        session.undo()
        #expect(session.activeLayer?.isLocked == false && session.canEditLayers)
        reopened.toggleSelectedLayerLock()
        #expect(reopened.canEditLayers)
    }

    @Test func lockedFolderProtectsChildrenUntilTheFolderIsUnlocked() throws {
        let session = EditorSession()
        session.createDocument(width: 60, height: 60)
        let image = try square()
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Square"))
        let child = try #require(session.activeLayerID)
        session.groupSelectedLayers()
        let folder = try #require(session.activeLayerID)
        session.toggleSelectedLayerLock()
        session.selectLayer(child)
        #expect(session.layerIsLocked(child))
        #expect(!session.canToggleSelectedLayerLock && !session.canEditLayers)
        session.toggleSelectedLayerLock()
        #expect(session.activeLayer?.isLocked == false)
        session.selectLayer(folder)
        session.toggleSelectedLayerLock()
        session.selectLayer(child)
        #expect(session.canToggleSelectedLayerLock && session.canEditLayers)
    }

    @Test func lockedLayerDoesNotBlockCreatingAnotherLayer() throws {
        let session = EditorSession()
        session.createDocument(width: 60, height: 60, emptyLayer: true)
        let locked = try #require(session.activeLayerID)
        session.toggleSelectedLayerLock()
        session.addBlankLayer()
        #expect(session.document?.layers.count == 2)
        #expect(session.activeLayerID != locked && session.canEditLayers)
        session.selectLayer(locked)
        session.addAdjustment(.invert)
        #expect(session.document?.layers.count == 3)
        #expect(session.activeLayer?.adjustment?.kind == .invert)
        #expect(session.layerIsLocked(locked))
    }

    @Test func satinAndPatternDrawOnlyInsideTheShape() throws {
        let image = try square()
        var effects = LayerEffects(satin: SatinEffect())
        effects.satin?.opacity = 1
        effects.satin?.blendMode = .normal
        var result = try LayerEffectsRenderer.render(image, mask: nil, effects: effects)
        #expect(try pixel(result.image, 0, 0).alpha == 0)
        var pattern = PatternOverlayEffect(pattern: .checker, scale: 100)
        pattern.red = 1; pattern.green = 0; pattern.blue = 0
        pattern.paperRed = 0; pattern.paperGreen = 0; pattern.paperBlue = 1
        result = try LayerEffectsRenderer.render(image, mask: nil, effects: LayerEffects(patternOverlay: pattern))
        let inset = Int(result.inset)
        // Layer pixel (16, 16) is in the checkerboard's first ink cell; (24, 16) is paper.
        let ink = try pixel(result.image, inset + 16, inset + 16), paper = try pixel(result.image, inset + 24, inset + 16)
        #expect(ink.red == 255 && ink.blue == 0 && paper.blue == 255 && paper.red == 0)
        #expect(try pixel(result.image, 1, 1).alpha == 0)
    }

    @Test func layerStyleDialogIsOneUndoStepAndCancelPutsItBack() throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 80, emptyLayer: true)
        session.selectTool(.shape)
        session.beginShape(at: CGPoint(x: 10, y: 10))
        session.dragShape(to: CGPoint(x: 60, y: 60), square: false, fromCenter: false)
        session.finishShape()
        let id = try #require(session.activeLayerID)
        let count = session.history.undoCount

        session.openLayerStyle()
        #expect(session.layerStyle?.layerID == id && !session.canEditLayers)
        session.setLayerStyleEffect(.bevel, on: true)
        session.setLayerStyleEffect(.shadow, on: true)
        session.changeLayerStyle { $0.fillOpacity = 0.5 }
        session.setLayerStyleOpacity(0.4)
        #expect(session.activeLayer?.effects?.bevel != nil && session.activeLayer?.opacity == 0.4)
        #expect(session.activeLayer?.effects?.shadow?.blendMode == .multiply, "new effects take Photoshop's modes")
        #expect(session.history.undoCount == count, "nothing is recorded while the dialog is open")
        session.finishLayerStyle(commit: false)
        #expect(session.activeLayer?.effects == nil && session.activeLayer?.opacity == 1 && session.history.undoCount == count)

        session.addEffect(.satin)
        #expect(session.layerStyle?.page == .effect(.satin) && session.activeLayer?.effects?.satin != nil)
        session.setLayerStyleEffect(.patternOverlay, on: true)
        session.finishLayerStyle(commit: true)
        #expect(session.history.undoCount == count + 1 && session.layerStyle == nil)
        #expect(session.activeLayer?.effects?.kinds == [.satin, .patternOverlay])
        session.undo()
        #expect(session.activeLayer?.effects == nil)
        session.redo()
        #expect(session.activeLayer?.effects?.satin != nil)
    }
}
