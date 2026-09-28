import AppKit
import SwiftUI

/// The Liquify dialog's tools: how a stroke moves the pixels under the brush.
nonisolated enum LiquifyMode: String, CaseIterable, Sendable {
    case forwardWarp = "Forward Warp"
    case reconstruct = "Reconstruct"
    case twirlClockwise = "Twirl Clockwise"
    case pucker = "Pucker"
    case bloat = "Bloat"
    case pushLeft = "Push Left"
    /// `rawValue` as a localizable display name; `rawValue` itself stays the stable, unlocalized identifier.
    var displayName: LocalizedStringKey {
        switch self {
        case .forwardWarp: return "Forward Warp"
        case .reconstruct: return "Reconstruct"
        case .twirlClockwise: return "Twirl Clockwise"
        case .pucker: return "Pucker"
        case .bloat: return "Bloat"
        case .pushLeft: return "Push Left"
        }
    }
    var symbol: String {
        switch self {
        case .forwardWarp: return "hand.point.up.left"
        case .reconstruct: return "clock.arrow.circlepath"
        case .twirlClockwise: return "arrow.clockwise"
        case .pucker: return "arrow.down.right.and.arrow.up.left"
        case .bloat: return "arrow.up.left.and.arrow.down.right"
        case .pushLeft: return "arrow.left"
        }
    }
    /// Tools that keep working while the brush is held still, as well as when it moves.
    var worksInPlace: Bool { self == .reconstruct || self == .twirlClockwise || self == .pucker || self == .bloat }
}

/// The Liquify dialog's brush, in the layer's own pixels.
nonisolated struct LiquifyBrush: Equatable, Sendable {
    static let sizeRange: ClosedRange<Double> = 1...3000
    var size: Double = 100
    /// How firmly the brush's edge works, 0–100: 0 fades out from the center, 100 is even to the rim.
    var density: Double = 50
    /// How far each dab moves pixels, 1–100.
    var pressure: Double = 100
    /// How fast the in-place tools work while the brush is held still, 0–100.
    var rate: Double = 50
}

/// One stroke, for undo: the part of the field it changed, as it was before and after.
nonisolated struct LiquifyStep: Sendable {
    let x0: Int, y0: Int, x1: Int, y1: Int
    let before: [Float]
    let after: [Float]
    var byteCount: Int { (before.count + after.count) * MemoryLayout<Float>.size }
}

/// The dialog's working copy: the layer's pixels, the displacement field strokes build up over them, and the
/// result, re-rendered only where dabs changed the field (see LiquifyPixels.h).
nonisolated final class LiquifyField {
    let width: Int
    let height: Int
    /// The result, drawn into as the field changes.
    let context: CGContext
    private let output: UnsafeMutablePointer<UInt8>
    private let source: UnsafeMutablePointer<UInt8>
    private let field: UnsafeMutablePointer<Float>
    /// The field as the last finished stroke left it, which the next stroke's undo step is taken from.
    private let checkpoint: UnsafeMutablePointer<Float>
    /// The pixels changed since the last render, and by the stroke in progress: x0, y0, x1, y1, empty when x1 < x0.
    private var dirty = [0, 0, -1, -1]
    private var strokeRect = [0, 0, -1, -1]

    /// `image` drawn at `width` × `height`, with nothing moved yet.
    init(image: CGImage, width: Int, height: Int) throws {
        self.width = width; self.height = height
        context = try BrushRaster.context(width: width, height: height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), mask: false, context: context)
        guard let data = context.data else { throw ExportError.render }
        output = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        source = .allocate(capacity: width * height * 4)
        source.update(from: output, count: width * height * 4)
        field = .allocate(capacity: width * height * 2)
        field.initialize(repeating: 0, count: width * height * 2)
        checkpoint = .allocate(capacity: width * height * 2)
        checkpoint.initialize(repeating: 0, count: width * height * 2)
    }
    deinit {
        source.deallocate()
        field.deallocate()
        checkpoint.deallocate()
    }

    private static func union(_ a: [Int], _ b: [Int]) -> [Int] {
        guard a[2] >= a[0] else { return b }
        guard b[2] >= b[0] else { return a }
        return [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]
    }

    /// One dab at `to`, having travelled from `from`, in this copy's pixels.
    func dab(_ mode: LiquifyMode, from: CGPoint, to: CGPoint, diameter: CGFloat, hardness: CGFloat, strength: CGFloat) {
        var changed = [0, 0, -1, -1]
        let status = changed.withUnsafeMutableBufferPointer { rect in
            liquify_dab(field, width, height, Int32(LiquifyMode.allCases.firstIndex(of: mode) ?? 0),
                        from.x, from.y, to.x, to.y, diameter, hardness, strength, rect.baseAddress)
        }
        guard status == 0, changed[2] >= changed[0] else { return }
        dirty = Self.union(dirty, changed)
        strokeRect = Self.union(strokeRect, changed)
    }

    /// Brings `context` up to date with the field; false when nothing had changed.
    func renderChanges() -> Bool {
        guard dirty[2] >= dirty[0] else { return false }
        liquify_render(source, output, width, height, field, dirty[0], dirty[1], dirty[2], dirty[3])
        dirty = [0, 0, -1, -1]
        return true
    }

    /// The field's values over x0…x1, y0…y1 of `buffer`, row by row.
    private func region(of buffer: UnsafeMutablePointer<Float>, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> [Float] {
        let rowLength = (x1 - x0 + 1) * 2
        return [Float](unsafeUninitializedCapacity: rowLength * (y1 - y0 + 1)) { values, count in
            for y in y0...y1 { (values.baseAddress! + (y - y0) * rowLength).update(from: buffer + (y * width + x0) * 2, count: rowLength) }
            count = rowLength * (y1 - y0 + 1)
        }
    }
    private func write(_ values: [Float], to buffer: UnsafeMutablePointer<Float>, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        let rowLength = (x1 - x0 + 1) * 2
        values.withUnsafeBufferPointer { values in
            for y in y0...y1 { (buffer + (y * width + x0) * 2).update(from: values.baseAddress! + (y - y0) * rowLength, count: rowLength) }
        }
    }

    /// Ends the stroke in progress, returning what it changed for undo; nil when it changed nothing.
    func finishStroke() -> LiquifyStep? {
        let rect = strokeRect
        strokeRect = [0, 0, -1, -1]
        guard rect[2] >= rect[0] else { return nil }
        let before = region(of: checkpoint, rect[0], rect[1], rect[2], rect[3])
        let after = region(of: field, rect[0], rect[1], rect[2], rect[3])
        write(after, to: checkpoint, rect[0], rect[1], rect[2], rect[3])
        return LiquifyStep(x0: rect[0], y0: rect[1], x1: rect[2], y1: rect[3], before: before, after: after)
    }

    /// Puts a stroke's part of the field back as it was before it (`undo`) or after it.
    func restore(_ step: LiquifyStep, undo: Bool) {
        let values = undo ? step.before : step.after
        write(values, to: field, step.x0, step.y0, step.x1, step.y1)
        write(values, to: checkpoint, step.x0, step.y0, step.x1, step.y1)
        dirty = Self.union(dirty, [step.x0, step.y0, step.x1, step.y1])
    }

    var displacements: [Float] { Array(UnsafeBufferPointer(start: field, count: width * height * 2)) }

    /// `image` at full size through `displacements`, a field `fieldWidth` × `fieldHeight` covering the same image.
    static func render(_ image: CGImage, displacements: [Float], fieldWidth: Int, fieldHeight: Int) throws -> CGImage {
        let width = image.width, height = image.height
        let source = try BrushRaster.context(width: width, height: height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), mask: false, context: source)
        let result = try BrushRaster.context(width: width, height: height, mask: false)
        guard let input = source.data, let output = result.data else { throw ExportError.render }
        displacements.withUnsafeBufferPointer { field in
            liquify_render_scaled(input.bindMemory(to: UInt8.self, capacity: width * height * 4),
                                  output.bindMemory(to: UInt8.self, capacity: width * height * 4),
                                  width, height, field.baseAddress, fieldWidth, fieldHeight)
        }
        guard let made = result.makeImage() else { throw ExportError.render }
        return made
    }
}

/// The open Liquify dialog. Strokes are made on a copy of the layer no larger than `previewLimit`, so the brush
/// keeps up; OK scales the field they built up to the layer's full size and resamples the layer through it once.
/// Points come in the layer's own pixels, top row first.
@Observable
final class LiquifyEdit {
    static let previewLimit: CGFloat = 2048
    let layerID: UUID
    let layerName: String
    let original: CGImage
    let transform: LayerTransform
    /// The dialog's copy's size over the layer's.
    let scale: CGFloat
    /// The dialog's copy before any stroke, shown with Preview off.
    let before: CGImage
    var mode: LiquifyMode = .forwardWarp
    var brush: LiquifyBrush
    var preview = true
    var committing = false
    /// Finished strokes, oldest first, and those undone, most recently undone last.
    private(set) var undoSteps: [LiquifyStep] = []
    private(set) var redoSteps: [LiquifyStep] = []
    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }
    var hasChanges: Bool { !undoSteps.isEmpty }
    /// How much history is kept; the oldest strokes go first.
    static let historyLimit = (steps: 100, bytes: 256 << 20)
    @ObservationIgnored let field: LiquifyField
    /// The newest rendered result, for when Preview is turned back on.
    @ObservationIgnored private(set) var current: CGImage
    /// Where the brush is, in layer pixels, while a stroke is in progress.
    @ObservationIgnored private var last: CGPoint?
    @ObservationIgnored private var holdTask: Task<Void, Never>?

    init(layer: ImageLayer, brush: LiquifyBrush) throws {
        guard let asset = layer.asset else { throw ProjectError.invalid }
        layerID = layer.id; layerName = layer.name; original = asset.image; transform = layer.transform
        self.brush = brush
        let longest = CGFloat(max(asset.image.width, asset.image.height))
        scale = min(1, Self.previewLimit / max(1, longest))
        field = try LiquifyField(image: asset.image, width: max(1, Int((CGFloat(asset.image.width) * scale).rounded())),
                                 height: max(1, Int((CGFloat(asset.image.height) * scale).rounded())))
        guard let start = field.context.makeImage() else { throw ExportError.render }
        before = start
        current = start
    }

    /// A dab from `a` to `b` (layer pixels) with the current tool and brush.
    private func dab(from a: CGPoint, to b: CGPoint, strength: CGFloat) {
        field.dab(mode, from: CGPoint(x: a.x * scale, y: a.y * scale), to: CGPoint(x: b.x * scale, y: b.y * scale),
                  diameter: max(1, brush.size * scale), hardness: min(0.98, max(0, brush.density / 100)),
                  strength: min(4, max(0.01, strength)))
    }

    /// The result, if it changed since the last call. The dialog asks once a frame, so however many dabs arrive in
    /// between, the pixels are rendered and handed over once.
    func takeImage() -> CGImage? {
        guard field.renderChanges(), let made = field.context.makeImage() else { return nil }
        current = made
        return made
    }

    /// Starts a stroke at `point`.
    func begin(at point: CGPoint) {
        guard !committing else { return }
        last = point
        guard mode.worksInPlace else { return }
        dab(from: point, to: point, strength: brush.pressure / 100)
        // The in-place tools go on working while the brush is held still.
        holdTask?.cancel()
        holdTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, !Task.isCancelled, let point = self.last, self.brush.rate > 0 else { continue }
                self.dab(from: point, to: point, strength: self.brush.pressure / 100 * self.brush.rate / 100)
            }
        }
    }

    /// Continues the stroke to `point`, dabbing along the way.
    func drag(to point: CGPoint) {
        guard !committing, let from = last else { return }
        let distance = hypot(point.x - from.x, point.y - from.y)
        // A dab every 8% of the brush, and never closer than a pixel of the dialog's copy. The field moves pixels
        // by the whole of the brush's travel however far apart the dabs are.
        let spacing = max(1 / scale, brush.size * 0.08)
        guard distance >= spacing else { return }
        // The in-place tools work per dab, so each does as much as the 2.5%-apart dabs they were tuned with would.
        let perDab = mode.worksInPlace ? min(4, spacing / max(0.0001, brush.size * 0.025)) : 1
        let steps = Int((distance / spacing).rounded(.up))
        var previous = from
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let next = CGPoint(x: from.x + (point.x - from.x) * t, y: from.y + (point.y - from.y) * t)
            dab(from: previous, to: next, strength: brush.pressure / 100 * perDab)
            previous = next
        }
        last = point
    }

    /// Ends the stroke, keeping it as one undo step.
    func end() {
        holdTask?.cancel()
        holdTask = nil
        last = nil
        guard let step = field.finishStroke() else { return }
        undoSteps.append(step)
        redoSteps.removeAll()
        var bytes = undoSteps.reduce(0) { $0 + $1.byteCount }
        while undoSteps.count > Self.historyLimit.steps || (bytes > Self.historyLimit.bytes && undoSteps.count > 1) {
            bytes -= undoSteps.removeFirst().byteCount
        }
    }

    func undo() {
        guard !committing else { return }
        end()
        guard let step = undoSteps.popLast() else { return }
        field.restore(step, undo: true)
        redoSteps.append(step)
    }

    func redo() {
        guard !committing else { return }
        end()
        guard let step = redoSteps.popLast() else { return }
        field.restore(step, undo: false)
        undoSteps.append(step)
    }
}

extension EditorSession {
    var canLiquify: Bool { canAdjustColors && hueSaturation == nil }

    func beginLiquify() {
        guard liquify == nil, canLiquify else { NSSound.beep(); return }
        if gradientEdit != nil {
            Task { await commitGradient(); beginLiquify() }
            return
        }
        commitTransform(); cancelCrop(); cancelLasso()
        guard let layer = activeLayer else { return }
        do { liquify = try LiquifyEdit(layer: layer, brush: liquifyBrush) }
        catch { brushError = error.localizedDescription }
    }

    func cancelLiquify() {
        guard let edit = liquify, !edit.committing else { return }
        edit.end()
        liquifyBrush = edit.brush
        liquify = nil
    }

    /// Resamples the layer's full-size pixels through the dialog's field, as one undo step.
    func commitLiquify() async {
        guard let edit = liquify, !edit.committing else { return }
        edit.end()
        liquifyBrush = edit.brush
        // Nothing changed: close as Cancel does, without an undo step.
        guard edit.hasChanges else { liquify = nil; return }
        edit.committing = true
        isProjectBusy = true
        defer { liquify = nil; isProjectBusy = false; brushRevision += 1 }
        let source = edit.original, name = edit.layerName
        let displacements = edit.field.displacements, fieldWidth = edit.field.width, fieldHeight = edit.field.height
        do {
            let asset = try await Task.detached(priority: .userInitiated) { () -> ImportedImage in
                let image = try LiquifyField.render(source, displacements: displacements, fieldWidth: fieldWidth, fieldHeight: fieldHeight)
                return ImportedImage(image: image, thumbnail: try PixelAdjust.thumbnail(of: image), name: name)
            }.value
            guard let index = document?.layers.firstIndex(where: { $0.id == edit.layerID }),
                  let current = document?.layers[index],
                  current.asset?.image === edit.original, current.transform == edit.transform else { return }
            beginEdit("Liquify")
            document?.layers[index].asset = asset
            endEdit()
        } catch { brushError = error.localizedDescription }
    }
}
