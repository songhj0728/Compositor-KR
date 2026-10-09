import AppKit
import CoreImage

/// A stroke's effects: unchanged pixels are reused, and only changed regions are
/// rendered on a worker. Pointer events never wait for pixel effects to finish.
@MainActor final class LayerEffectsSurface {
    let layerID: UUID
    let grid: CGSize
    let sourceRect: CGRect
    let margin: CGFloat
    let hasFullResolutionSeed: Bool
    private let effects: LayerEffects
    private let worker: Worker
    private static let queue = DispatchQueue(label: "com.compositor.live-effects", qos: .userInitiated)
    private var pending: Input?
    private var submitted: [String: ObjectIdentifier] = [:]
    private var didSubmit = false
    private(set) var isRendering = false
    private(set) var image: CGImage?
    private(set) var lastRenderedRegion: CGRect?
    var placement: LayerTransform?
    private let completion: @MainActor @Sendable () -> Void

    nonisolated struct MaskStroke: Sendable {
        let patches: [BrushPatch]
        let toGrid: CGAffineTransform
        let coverage: @Sendable (CGRect) -> CGImage?
    }

    nonisolated private struct Result: @unchecked Sendable {
        let image: CGImage
        let region: CGRect
    }

    nonisolated private struct Input: @unchecked Sendable {
        let base: CGImage?
        let baseRaster: RasterSnapshot?
        let patches: [BrushPatch]
        let mask: CGImage?
        let maskStroke: MaskStroke?
    }

    init?(layerID: UUID, effects: LayerEffects, grid: CGSize, sourceRect: CGRect,
          seed: (image: CGImage, inset: CGFloat)? = nil,
          completion: @escaping @MainActor @Sendable () -> Void = {}) {
        guard let worker = Worker(effects: effects, grid: grid, sourceRect: sourceRect, seed: seed) else { return nil }
        self.layerID = layerID; self.effects = effects; self.grid = grid; self.sourceRect = sourceRect
        self.margin = worker.margin; self.worker = worker; self.completion = completion
        // A resized preview is useful during input, but its untouched pixels cannot
        // be adopted as a finished full-resolution result after the stroke.
        self.hasFullResolutionSeed = seed.map {
            abs(CGFloat($0.image.width) - 2 * $0.inset - sourceRect.width) < 0.01
                && abs(CGFloat($0.image.height) - 2 * $0.inset - sourceRect.height) < 0.01
        } ?? true
    }

    func matches(layerID: UUID, effects: LayerEffects, grid: CGSize, sourceRect: CGRect) -> Bool {
        self.layerID == layerID && self.effects == effects && self.grid == grid && self.sourceRect == sourceRect
    }

    func update(base: CGImage?, baseRaster: RasterSnapshot? = nil, patches: [BrushPatch], mask: CGImage?, maskStroke: MaskStroke? = nil) {
        var seen: [String: ObjectIdentifier] = [:]
        for patch in maskStroke?.patches ?? patches {
            seen["\(Int(patch.rect.minX)),\(Int(patch.rect.minY))"] = ObjectIdentifier(patch.image)
        }
        guard !didSubmit || seen != submitted else { return }
        submitted = seen
        didSubmit = true
        // Coalesce pending pointer samples, but allow the current result to finish:
        // cancelling on every mouse move would starve continuous strokes of updates.
        let input = Input(base: base, baseRaster: baseRaster, patches: patches, mask: mask, maskStroke: maskStroke)
        if effects.bevel == nil {
            if let result = worker.update(input) { image = result.image; lastRenderedRegion = result.region }
        } else {
            pending = input
            processPending()
        }
    }

    private func processPending() {
        guard !isRendering, let input = pending else { return }
        pending = nil
        isRendering = true
        let worker = worker
        Self.queue.async { [weak self] in
            let result = autoreleasepool { worker.update(input) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRendering = false
                if let result { self.image = result.image; self.lastRenderedRegion = result.region }
                self.processPending()
                if result != nil { self.completion() }
            }
        }
    }

    /// Core Graphics lives in this platform adapter. The bounded-region rules and
    /// Euclidean bevel geometry do not depend on the scheduling or drawing API.
    nonisolated private final class Worker: @unchecked Sendable {
        let grid: CGSize
        let sourceRect: CGRect
        let margin: CGFloat
        private let effects: LayerEffects
        private let context: CGContext
        private let seed: (image: CGImage, inset: CGFloat)?
        private var seeded = false
        private var taken: [String: ObjectIdentifier] = [:]
        private var takenRects: [String: CGRect] = [:]
        private var image: CGImage?
        private var maskStroke: MaskStroke?
        private var baseRaster: RasterSnapshot?
        private var lastRegion: CGRect?

        init?(effects: LayerEffects, grid: CGSize, sourceRect: CGRect, seed: (image: CGImage, inset: CGFloat)?) {
            let margin = LayerEffectsRenderer.margin(for: effects)
            let width = Int(grid.width + margin * 2), height = Int(grid.height + margin * 2)
            guard width > 0, height > 0, width * height <= 80_000_000,
                  let context = try? BrushRaster.context(width: width, height: height, mask: false) else { return nil }
            self.effects = effects; self.grid = grid; self.sourceRect = sourceRect
            self.margin = margin; self.context = context; self.seed = seed
        }

        /// How far a pixel can reach into its surroundings: everything within this of a change may need redoing.
        private var reach: CGFloat {
            var reach: CGFloat = 1
            if let stroke = effects.stroke, stroke.isEnabled { reach = max(reach, stroke.size + 2) }
            if let shadow = effects.shadow, shadow.isEnabled { reach = max(reach, shadow.distance + shadow.blur * 3 + 2) }
            if let glow = effects.outerGlow, glow.isEnabled { reach = max(reach, glow.size * 3 + 2) }
            if let glow = effects.innerGlow, glow.isEnabled { reach = max(reach, glow.size * 3 + 2) }
            if let inner = effects.innerShadow, inner.isEnabled { reach = max(reach, inner.distance + inner.blur * 3 + 2) }
            if let bevel = effects.bevel, bevel.isEnabled {
                let size = max(1, Float(bevel.size(clampedTo: sourceRect.size)))
                reach = max(reach, CGFloat(size) + LayerStyleRenderer.bevelFilterSupport(bevel, size: size) + 1)
            }
            if let satin = effects.satin, satin.isEnabled { reach = max(reach, satin.distance + satin.size * 3 + 2) }
            return ceil(reach)
        }

        /// Brings the surface up to date: everything on the first pass, and after that only where the paint changed.
        /// `base` is the layer's committed pixels and `patches` the stroke's tiles as they stand. Painting the layer's mask
        /// instead, `maskStroke` holds the mask as it was and the stroke's tiles of it; the pixels themselves don't change.
        func update(_ input: Input) -> Result? {
            let base = input.base, patches = input.patches, mask = input.mask, maskStroke = input.maskStroke
            self.baseRaster = input.baseRaster
            if !seeded, let seed {
                let inset = seed.inset * sourceRect.width / max(1, CGFloat(seed.image.width) - seed.inset * 2)
                BrushRaster.draw(seed.image, in: sourceRect.insetBy(dx: -inset, dy: -inset)
                    .offsetBy(dx: margin, dy: margin), mask: false, context: context)
                image = context.makeImage()
            }
            seeded = true
            self.maskStroke = maskStroke
            var dirty: CGRect?
            var seen: [String: ObjectIdentifier] = [:]
            var rects: [String: CGRect] = [:]
            for patch in maskStroke?.patches ?? patches {
                let key = "\(Int(patch.rect.minX)),\(Int(patch.rect.minY))"
                seen[key] = ObjectIdentifier(patch.image)
                // A mask on its own placement is painted in its own grid; what it touched is found in the layer's.
                let rect = maskStroke.map { patch.rect.applying($0.toGrid).insetBy(dx: -1, dy: -1) } ?? patch.rect
                rects[key] = rect
                guard taken[key] != ObjectIdentifier(patch.image) else { continue }
                dirty = dirty.map { $0.union(rect) } ?? rect
            }
            // Temporary brush tails can retract tiles; restore their old regions as well.
            for (key, rect) in takenRects where seen[key] == nil {
                dirty = dirty.map { $0.union(rect) } ?? rect
            }
            let first = image == nil
            taken = seen
            takenRects = rects
            let region = first ? CGRect(origin: .zero, size: grid).insetBy(dx: -margin, dy: -margin) : dirty
            guard let region else { return nil }
            compose(region.integral, base: base, patches: patches, mask: mask)
            image = context.makeImage()
            guard let image, let lastRegion else { return nil }
            return Result(image: image, region: lastRegion)
        }

        /// Redraws one region of the surface: the effects there, then the pixels over them.
        private func compose(_ region: CGRect, base: CGImage?, patches: [BrushPatch], mask: CGImage?) {
            let bounds = CGRect(origin: .zero, size: grid).insetBy(dx: -margin, dy: -margin)
            let inner = region.insetBy(dx: -reach, dy: -reach).integral.intersection(bounds)
            guard !inner.isNull, inner.width >= 1, inner.height >= 1 else { return }
            lastRegion = inner
            // Everything that can reach into `inner` has to be looked at.
            let outer = inner.insetBy(dx: -reach, dy: -reach).integral
            guard let pixels = window(outer, base: base, patches: patches, mask: mask) else { return }
            // Photoshop's Layer Style past the GPU pass's reach, drawn in floating point; a pattern keeps its place.
            let styled = effects.needsStyleRenderer
                ? try? LayerStyleRenderer.render(pixels, effects: effects,
                                                 origin: CGPoint(x: outer.minX - sourceRect.minX, y: outer.minY - sourceRect.minY),
                                                 fullSize: sourceRect.size)
                : nil
            // In one pass on the GPU when it is available: the outline's reach and the shadow's blur are what cost.
            if let built = styled ?? (effects.needsStyleRenderer ? nil : MetalLayerEffects.shared.flatMap({ try? $0.render(pixels, effects: effects) })) {
                context.saveGState()
                context.clip(to: inner.offsetBy(dx: margin, dy: margin))
                context.clear(inner.offsetBy(dx: margin, dy: margin))
                BrushRaster.draw(built, in: outer.offsetBy(dx: margin, dy: margin), mask: false, context: context)
                context.restoreGState()
                return
            }
            // In the surface's own coordinates, the grid starts at the margin.
            func placed(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: margin, dy: margin) }
            context.saveGState()
            context.clip(to: placed(inner))
            context.clear(placed(inner))
            if let shadow = effects.shadow, shadow.isEnabled, shadow.opacity > 0,
               let coverage = try? LayerEffectsRenderer.shadowCoverage(pixels, in: outer.size, offset: shadow.offset, blur: shadow.blur) {
                fill(shadow.color, alpha: shadow.opacity, coverage: coverage, in: placed(outer))
            }
            if let glow = effects.outerGlow, glow.isEnabled, glow.opacity > 0,
               let coverage = try? LayerEffectsRenderer.outerGlowCoverage(pixels, placed: CGRect(origin: .zero, size: outer.size), size: outer.size, glow: glow) {
                fill(glow.color, alpha: glow.opacity, coverage: coverage, in: placed(outer))
            }
            let stroke = effects.stroke.flatMap { $0.isEnabled && $0.size > 0 && $0.opacity > 0 ? $0 : nil }
            if let stroke, !stroke.inside, let ring = try? LayerEffectsRenderer.ringCoverage(pixels, in: outer.size, stroke: stroke) {
                fill(stroke.color, alpha: stroke.opacity, coverage: ring, in: placed(outer))
            }
            // An inner glow recolors the pixels themselves, keeping their alpha, as the full renderer does.
            var shown = pixels
            if let glow = effects.innerGlow, glow.isEnabled, glow.size > 0, glow.opacity > 0,
               let coverage = try? LayerEffectsRenderer.innerGlowCoverage(
                    pixels,
                    placed: CGRect(origin: .zero, size: outer.size),
                    size: outer.size,
                    glow: glow
               ), let layer = try? BrushRaster.copy(pixels) {
                LayerEffectsRenderer.recolor(layer, glow.color, alpha: glow.opacity, amount: coverage,
                                             in: CGRect(origin: .zero, size: outer.size))
                shown = layer.makeImage() ?? pixels
            }
            BrushRaster.draw(shown, in: placed(outer), mask: false, context: context)
            if let stroke, stroke.inside, let ring = try? LayerEffectsRenderer.ringCoverage(pixels, in: outer.size, stroke: stroke) {
                fill(stroke.color, alpha: stroke.opacity, coverage: ring, in: placed(outer))
            }
            context.restoreGState()
        }

        /// The layer as the stroke has it, over one region: its committed pixels, the tiles painted since, and its mask.
        private func window(_ region: CGRect, base: CGImage?, patches: [BrushPatch], mask: CGImage?) -> CGImage? {
            guard region.width >= 1, region.height >= 1,
                  let window = try? BrushRaster.context(width: Int(region.width), height: Int(region.height), mask: false) else { return nil }
            window.translateBy(x: -region.minX, y: -region.minY)
            if let maskStroke {
                guard let live = maskStroke.coverage(region) else { return nil }
                // Clipped the way BrushRaster draws, so the mask's top row lands on the region's top row.
                window.translateBy(x: region.minX, y: region.maxY)
                window.scaleBy(x: 1, y: -1)
                window.clip(to: CGRect(origin: .zero, size: region.size), mask: live)
                window.scaleBy(x: 1, y: -1)
                window.translateBy(x: -region.minX, y: -region.maxY)
                if let baseRaster { baseRaster.draw(in: sourceRect, context: window) }
                else if let base { BrushRaster.draw(base, in: sourceRect, mask: false, context: window) }
                return window.makeImage()
            }
            func drawPixels() {
                if let baseRaster { baseRaster.draw(in: sourceRect, context: window) }
                else if let base { BrushRaster.draw(base, in: sourceRect, mask: false, context: window) }
                for patch in patches where patch.rect.intersects(region) {
                    BrushRaster.draw(patch.image, in: patch.rect, mask: false, context: window)
                }
            }
            if let mask {
                // The layer's own pixels are shown through its mask; paint laid down past them is not masked at all.
                // Clipped the way BrushRaster draws, so the mask's top row lands on the layer's top row.
                window.saveGState()
                window.translateBy(x: sourceRect.minX, y: sourceRect.maxY)
                window.scaleBy(x: 1, y: -1)
                window.clip(to: CGRect(origin: .zero, size: sourceRect.size), mask: mask)
                window.scaleBy(x: 1, y: -1)
                window.translateBy(x: -sourceRect.minX, y: -sourceRect.maxY)
                drawPixels()
                window.restoreGState()
                window.saveGState()
                let outside = CGMutablePath()
                outside.addRect(region)
                outside.addRect(sourceRect)
                window.addPath(outside)
                window.clip(using: .evenOdd)
                drawPixels()
                window.restoreGState()
            } else {
                drawPixels()
            }
            return window.makeImage()
        }

        private func fill(_ color: PaletteColor, alpha: Double, coverage: CGImage, in rect: CGRect) {
            context.saveGState()
            context.clip(to: rect, mask: coverage)
            context.setAlpha(alpha)
            context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1))
            context.fill(rect)
            context.restoreGState()
        }
}
}
