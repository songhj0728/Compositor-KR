import AppKit
import SwiftUI

nonisolated enum ShapeKind: String, CaseIterable, Codable, Sendable {
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case line = "Line"
    /// `rawValue` as a localizable display name; `rawValue` itself stays the stable, unlocalized identifier.
    var displayName: LocalizedStringKey {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        }
    }
    /// The shape filling `rect`. A rectangle's corners round by `cornerRadius`, at most half its shorter
    /// side (so a large radius makes a pill); ellipses ignore it. A line runs corner to corner and is stroked,
    /// not filled (see `linePath`).
    func path(in rect: CGRect, cornerRadius: CGFloat = 0) -> CGPath {
        if self == .ellipse { return CGPath(ellipseIn: rect, transform: nil) }
        let radius = min(max(0, cornerRadius), rect.width / 2, rect.height / 2)
        guard radius > 0 else { return CGPath(rect: rect, transform: nil) }
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

/// What a shape layer draws, kept so the shape can be drawn again at a new size.
nonisolated struct LayerShapeStyle: Codable, Equatable, Sendable {
    var kind: ShapeKind
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    /// Document pixels, whatever size the shape is scaled to.
    var cornerRadius: CGFloat
    /// A line's thickness, and its two ends as fractions of the layer's box (0–1), so the line lands on exactly the
    /// points it was dragged between and still redraws correctly at another size. Nil on other shapes.
    var lineWidth: CGFloat? = nil
    var start: CGPoint? = nil
    var end: CGPoint? = nil
    /// Whether the inside is filled; missing means filled, as every shape was before strokes.
    var filled: Bool? = nil
    /// An outline drawn just inside the edge of a rectangle or ellipse, in document pixels, and its color. Missing (or
    /// a width of 0) means no outline.
    var strokeWidth: CGFloat? = nil
    var strokeRed: CGFloat? = nil
    var strokeGreen: CGFloat? = nil
    var strokeBlue: CGFloat? = nil
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var fills: Bool { filled ?? true }
    var strokeColor: PaletteColor { PaletteColor(red: strokeRed ?? 0, green: strokeGreen ?? 0, blue: strokeBlue ?? 0) }
    var strokeSize: CGFloat { kind == .line ? 0 : max(0, strokeWidth ?? 0) }
    mutating func setColor(_ color: PaletteColor) { red = color.red; green = color.green; blue = color.blue }
    mutating func setStrokeColor(_ color: PaletteColor) { strokeRed = color.red; strokeGreen = color.green; strokeBlue = color.blue }
}

/// A layer made with the Shape tool. Its pixels are an ordinary raster, so it clips, masks, blends and filters like
/// any layer; `image` is the raster the shape drew. Once anything else changes those pixels (painting, a filter),
/// the layer's image is no longer this one and the layer is plain pixels from then on.
nonisolated struct LayerShape: Equatable, @unchecked Sendable {
    var style: LayerShapeStyle
    let image: CGImage
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.style == rhs.style && lhs.image === rhs.image }
    static func loaded(_ style: LayerShapeStyle?, image: CGImage?) -> LayerShape? {
        guard let style, let image else { return nil }
        return LayerShape(style: style, image: image)
    }
}

extension ImageLayer {
    /// The shape this layer still is: nil once its pixels were edited some other way.
    var liveShape: LayerShape? {
        guard let shape, let image = asset?.image, image === shape.image else { return nil }
        return shape
    }
}

/// A click with the Shape tool: the dialog asking for the shape's size is open.
struct ShapeSizeRequest: Equatable, Identifiable {
    let id = UUID()
    let kind: ShapeKind
    /// Where the click was, in document pixels.
    let point: CGPoint
}

/// A shape being dragged out with the Shape tool, in whole document pixels.
struct ShapeDraft: Equatable {
    let kind: ShapeKind
    let anchor: CGPoint
    var rect: CGRect
    /// Where a line is being dragged to, so its ends stay exactly where they were put.
    var end: CGPoint? = nil
    /// Document pixels, fixed when the drag starts; rectangles only.
    var cornerRadius: CGFloat = 0
}

extension EditorSession {
    /// Pixels one shape layer may hold, the same budget as an import.
    nonisolated static let maxShapePixels = DocumentLimits.maxSurfacePixels

    func beginShape(at point: CGPoint) {
        guard tool == .shape, canEditLayers, point.x.isFinite, point.y.isFinite else { return }
        let anchor = CGPoint(x: point.x.rounded(), y: point.y.rounded())
        shapeDraft = ShapeDraft(kind: shapeKind, anchor: anchor, rect: CGRect(origin: anchor, size: .zero),
                                cornerRadius: shapeKind == .rectangle ? CGFloat(shapeCornerRadius) : 0)
    }

    /// The line being dragged, from where it began to where the pointer is, in document pixels.
    var shapeLineEnds: (start: CGPoint, end: CGPoint)? {
        guard let draft = shapeDraft, draft.kind == .line, let end = draft.end else { return nil }
        return (draft.anchor, end)
    }

    /// Shift makes a square or circle; Option grows the shape from its center, as in Photoshop.
    func dragShape(to point: CGPoint, square: Bool, fromCenter: Bool) {
        guard var draft = shapeDraft, point.x.isFinite, point.y.isFinite else { return }
        // Shift on a line snaps its angle to eighths of a turn — flat, upright, or 45° — rather than squaring a box.
        if draft.kind == .line, square {
            let dx = point.x - draft.anchor.x, dy = point.y - draft.anchor.y
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            let snapped = CGPoint(x: draft.anchor.x + cos(angle) * length, y: draft.anchor.y + sin(angle) * length)
            draft.end = snapped
            draft.rect = DragBox.rect(from: draft.anchor, to: snapped, square: false, fromCenter: fromCenter)
            shapeDraft = draft
            return
        }
        if draft.kind == .line { draft.end = point }
        draft.rect = DragBox.rect(from: draft.anchor, to: point, square: square, fromCenter: fromCenter)
        shapeDraft = draft
    }

    func cancelShape() {
        if shapeDraft != nil { shapeDraft = nil }
    }

    /// Shift-U (and Tab): the Shape tool steps through Rectangle, Ellipse and Line.
    func toggleShapeKind() {
        cancelShape()
        let kinds = ShapeKind.allCases
        shapeKind = kinds[((kinds.firstIndex(of: shapeKind) ?? 0) + 1) % kinds.count]
    }

    /// Makes the dragged shape on a new layer above the active one, in the Shape tool's fill, outline and line
    /// width, in one undo step. A click without a drag asks for a size instead (see `ShapeSizeRequest`); the
    /// selection is left alone.
    func finishShape() {
        guard let draft = shapeDraft else { return }
        shapeDraft = nil
        let clicked = draft.kind == .line ? (draft.end ?? draft.anchor) == draft.anchor : draft.rect.width < 1 && draft.rect.height < 1
        if clicked {
            if canEditLayers, document != nil { shapeSizeRequest = ShapeSizeRequest(kind: draft.kind, point: draft.anchor) }
            return
        }
        var rect = draft.rect
        var ends: (start: CGPoint, end: CGPoint)?
        if draft.kind == .line { ends = (draft.anchor, draft.end ?? draft.anchor) }
        makeShape(draft.kind, rect: &rect, ends: ends, cornerRadius: draft.cornerRadius)
    }

    /// The shape of the size asked for by a click: centered on the canvas with From Center, on the click otherwise.
    /// A line runs from the box's top-left corner to its bottom-right one, so a height of 0 draws it flat.
    func finishShapeSize(width: Int, height: Int, fromCenter: Bool) {
        guard let request = shapeSizeRequest else { return }
        shapeSizeRequest = nil
        guard let document, width >= 0, height >= 0 else { return }
        let center = fromCenter ? CGPoint(x: CGFloat(document.width) / 2, y: CGFloat(document.height) / 2) : request.point
        let origin = CGPoint(x: (center.x - CGFloat(width) / 2).rounded(), y: (center.y - CGFloat(height) / 2).rounded())
        var rect = CGRect(origin: origin, size: CGSize(width: width, height: height))
        shapeSizeWidth = width
        shapeSizeHeight = height
        shapeSizeFromCenter = fromCenter
        if request.kind == .line {
            guard width > 0 || height > 0 else { return }
            makeShape(.line, rect: &rect, ends: (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)), cornerRadius: 0)
        } else {
            guard width >= 1, height >= 1 else { return }
            makeShape(request.kind, rect: &rect, ends: nil, cornerRadius: request.kind == .rectangle ? CGFloat(shapeCornerRadius) : 0)
        }
    }

    func cancelShapeSize() { shapeSizeRequest = nil }

    /// The Shape tool's own look for the next shape: its fill, outline and line width.
    func shapeToolStyle(_ kind: ShapeKind, cornerRadius: CGFloat) -> LayerShapeStyle {
        var style = LayerShapeStyle(kind: kind, red: shapeFillColor.red, green: shapeFillColor.green, blue: shapeFillColor.blue,
                                    cornerRadius: cornerRadius, lineWidth: kind == .line ? CGFloat(shapeLineWidth) : nil)
        if kind != .line {
            style.filled = shapeFills ? nil : false
            if shapeStrokeWidth > 0 {
                style.strokeWidth = CGFloat(shapeStrokeWidth)
                style.setStrokeColor(shapeStrokeColor)
            }
        }
        return style
    }

    /// A shape on a new layer covering `rect` (a line's box grows by room for its own thickness and round ends).
    private func makeShape(_ kind: ShapeKind, rect: inout CGRect, ends: (start: CGPoint, end: CGPoint)?, cornerRadius: CGFloat) {
        let thickness = CGFloat(shapeLineWidth)
        if kind == .line, let ends {
            let from = ends.start, to = ends.end
            rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                          width: abs(to.x - from.x), height: abs(to.y - from.y)).insetBy(dx: -thickness / 2, dy: -thickness / 2)
        }
        guard canEditLayers, document != nil, rect.width >= 1, rect.height >= 1 else { return }
        guard Int(rect.width) * Int(rect.height) <= Self.maxShapePixels else {
            brushError = "That shape is too large. A shape can cover up to \(DocumentLimits.maxSurfaceMegapixels) megapixels."
            return
        }
        do {
            // The ends as fractions of the box, so a scaled line still runs between the same two places.
            let box = rect
            func unit(_ point: CGPoint) -> CGPoint {
                CGPoint(x: box.width > 0 ? (point.x - box.minX) / box.width : 0.5,
                        y: box.height > 0 ? (point.y - box.minY) / box.height : 0.5)
            }
            var style = shapeToolStyle(kind, cornerRadius: cornerRadius)
            style.start = ends.map { unit($0.start) }
            style.end = ends.map { unit($0.end) }
            let image = try Self.shapeImage(style, size: rect.size)
            addPixelLayer(image, at: rect.origin, name: nextShapeName(kind), editName: kind.rawValue,
                          dropsSelection: false, shape: LayerShape(style: style, image: image))
        } catch { brushError = error.localizedDescription }
    }

    /// The active layer when it is still a shape the Shape tool made.
    var activeShape: LayerShape? { activeLayer?.liveShape }

    /// Changes the Shape tool's look, and the selected shape's with it, so the shape just made (or any shape picked in
    /// the Layers panel) takes a new fill, outline or line width. One undo step for the shape; the tool remembers
    /// the setting for the shapes after it.
    func changeShapeStyle(name: String = "Shape Style", _ change: (inout LayerShapeStyle) -> Void) {
        guard let index = document?.layers.firstIndex(where: { $0.id == activeLayerID }),
              let layer = document?.layers[index], let shape = layer.liveShape, let asset = layer.asset, canEditLayers else { return }
        var style = shape.style
        change(&style)
        guard style != shape.style else { return }
        let width = max(1, Int(layer.transform.size.width.rounded())), height = max(1, Int(layer.transform.size.height.rounded()))
        guard width * height <= Self.maxShapePixels,
              let image = try? Self.shapeImage(style, size: CGSize(width: width, height: height)),
              let thumbnail = try? PixelInvert.thumbnail(of: image) else { return }
        finishOpacityEdit()
        beginEdit(name)
        // A mask that follows the layer's pixel grid stays exactly where it is if that grid changes size.
        if let mask = layer.mask, mask.placement == nil, asset.image.width != width || asset.image.height != height {
            document?.layers[index].mask?.placement = layer.maskTransform
        }
        document?.layers[index].asset = ImportedImage(image: image, thumbnail: thumbnail, name: asset.name)
        document?.layers[index].shape = LayerShape(style: style, image: image)
        endEdit()
    }

    /// The fill the Shape tool's bar shows: the selected shape's, otherwise the next shape's.
    var shapeBarFill: PaletteColor { activeShape?.style.color ?? shapeFillColor }
    var shapeBarFills: Bool { activeShape.map { $0.style.kind == .line || $0.style.fills } ?? shapeFills }
    var shapeBarStroke: PaletteColor { activeShape.map { $0.style.strokeSize > 0 ? $0.style.strokeColor : shapeStrokeColor } ?? shapeStrokeColor }
    var shapeBarStrokeWidth: Double { activeShape.map { Double($0.style.strokeSize) } ?? shapeStrokeWidth }
    var shapeBarLineWidth: Double { activeShape?.style.lineWidth.map { Double($0) } ?? shapeLineWidth }

    func setShapeFill(_ color: PaletteColor) {
        shapeFillColor = color
        changeShapeStyle(name: "Shape Fill") { $0.setColor(color) }
    }
    func setShapeFills(_ fills: Bool) {
        shapeFills = fills
        changeShapeStyle(name: "Shape Fill") { if $0.kind != .line { $0.filled = fills ? nil : false } }
    }
    func setShapeStroke(_ color: PaletteColor) {
        shapeStrokeColor = color
        changeShapeStyle(name: "Shape Stroke") { style in
            guard style.kind != .line else { return }
            style.setStrokeColor(color)
            if style.strokeSize == 0, self.shapeStrokeWidth > 0 { style.strokeWidth = CGFloat(self.shapeStrokeWidth) }
        }
    }
    func setShapeStrokeWidth(_ width: Double) {
        let width = width.isFinite ? min(1000, max(0, width.rounded())) : 0
        shapeStrokeWidth = width
        changeShapeStyle(name: "Shape Stroke") { style in
            guard style.kind != .line else { return }
            style.strokeWidth = width > 0 ? CGFloat(width) : nil
            if width > 0, style.strokeRed == nil { style.setStrokeColor(self.shapeStrokeColor) }
        }
    }
    func setShapeLineWidth(_ width: Double) {
        let width = width.isFinite ? min(5000, max(1, width.rounded())) : 4
        shapeLineWidth = width
        changeShapeStyle(name: "Line Width") { style in
            guard style.kind == .line else { return }
            style.lineWidth = CGFloat(width)
        }
    }
    func openShapeColorPicker(stroke: Bool) {
        guard canEditPalette, colorPicker == nil else { return }
        colorPicker = ColorPickerState(target: .shape(stroke: stroke), original: stroke ? shapeBarStroke : shapeBarFill)
    }
    /// "Rectangle 1", "Ellipse 2", … skipping names already in the document.
    func nextShapeName(_ kind: ShapeKind) -> String {
        let names = Set(document?.layers.map(\.name) ?? [])
        var number = 1
        while names.contains("\(kind.rawValue) \(number)") { number += 1 }
        return "\(kind.rawValue) \(number)"
    }

    /// A shape layer scaled to a new size draws its shape again at that size, so a rounded corner keeps its radius
    /// instead of stretching. Part of the edit that changed the size.
    func redrawShape(at index: Int) {
        guard let layer = document?.layers[index], let shape = layer.liveShape, let asset = layer.asset else { return }
        let width = max(1, Int(layer.transform.size.width.rounded())), height = max(1, Int(layer.transform.size.height.rounded()))
        guard width != asset.image.width || height != asset.image.height, width * height <= Self.maxShapePixels,
              let image = try? Self.shapeImage(shape.style, size: CGSize(width: width, height: height)),
              let thumbnail = try? PixelInvert.thumbnail(of: image) else { return }
        // A mask that follows the layer's pixel grid stays exactly where it is while that grid changes size.
        if let mask = layer.mask, mask.placement == nil { document?.layers[index].mask?.placement = layer.maskTransform }
        document?.layers[index].asset = ImportedImage(image: image, thumbnail: thumbnail, name: asset.name)
        document?.layers[index].shape = LayerShape(style: shape.style, image: image)
    }

    /// While a rounded rectangle is being scaled, the shape drawn at the size it's being dragged to, so its corners
    /// keep their radius during the drag rather than only once it's applied. At most 2048 pixels across (the radius
    /// scales down with it); nil for any other layer, which just stretches until the redraw at commit.
    func shapeTransformPreview(for layer: ImageLayer, transform: LayerTransform) -> CGImage? {
        guard transformEdit != nil, let shape = layer.liveShape, shape.style.kind == .rectangle, shape.style.cornerRadius > 0 else {
            if !shapeTransformPreviewCache.isEmpty, transformEdit == nil { shapeTransformPreviewCache = [:] }
            return nil
        }
        let size = transform.size
        guard size.width >= 1, size.height >= 1,
              abs(size.width - CGFloat(shape.image.width)) >= 0.5 || abs(size.height - CGFloat(shape.image.height)) >= 0.5 else { return nil }
        let factor = min(1, 2048 / max(size.width, size.height))
        let drawn = CGSize(width: max(1, (size.width * factor).rounded()), height: max(1, (size.height * factor).rounded()))
        if let cached = shapeTransformPreviewCache[layer.id], cached.size == drawn { return cached.image }
        var scaled = shape.style
        scaled.cornerRadius *= factor
        scaled.strokeWidth = scaled.strokeWidth.map { $0 * factor }
        guard let image = try? Self.shapeImage(scaled, size: drawn) else { return nil }
        shapeTransformPreviewCache[layer.id] = (drawn, image)
        return image
    }

    /// A shape layer's pixels at `size`: its fill, then its outline just inside the edge.
    nonisolated static func shapeImage(_ style: LayerShapeStyle, size: CGSize) throws -> CGImage {
        try shapeImage(style.kind, size: size, color: style.color, cornerRadius: style.cornerRadius,
                       lineWidth: style.lineWidth ?? 0, start: style.start, end: style.end, fills: style.fills,
                       stroke: style.strokeSize > 0 ? style.strokeColor : nil, strokeWidth: style.strokeSize)
    }

    /// The shape filling its box, anti-aliased where it curves.
    nonisolated static func shapeImage(_ kind: ShapeKind, size: CGSize, color: PaletteColor, cornerRadius: CGFloat = 0,
                           lineWidth: CGFloat = 0, start: CGPoint? = nil, end: CGPoint? = nil, fills: Bool = true,
                           stroke: PaletteColor? = nil, strokeWidth: CGFloat = 0) throws -> CGImage {
        let context = try BrushRaster.context(width: Int(size.width), height: Int(size.height), mask: false)
        let bounds = CGRect(origin: .zero, size: size)
        if kind == .line {
            // Corner to corner, inset by half the thickness so the stroke stays inside the layer.
            let thickness = max(1, lineWidth)
            context.setStrokeColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1))
            context.setLineWidth(thickness)
            context.setLineCap(.round)
            // The ends sit where they were dragged, as fractions of the box. Older lines (no ends stored) ran corner
            // to corner, inset by half their thickness.
            let inset = bounds.insetBy(dx: min(thickness, size.width) / 2, dy: min(thickness, size.height) / 2)
            let from = start.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) } ?? CGPoint(x: inset.minX, y: inset.minY)
            let to = end.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) } ?? CGPoint(x: inset.maxX, y: inset.maxY)
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
            guard let image = context.makeImage() else { throw ExportError.render }
            return image
        }
        if fills {
            context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1))
            context.addPath(kind.path(in: bounds, cornerRadius: cornerRadius))
            context.fillPath()
        }
        // Inside the edge, so the outline never grows the layer, as a Photoshop shape's Inside stroke.
        if let stroke, strokeWidth > 0 {
            let width = min(strokeWidth, min(size.width, size.height) / 2)
            context.setStrokeColor(CGColor(srgbRed: stroke.red, green: stroke.green, blue: stroke.blue, alpha: 1))
            context.setLineWidth(width)
            context.addPath(kind.path(in: bounds.insetBy(dx: width / 2, dy: width / 2), cornerRadius: max(0, cornerRadius - width / 2)))
            context.strokePath()
        }
        guard let image = context.makeImage() else { throw ExportError.render }
        return image
    }
}
