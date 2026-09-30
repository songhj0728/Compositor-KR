import AppKit
import ImageIO
import Testing
@testable import Compositor

/// Exported PSDs, read back by Compositor's own reader (layers, masks, clipping, adjustments) and by ImageIO (the
/// header, flattened image and profile, as other apps see them).
@MainActor
struct PSDExportTests {
    private let canvas = CGSize(width: 100, height: 80)

    private func solid(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, width: Int, height: Int) throws -> ImportedImage {
        let context = try BrushRaster.context(width: width, height: height, mask: false, space: CGColorSpace(name: CGColorSpace.sRGB)!)
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: "")
    }

    /// Left half hidden (black), right half shown (white).
    private func halfMask(width: Int, height: Int) throws -> LayerMask {
        let context = try BrushRaster.context(width: width, height: height, mask: true)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return LayerMask(asset: try LayerMask.asset(from: #require(context.makeImage())))
    }

    private func export(_ layers: [ImageLayer], options: PSDExportOptions = PSDExportOptions()) async throws -> (data: Data, result: PSDExportResult) {
        let session = EditorSession()
        var document = CanvasDocument(width: Int(canvas.width), height: Int(canvas.height), layers: layers, resolution: 300)
        document.guides = [CanvasGuide(id: UUID(), axis: .vertical, position: 25)]
        session.document = document
        let snapshot = try #require(session.projectSnapshot())
        let result = try await ImageExporter.shared.psd(snapshot, options: options)
        return (result.data, result)
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false, space: CGColorSpace(name: CGColorSpace.sRGB)!)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let p = y * context.bytesPerRow + x * 4
        return [data[p], data[p + 1], data[p + 2], data[p + 3]]
    }

    @Test func layersFoldersMasksAndClippingSurviveTheTrip() async throws {
        var base = ImageLayer(asset: try solid(1, 0, 0, width: 40, height: 30), origin: CGPoint(x: 10, y: 20))
        base.name = "배경 빨강"
        base.opacity = 0.5
        base.blendMode = .multiply
        base.mask = try halfMask(width: 40, height: 30)
        var clipped = ImageLayer(asset: try solid(0, 0, 1, width: 20, height: 20), origin: CGPoint(x: 15, y: 25))
        clipped.name = "Clipped"
        clipped.maskSourceID = base.id
        let folder = ImageLayer(id: UUID(), asset: nil, name: "Folder", isVisible: false,
                                transform: LayerTransform(origin: .zero, size: canvas), isGroup: true, opacity: 0.8)
        var inside = ImageLayer(asset: try solid(0, 1, 0, width: 10, height: 10), origin: CGPoint(x: 70, y: 5))
        inside.name = "Inside"
        inside.parentID = folder.id
        inside.blendMode = .linearDodge
        let (data, result) = try await export([base, clipped, inside, folder])
        #expect(result.notes.isEmpty)

        let read = try PSDReader.read(data)
        #expect(read.width == 100 && read.height == 80)
        let byName = Dictionary(uniqueKeysWithValues: read.layers.map { ($0.name, $0) })
        let red = try #require(byName["배경 빨강"])
        #expect(red.bounds == CGRect(x: 10, y: 20, width: 40, height: 30))
        #expect(abs(red.opacity - 0.5) < 0.01)
        #expect(red.blendMode == .multiply)
        #expect(red.mask != nil && red.maskEnabled)
        #expect(!red.clipping)
        let redImage = try #require(red.image)
        #expect(try pixel(redImage, x: 5, y: 5) == [255, 0, 0, 255])
        #expect(try #require(byName["Clipped"]).clipping)
        let group = try #require(byName["Folder"])
        #expect(group.isGroup && !group.isVisible && abs(group.opacity - 0.8) < 0.01)
        let child = try #require(byName["Inside"])
        #expect(child.parentID == group.id)
        #expect(child.blendMode == .linearDodge)
        // Bottom to top as in the project.
        #expect(read.layers.map(\.name) == ["배경 빨강", "Clipped", "Inside", "Folder"])
    }

    @Test func imageIOReadsTheFlattenedImageAndProfile() async throws {
        let layer = ImageLayer(asset: try solid(0, 0, 1, width: 100, height: 80), origin: .zero)
        let (data, _) = try await export([layer])
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 100 && image.height == 80)
        let center = try pixel(image, x: 50, y: 40)
        #expect(center[2] > 240 && center[0] < 15 && center[3] == 255)
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
        // ImageIO doesn't report a PSD's resolution; Compositor's reader does.
        #expect(abs(try PSDReader.read(data).resolution - 300) < 0.01)
    }

    @Test func rotatedAndScaledLayersArePlacedAsTheCanvasShowsThem() async throws {
        var layer = ImageLayer(asset: try solid(1, 1, 0, width: 20, height: 10), origin: CGPoint(x: 40, y: 30))
        layer.transform.size = CGSize(width: 40, height: 20)
        layer.transform.rotation = 90
        let (data, _) = try await export([layer])
        let record = try #require(try PSDReader.read(data).layers.first)
        // 40 × 20 turned a quarter: 20 wide and 40 tall about the same center (60, 40).
        #expect(record.bounds == CGRect(x: 50, y: 20, width: 20, height: 40))
        #expect(try pixel(#require(record.image), x: 10, y: 20)[3] == 255)
    }

    @Test func adjustmentLayersStayEditable() async throws {
        func adjustment(_ value: LayerAdjustment) -> ImageLayer {
            ImageLayer(id: UUID(), asset: nil, name: value.kind.rawValue, isVisible: true,
                       transform: LayerTransform(origin: .zero, size: canvas), adjustment: value)
        }
        var levels = LayerAdjustment(kind: .levels)
        levels.levels.ranges[0] = LevelRange(black: 20, gamma: 1.5, white: 230, outputBlack: 5, outputWhite: 250)
        levels.levels.ranges[2] = LevelRange(black: 0, gamma: 0.8, white: 255, outputBlack: 0, outputWhite: 255)
        var curves = LayerAdjustment(kind: .curves)
        curves.curves.channels[0] = [CurvePoint(x: 0, y: 10), CurvePoint(x: 128, y: 160), CurvePoint(x: 255, y: 240)]
        curves.curves.channels[3] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 255, y: 200)]
        var hsv = HueSaturationSettings(hue: 30, saturation: -20, lightness: 10)
        hsv.adjustments[.blues] = RangeAdjustment(hue: -15, saturation: 40, lightness: 0)
        var hue = LayerAdjustment(kind: .hsv)
        hue.hsvSettings = hsv
        var colorize = LayerAdjustment(kind: .hsv)
        colorize.hsvSettings = HueSaturationSettings(hue: 200, saturation: 60, lightness: -10, colorize: true)
        var exposure = LayerAdjustment(kind: .exposure)
        exposure.exposure = ExposureSettings(exposure: 1.5, offset: -0.1, gamma: 1.2)
        var balance = LayerAdjustment(kind: .colorBalance)
        balance.colorBalance = ColorBalanceSettings(shadowCyanRed: 10, midYellowBlue: -30, highlightMagentaGreen: 55, preserveLuminosity: false)
        var blackWhite = LayerAdjustment(kind: .blackWhite)
        blackWhite.blackWhite.tint = true
        var gradient = LayerAdjustment(kind: .gradientMap)
        gradient.gradientMap = GradientMapSettings(shadows: AdjustmentColor(red: 0.1, green: 0, blue: 0.3),
                                                   highlights: AdjustmentColor(red: 1, green: 0.9, blue: 0.5), reversed: true)
        let base = ImageLayer(asset: try solid(0.5, 0.5, 0.5, width: 100, height: 80), origin: .zero)
        let values = [levels, curves, hue, colorize, exposure, balance, LayerAdjustment(kind: .invert), blackWhite, gradient]
        let (data, result) = try await export([base] + values.map(adjustment))
        #expect(result.notes.isEmpty)
        let read = try PSDReader.read(data).layers
        #expect(read.count == 1 + values.count)
        let adjustments = read.dropFirst()
        #expect(adjustments.allSatisfy { $0.kind == .adjustment })

        let readLevels = try #require(adjustments[1].adjustment?.levels)
        #expect(readLevels.ranges[0] == levels.levels.ranges[0].normalized)
        #expect(readLevels.ranges[2] == levels.levels.ranges[2].normalized)
        #expect(adjustments[2].adjustment?.curves.channels[0] == curves.curves.channels[0])
        #expect(adjustments[2].adjustment?.curves.channels[3] == curves.curves.channels[3])
        let readHue = try #require(adjustments[3].adjustment?.resolvedHSV)
        #expect(readHue.adjustments[.master] == RangeAdjustment(hue: 30, saturation: -20, lightness: 10))
        #expect(readHue.adjustments[.blues] == RangeAdjustment(hue: -15, saturation: 40, lightness: 0))
        #expect(readHue.bands[.reds] == ColorRange.reds.defaultBand)
        let readColorize = try #require(adjustments[4].adjustment?.resolvedHSV)
        #expect(readColorize.colorize && readColorize.adjustments[.master] == RangeAdjustment(hue: 200, saturation: 60, lightness: -10))
        let readExposure = try #require(adjustments[5].adjustment?.exposure)
        #expect(abs(readExposure.exposure - 1.5) < 0.001 && abs(readExposure.offset + 0.1) < 0.001 && abs(readExposure.gamma - 1.2) < 0.001)
        #expect(adjustments[6].adjustment?.colorBalance == balance.colorBalance)
        #expect(adjustments[7].adjustment?.kind == .invert)
        // Black & White and Gradient Map aren't read back by Compositor, but are written in Photoshop's layout.
        #expect(adjustments[8].adjustment == nil && adjustments[9].adjustment == nil)
        let gradientData = PSDAdjustmentCoding.gradientMap(gradient.gradientMap)
        // Header 4, the name "Custom" 16, two 20-byte color stops, two 10-byte transparency stops, and 40 bytes of
        // Photoshop 6's trailing settings, with the three counts.
        #expect(gradientData.count == 124)
        #expect(PSDAdjustmentCoding.blackWhite(blackWhite.blackWhite).prefix(4) == Data([0, 0, 0, 16]))
    }

    @Test func adjustmentsPhotoshopLacksAreSavedAsTheirPixels() async throws {
        let base = ImageLayer(asset: try solid(0.2, 0.4, 0.6, width: 100, height: 80), origin: .zero)
        var invert = ImageLayer(id: UUID(), asset: nil, name: "Invert", isVisible: true,
                                transform: LayerTransform(origin: .zero, size: canvas), adjustment: LayerAdjustment(kind: .invert))
        var blur = ImageLayer(id: UUID(), asset: nil, name: "Blur", isVisible: true,
                              transform: LayerTransform(origin: .zero, size: canvas), adjustment: LayerAdjustment(kind: .gaussianBlur))
        invert.opacity = 1
        blur.opacity = 1
        let (data, result) = try await export([base, invert, blur])
        #expect(result.notes.contains { $0.layerName == "Blur" })
        let read = try PSDReader.read(data).layers
        #expect(read[1].kind == .adjustment)
        #expect(read[2].kind == .raster && read[2].image?.width == 100)

        // Unticked, even Invert is saved as pixels: the base inverted.
        let (flat, _) = try await export([base, invert], options: PSDExportOptions(editableAdjustments: false))
        let baked = try PSDReader.read(flat).layers[1]
        #expect(baked.kind == .raster)
        let color = try pixel(#require(baked.image), x: 50, y: 40)
        #expect(abs(Int(color[0]) - 204) <= 2 && abs(Int(color[1]) - 153) <= 2 && abs(Int(color[2]) - 102) <= 2)
    }

    @Test func effectsAreMergedAndNonAdjacentClippingIsApplied() async throws {
        var base = ImageLayer(asset: try solid(1, 0, 0, width: 20, height: 20), origin: CGPoint(x: 0, y: 0))
        base.name = "Base"
        var between = ImageLayer(asset: try solid(0, 1, 0, width: 10, height: 10), origin: CGPoint(x: 80, y: 60))
        between.name = "Between"
        var far = ImageLayer(asset: try solid(0, 0, 1, width: 40, height: 40), origin: CGPoint(x: 0, y: 0))
        far.name = "Far"
        far.maskSourceID = base.id
        var effects = LayerEffects()
        effects.stroke = StrokeEffect()
        var stroked = ImageLayer(asset: try solid(1, 1, 1, width: 10, height: 10), origin: CGPoint(x: 50, y: 30))
        stroked.name = "Stroked"
        stroked.effects = effects
        let (data, result) = try await export([base, between, far, stroked])
        #expect(result.notes.contains { $0.layerName == "Far" })
        let read = try PSDReader.read(data).layers
        let farRecord = try #require(read.first { $0.name == "Far" })
        #expect(!farRecord.clipping)
        let farImage = try #require(farRecord.image)
        // Inside the base's 20 × 20 it shows; past it, it's cut away.
        #expect(try pixel(farImage, x: 10, y: 10)[3] == 255)
        #expect(try pixel(farImage, x: 30, y: 30)[3] == 0)
        // The stroke stays Photoshop's own Layer Style, over the layer's own 10 × 10 pixels.
        let styled = try #require(read.first { $0.name == "Stroked" })
        #expect(styled.bounds.width == 10 && styled.kind == .effects)
        #expect(!result.notes.contains { $0.layerName == "Stroked" })
        // Unticked, the stroke is drawn around the layer, so its pixels reach past it.
        let (flat, flatResult) = try await export([base, between, far, stroked], options: PSDExportOptions(editableTextAndStyles: false))
        #expect(flatResult.notes.contains { $0.layerName == "Stroked" })
        let merged = try #require(PSDReader.read(flat).layers.first { $0.name == "Stroked" })
        #expect(merged.bounds.width > 10 && merged.kind == .raster)
    }

    /// Text is written as a Photoshop type layer that reads back as the same text, colors and faces letter by letter.
    @Test func textIsWrittenAsEditableType() async throws {
        let session = EditorSession()
        session.createDocument(width: 400, height: 300, emptyLayer: true)
        session.selectTool(.type)
        session.beginText(at: CGPoint(x: 40, y: 80))
        session.textDraft?.style.content = "Hello\nType"
        session.textDraft?.style.fontSize = 36
        session.textDraft?.style.setColor(PaletteColor(red: 1, green: 0, blue: 0), in: NSRange(location: 6, length: 4))
        #expect(session.finishText())
        let snapshot = try #require(session.projectSnapshot())
        let result = try await ImageExporter.shared.psd(snapshot)
        #expect(!result.notes.contains { $0.message.contains("Text") })
        let parsed = try #require(PSDReader.read(result.data).layers.first { $0.text != nil }?.text)
        #expect(parsed.style.content == "Hello\nType")
        #expect(abs(parsed.style.fontSize - 36) < 0.01)
        #expect(parsed.style.color(at: 0) == PaletteColor(red: 0, green: 0, blue: 0))
        #expect(parsed.style.color(at: 7) == PaletteColor(red: 1, green: 0, blue: 0))
        let layer = try #require(session.activeLayer)
        let baseline = PSDText.baseline(layer.liveText!.style, image: layer.transform.size)
        #expect(abs(parsed.documentAnchor.x - (layer.transform.origin.x + LayerTextStyle.padding)) < 0.5)
        #expect(abs(parsed.documentAnchor.y - (layer.transform.origin.y + baseline)) < 0.5)
    }

    /// Photoshop's matrix maps text space row-vector style: a 90° clockwise turn sends its x axis straight down.
    @Test func rotatedTextKeepsItsTurn() throws {
        var style = LayerTextStyle()
        style.content = "Turn"
        let transform = LayerTransform(origin: CGPoint(x: 100, y: 100), size: CGSize(width: 200, height: 100), rotation: 90)
        let block = try #require(PSDTextWriter.block(style, transform: transform, width: 200, height: 100))
        let parsed = try #require(PSDText.parse(extra: ["TySh": block]))
        #expect(abs(parsed.rotation - 90) < 0.01)
    }

    /// Layer styles go to Photoshop as its own Layer Style and come back as the same effects.
    @Test func layerStylesRoundTripThroughPhotoshopsLayerStyle() async throws {
        var effects = LayerEffects()
        effects.shadow = ShadowEffect(angle: 135, distance: 7, blur: 9, opacity: 0.6, spread: 20, blendMode: .multiply)
        var bevel = BevelEffect()
        bevel.style = .emboss
        bevel.technique = .chiselSoft
        bevel.size = 12
        bevel.usesContour = true
        bevel.contour = .ring
        effects.bevel = bevel
        effects.satin = SatinEffect()
        effects.stroke = StrokeEffect(size: 3, red: 0, green: 0, blue: 1, opacity: 1, inside: false, centered: true)
        effects.fillOpacity = 0.4
        var layer = ImageLayer(asset: try solid(1, 0, 0, width: 20, height: 20), origin: CGPoint(x: 30, y: 30))
        layer.name = "Styled"
        layer.effects = effects
        let (data, _) = try await export([layer])
        let record = try #require(PSDReader.read(data).layers.first { $0.name == "Styled" })
        let read = try #require(record.effects)
        #expect(read.shadow?.angle == 135 && read.shadow?.distance == 7 && read.shadow?.blur == 9)
        #expect(read.shadow?.spread == 20 && read.shadow?.blendMode == .multiply)
        #expect(abs((read.shadow?.opacity ?? 0) - 0.6) < 0.001)
        #expect(read.bevel?.style == .emboss && read.bevel?.technique == .chiselSoft && read.bevel?.size == 12)
        #expect(read.bevel?.hasContour == true && read.bevel?.contour == .ring)
        #expect(read.satin == SatinEffect())
        #expect(read.stroke?.centered == true && read.stroke?.color == PaletteColor(red: 0, green: 0, blue: 1))
        #expect(abs(read.fill - 0.4) < 0.01)

        // A Pattern Overlay has no Photoshop form here, so that layer's effects are drawn into its pixels.
        layer.effects?.patternOverlay = PatternOverlayEffect()
        let (flat, result) = try await export([layer])
        #expect(result.notes.contains { $0.layerName == "Styled" })
        #expect(try #require(PSDReader.read(flat).layers.first { $0.name == "Styled" }).effects == nil)
    }
}
