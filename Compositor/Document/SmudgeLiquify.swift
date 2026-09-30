import AppKit
import SwiftUI

/// The Brush tool's modes.
nonisolated enum BrushToolMode: String, CaseIterable, Sendable {
    case paint = "Paint"
    case erase = "Erase"
    /// `rawValue` as a localizable display name; `rawValue` itself stays the stable, unlocalized identifier.
    var displayName: LocalizedStringKey {
        switch self {
        case .paint: return "Paint"
        case .erase: return "Erase"
        }
    }
}

/// The Smear tool's modes, as Photoshop's Blur, Sharpen and Smudge tools: Blur softens and Sharpen crisps what's
/// under the brush, Smudge drags its colors along. (Liquify is a filter of its own: Filter ▸ Liquify.)
nonisolated enum BlurToolMode: String, CaseIterable, Sendable {
    case blur = "Blur"
    case sharpen = "Sharpen"
    case smudge = "Smudge"
    /// `rawValue` as a localizable display name; `rawValue` itself stays the stable, unlocalized identifier.
    var displayName: LocalizedStringKey {
        switch self {
        case .blur: return "Blur"
        case .sharpen: return "Sharpen"
        case .smudge: return "Smudge"
        }
    }
}

/// A Smudge or Blur stroke in progress. Smudge works on the active layer as the canvas shows it, at document size;
/// Blur on the layer's own pixels, at their own resolution, so a scaled-down photo keeps its detail. It changes that
/// working copy dab by dab, and the canvas shows it in place of the layer. When the stroke ends, the result is painted
/// into the layer's own pixels along the stroke's path (see `EditorSession.finishWarp`).
final class WarpStroke {
    let layer: ImageLayer
    /// Blur rather than Smudge: each dab diffuses what's under it (see `smear_blur_dab`), where it is.
    let blurs: Bool
    let diameter: CGFloat
    let hardness: CGFloat
    let strength: CGFloat
    /// Blur: how far one stroke across a spot softens it, in canvas pixels, whatever the brush's size.
    let blurRadius: CGFloat
    let width: Int
    let height: Int
    /// Where the working copy sits on the canvas: across it, or, in the layer's own grid, where the layer is.
    let placement: LayerTransform
    /// The working copy is the layer's own pixels (Blur on a layer small enough), rather than the canvas's.
    let inLayerGrid: Bool
    /// Document points into the working copy's pixels, and how many of them a document pixel spans.
    private let toGrid: CGAffineTransform
    private let gridScale: CGFloat
    let context: CGContext
    private let pixels: UnsafeMutablePointer<UInt8>
    /// Every dab's center, for painting the result into the layer.
    private(set) var points: [CGPoint] = []
    /// The working copy on the GPU, where the dabs run when there is one (see MetalWarp).
    let gpu: MetalWarp?
    private var cpuImage: CGImage?
    /// The working copy as an image, fetched from the GPU the first time it's asked for after a dab.
    var image: CGImage? {
        guard let gpu else { return cpuImage }
        if cpuImage == nil {
            gpu.read(into: context)
            cpuImage = context.makeImage()
        }
        return cpuImage
    }
    private var last: CGPoint?
    /// Smudge: the color the brush carries, a (2r+1)² RGBA square.
    private var carried: [Float] = []

    init(layer: ImageLayer, image: CGImage, transform: LayerTransform, canvas: CGSize, settings: BrushSettings,
         blurs: Bool = false, useGPU: Bool = true) throws {
        self.layer = layer
        self.blurs = blurs
        diameter = max(2, settings.diameter)
        hardness = min(0.98, max(0, settings.hardness))
        strength = min(1, max(0.01, settings.opacity))
        blurRadius = min(50, max(0.5, settings.blurRadius))
        // Blur works in the layer's grid up to a budget of several canvases; a huge layer's is the canvas's instead.
        let budget = min(DocumentLimits.maxSurfacePixels, max(16_000_000, 4 * Int(canvas.width) * Int(canvas.height)))
        inLayerGrid = blurs && image.width * image.height <= budget
        if inLayerGrid {
            width = image.width; height = image.height
            placement = transform
            let mapping = BrushRaster.pixelToDocument(transform, width: width, height: height)
            toGrid = mapping.inverted()
            gridScale = 1 / max(1e-6, abs(mapping.a * mapping.d - mapping.b * mapping.c).squareRoot())
            context = try BrushRaster.context(width: width, height: height, mask: false)
            BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), mask: false, context: context)
        } else {
            width = Int(canvas.width); height = Int(canvas.height)
            placement = LayerTransform(origin: .zero, size: canvas)
            toGrid = .identity
            gridScale = 1
            context = try BrushRaster.context(width: width, height: height, mask: false)
            LayerRenderer.draw(image, transform: transform, center: transform.center, in: context)
        }
        guard let data = context.data else { throw ExportError.render }
        // Top-left rows: a document point's row is its y.
        pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // Blur's dabs run on the CPU (see SmearPixels.c); Smudge's on the GPU when there is one.
        gpu = useGPU && !blurs ? MetalWarp(pixels: context) : nil
        cpuImage = context.makeImage()
    }

    private var radius: Int { Int((diameter / 2).rounded(.up)) }
    /// How much a dab moves pixels at a distance `u` (0 center, 1 rim) from its center.
    private func weight(_ u: Float) -> Float {
        guard u < 1 else { return 0 }
        let h = Float(hardness)
        guard u > h else { return 1 }
        let t = (1 - u) / (1 - h)
        return t * t * (3 - 2 * t)
    }

    /// Continues the stroke to `point`, dabbing along the way, then refreshes `image`.
    func append(_ point: CGPoint) {
        guard let from = last else {
            last = point
            if blurs {
                // A click blurs too, so clicking again and again softens it further.
                blur(at: point)
                points.append(point)
                cpuImage = context.makeImage()
            } else if let gpu { gpu.pickUp(at: point, radius: radius); gpu.commit() } else { pickUp(at: point) }
            return
        }
        let distance = hypot(point.x - from.x, point.y - from.y)
        // Smudge drags the pixels one dab's spacing at a time and mixes them with what's there: spaced widely, each step
        // left a faint copy of what it dragged, echoes along the stroke. A pixel apart (a little more for a huge brush)
        // the steps run together into one smear, as Photoshop's does.
        let spacing = max(1, diameter * (blurs ? 0.1 : 0.005))
        guard distance >= spacing else { return }
        let steps = Int((distance / spacing).rounded(.up))
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let next = CGPoint(x: from.x + (point.x - from.x) * t, y: from.y + (point.y - from.y) * t)
            if blurs { blur(at: next) }
            else if let gpu { gpu.smudge(at: next, radius: radius, diameter: diameter, hardness: hardness, strength: strength) }
            else { smudge(at: next) }
            points.append(next)
        }
        last = point
        if let gpu {
            gpu.commit()
            cpuImage = nil
        } else {
            cpuImage = context.makeImage()
        }
    }

    /// One Blur dab. Dabs fall a tenth of the brush apart, so about ten cross each spot a stroke passes over; each
    /// spreads by the Radius over √10, so together, at full strength, the stroke softens by the Radius. In the working
    /// copy's pixels.
    private func blur(at center: CGPoint) {
        let point = center.applying(toGrid)
        Self.blurDabs &+= 1
        smear_blur_dab(pixels, width, height, context.bytesPerRow, point.x, point.y, diameter * gridScale / 2, hardness, strength,
                       blurRadius * gridScale / CGFloat(10).squareRoot(), Self.blurDabs)
    }
    /// Blur dabs laid so far, across strokes: each rounds to 8 bits its own way (see `smear_blur_dab`), even clicked
    /// again and again in one place.
    private static var blurDabs: UInt32 = 0

    private func pickUp(at center: CGPoint) {
        let r = radius, side = 2 * r + 1
        carried = [Float](repeating: 0, count: side * side * 4)
        let cx = Int(center.x.rounded()), cy = Int(center.y.rounded())
        for dy in -r...r {
            let y = cy + dy
            guard y >= 0, y < height else { continue }
            for dx in -r...r {
                let x = cx + dx
                guard x >= 0, x < width else { continue }
                let p = (y * width + x) * 4, c = ((dy + r) * side + dx + r) * 4
                for k in 0..<4 { carried[c + k] = Float(pixels[p + k]) }
            }
        }
    }

    private func smudge(at center: CGPoint) {
        let r = radius, side = 2 * r + 1
        let cx = Int(center.x.rounded()), cy = Int(center.y.rounded())
        let keep = Float(strength), invR = 1 / Float(diameter / 2)
        for dy in -r...r {
            let y = cy + dy
            guard y >= 0, y < height else { continue }
            for dx in -r...r {
                let x = cx + dx
                guard x >= 0, x < width else { continue }
                let w = weight(Float(dx * dx + dy * dy).squareRoot() * invR)
                guard w > 0 else { continue }
                let p = (y * width + x) * 4, c = ((dy + r) * side + dx + r) * 4
                for k in 0..<4 {
                    let under = Float(pixels[p + k])
                    // What was under the brush at the last dab, laid down here at the smudge's strength, as Photoshop
                    // does: all of it drags the pixels along; less mixes them with what's here, softening the trail.
                    let painted = under + (carried[c + k] - under) * w * keep
                    pixels[p + k] = UInt8(max(0, min(255, painted.rounded())))
                    // The brush then carries what it just left, and nothing older: holding on to what it picked up
                    // at the start stamped it again at every dab, a trail of ghost copies.
                    carried[c + k] = painted
                }
            }
        }
    }
}

extension EditorSession {
    func beginWarp(at point: CGPoint) {
        guard canPaint, !isMaskSelected, let layer = activeLayer, let image = layer.asset?.image, let document else {
            brushError = isMaskSelected ? "Smudge works on a layer's pixels, not its mask." : paintRefusal
            return
        }
        finishOpacityEdit()
        do {
            let stroke = try WarpStroke(layer: layer, image: image, transform: displayedTransform(for: layer),
                                        canvas: document.size, settings: brushSettings, blurs: blurMode == .blur)
            stroke.append(point)
            warpStroke = stroke
            lastBrushPoint = (point, layer.id, false)
            brushRevision += 1
        } catch { brushError = error.localizedDescription }
    }

    /// Paints the finished Smudge or Blur result into the layer's pixels along the stroke, as one undo step.
    func finishWarp() {
        guard let warp = warpStroke else { return }
        warpStroke = nil
        brushRevision += 1
        guard !warp.points.isEmpty, let result = warp.image,
              let current = document?.layers.first(where: { $0.id == warp.layer.id }),
              current.asset?.image === warp.layer.asset?.image, current.transform == warp.layer.transform else { return }
        do {
            var settings = brushSettings
            // A hard tip a little wider than the brush covers everything the stroke moved.
            settings.diameter = warp.diameter + 4
            settings.hardness = 1
            settings.opacity = 1
            let stroke = try makeRasterEdit(for: current, settings: settings)
            // In the layer's grid the result sits over the layer's own pixels; otherwise across the canvas.
            stroke.clone = warp.inLayerGrid ? (result, stroke.sourceRect, true)
                : (result, CGRect(x: 0, y: 0, width: result.width, height: result.height), false)
            stroke.replacesWithClone = true
            stroke.editName = (warp.blurs ? BlurToolMode.blur : .smudge).rawValue
            // The tip is solid and a little wider than the brush, so a point every twentieth of its width covers what
            // every dab did: a big brush on a big canvas lays thousands of dabs, and replaying each one stalled the release.
            let spacing = max(1, warp.diameter * 0.05)
            var kept: CGPoint?
            for (index, point) in warp.points.enumerated() {
                if let kept, index < warp.points.count - 1, hypot(point.x - kept.x, point.y - kept.y) < spacing { continue }
                try stroke.append(point)
                kept = point
            }
            try stroke.flush()
            if !stroke.patches.isEmpty { try commitPaintSnapshot(stroke) }
        } catch { brushError = error.localizedDescription }
    }
}
