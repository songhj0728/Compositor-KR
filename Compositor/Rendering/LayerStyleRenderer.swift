import CoreGraphics
import Foundation

/// Photoshop's full Layer Style, drawn on the CPU in floating point: Bevel & Emboss (with its Contour and Texture),
/// Satin, Pattern Overlay, every effect in its own blend mode, spread and choke, contours, and a Fill Opacity that
/// fades the layer's pixels but not its effects. The GPU's single pass (`MetalLayerEffects`) still draws the
/// effects that need none of this, exactly as before; see `LayerEffects.needsStyleRenderer`.
///
/// Effects stack as Photoshop's do, bottom to top: Drop Shadow, Outer Glow, an outside Stroke, the layer's pixels,
/// Pattern Overlay, Color Overlay, Satin, Inner Glow, Inner Shadow, an inside or centered Stroke, Bevel & Emboss.
/// Each draws over what is under it in its blend mode. They are drawn into the layer's own image, so a mode compares
/// against the layer and the effects beneath it, not the layers below it.
nonisolated enum LayerStyleRenderer {
    /// `pixels` — the layer as it's shown, with room around it for the effects — with `effects` drawn over and
    /// around it, the same size. `origin` is where the image's top-left pixel sits in the layer's own pixels, so a
    /// pattern stays put however much room there is around it, or whichever piece of the layer is being redrawn.
    /// `fullSize` is the layer's own true size, not this call's (`pixels` may be only the window a paint stroke
    /// just touched, padded by its reach) — Bevel & Emboss keys its size to it, so a layer redrawn a window at a
    /// time bevels exactly as it would whole, and a bevel too big for a small layer eases off short of its middle
    /// rather than warping it.
    static func render(_ pixels: CGImage, effects: LayerEffects, origin: CGPoint = .zero, fullSize: CGSize? = nil) throws -> CGImage {
        let effects = effects.visible
        guard effects.isValid else { throw ProjectError.invalid }
        let width = pixels.width, height = pixels.height, count = width * height
        let fullSize = fullSize ?? CGSize(width: width, height: height)
        guard count > 0, count <= 80_000_000 else { throw ExportError.tooLarge }
        let source = try BrushRaster.context(width: width, height: height, mask: false)
        BrushRaster.draw(pixels, in: CGRect(x: 0, y: 0, width: width, height: height), mask: false, context: source)
        guard let raw = source.data else { throw ExportError.render }
        let bytes = raw.assumingMemoryBound(to: UInt8.self)
        let rowBytes = source.bytesPerRow

        var canvas = Canvas(width: width, height: height)
        var layer = [SIMD4<Float>](repeating: .zero, count: count)
        var shape = [Float](repeating: 0, count: count)
        for y in 0..<height {
            for x in 0..<width {
                let at = y * rowBytes + x * 4, index = y * width + x
                let pixel = SIMD4<Float>(Float(bytes[at]), Float(bytes[at + 1]), Float(bytes[at + 2]), Float(bytes[at + 3])) / 255
                layer[index] = pixel
                shape[index] = pixel.w
            }
        }
        let planes = Planes(width: width, height: height)

        if let shadow = effects.shadow, shadow.opacity > 0 {
            let spread = Float(shadow.spread ?? 0) / 100
            var base = shape
            let hard = Int((shadow.blur * CGFloat(spread)).rounded())
            if hard > 0 { base = LayerEffectsRenderer.extreme(base, width: width, height: height, reach: hard, smallest: false) }
            base = planes.shift(base, dx: Float(shadow.offset.width), dy: Float(shadow.offset.height))
            base = planes.gaussian(base, sigma: Float(shadow.blur) * (1 - spread) / 2)
            if let contour = shadow.contour, contour != .linear { base = base.map(contour.value) }
            canvas.draw(base, opacity: Float(shadow.opacity), color: shadow.color, mode: shadow.blendMode ?? .normal)
        }
        if let glow = effects.outerGlow, glow.size > 0, glow.opacity > 0 {
            let spread = Float(glow.spread ?? 0) / 100
            var base = shape
            let hard = Int((glow.size * CGFloat(spread)).rounded())
            if hard > 0 { base = LayerEffectsRenderer.extreme(base, width: width, height: height, reach: hard, smallest: false) }
            base = planes.gaussian(base, sigma: Float(glow.size) * (1 - spread) / 2)
            let contour = glow.contour ?? .linear
            for i in base.indices { base[i] = contour.value(base[i]) * (1 - shape[i]) }
            canvas.draw(base, opacity: Float(glow.opacity), color: glow.color, mode: glow.blendMode ?? .normal)
        }
        let stroke = effects.stroke.flatMap { $0.size > 0 && $0.opacity > 0 ? $0 : nil }
        func drawStroke(_ stroke: StrokeEffect) {
            let reach = max(1, Int(stroke.size.rounded()))
            var ring = [Float](repeating: 0, count: count)
            if stroke.centered == true {
                let half = max(1, Int((stroke.size / 2).rounded()))
                let grown = LayerEffectsRenderer.extreme(shape, width: width, height: height, reach: half, smallest: false)
                let shrunk = LayerEffectsRenderer.extreme(shape, width: width, height: height, reach: half, smallest: true)
                for i in ring.indices { ring[i] = max(0, grown[i] - shrunk[i]) }
            } else {
                let moved = LayerEffectsRenderer.extreme(shape, width: width, height: height, reach: reach, smallest: stroke.inside)
                for i in ring.indices { ring[i] = stroke.inside ? max(0, shape[i] - moved[i]) : max(0, moved[i] - shape[i]) }
            }
            canvas.draw(ring, opacity: Float(stroke.opacity), color: stroke.color, mode: stroke.blendMode ?? .normal)
        }
        if let stroke, !stroke.inside, stroke.centered != true { drawStroke(stroke) }

        // The layer's own pixels, faded by Fill Opacity.
        canvas.drawPixels(layer, fill: Float(effects.fill))

        if let pattern = effects.patternOverlay, pattern.opacity > 0 {
            let ink = SIMD3<Float>(Float(pattern.red), Float(pattern.green), Float(pattern.blue))
            let paper = SIMD3<Float>(Float(pattern.paperRed), Float(pattern.paperGreen), Float(pattern.paperBlue))
            let scale = Float(pattern.scale) / 100
            var colors = [SIMD3<Float>](repeating: paper, count: count)
            for y in 0..<height {
                for x in 0..<width where shape[y * width + x] > 0 {
                    let amount = pattern.pattern.value(x: Float(x) + Float(origin.x), y: Float(y) + Float(origin.y), scale: scale)
                    colors[y * width + x] = paper + (ink - paper) * amount
                }
            }
            canvas.draw(shape, opacity: Float(pattern.opacity), colors: colors, mode: pattern.blendMode ?? .normal)
        }
        if let overlay = effects.colorOverlay, overlay.opacity > 0 {
            canvas.draw(shape, opacity: Float(overlay.opacity), color: overlay.color, mode: overlay.blendMode ?? .normal)
        }
        if let satin = effects.satin, satin.opacity > 0 {
            let dx = Float(satin.offset.width), dy = Float(satin.offset.height), sigma = Float(satin.size) / 2
            let ahead = planes.gaussian(planes.shift(shape, dx: dx, dy: dy), sigma: sigma)
            let behind = planes.gaussian(planes.shift(shape, dx: -dx, dy: -dy), sigma: sigma)
            var amount = [Float](repeating: 0, count: count)
            for i in amount.indices where shape[i] > 0 {
                let difference = min(1, abs(ahead[i] - behind[i]))
                amount[i] = satin.contour.value(satin.invert ? 1 - difference : difference) * shape[i]
            }
            canvas.draw(amount, opacity: Float(satin.opacity), color: satin.color, mode: satin.blendMode ?? .normal)
        }
        if let glow = effects.innerGlow, glow.size > 0, glow.opacity > 0 {
            let choke = Float(glow.choke ?? 0) / 100
            var base = shape
            let contour = glow.contour ?? .linear
            if glow.fromCenter == true {
                base = LayerEffectsRenderer.extreme(base, width: width, height: height, reach: max(1, Int(glow.size.rounded())), smallest: true)
                base = planes.gaussian(base, sigma: Float(glow.size) / 2)
                for i in base.indices { base[i] = contour.value(base[i]) * shape[i] }
            } else {
                let hard = Int((glow.size * CGFloat(choke)).rounded())
                if hard > 0 { base = LayerEffectsRenderer.extreme(base, width: width, height: height, reach: hard, smallest: true) }
                base = planes.gaussian(base, sigma: Float(glow.size) * (1 - choke) / 2)
                for i in base.indices { base[i] = contour.value(1 - base[i]) * shape[i] }
            }
            canvas.draw(base, opacity: Float(glow.opacity), color: glow.color, mode: glow.blendMode ?? .normal)
        }
        if let inner = effects.innerShadow, inner.opacity > 0 {
            let choke = Float(inner.choke ?? 0) / 100
            var moved = planes.shift(shape, dx: Float(inner.offset.width), dy: Float(inner.offset.height))
            let hard = Int((inner.blur * CGFloat(choke)).rounded())
            if hard > 0 { moved = LayerEffectsRenderer.extreme(moved, width: width, height: height, reach: hard, smallest: true) }
            moved = planes.gaussian(moved, sigma: Float(inner.blur) * (1 - choke) / 2)
            let contour = inner.contour ?? .linear
            for i in moved.indices { moved[i] = contour.value(1 - moved[i]) * shape[i] }
            canvas.draw(moved, opacity: Float(inner.opacity), color: inner.color, mode: inner.blendMode ?? .normal)
        }
        if let stroke, stroke.inside || stroke.centered == true { drawStroke(stroke) }
        if let bevel = effects.bevel, bevel.size > 0 || bevel.hasTexture {
            let shading = Self.bevelShading(bevel, shape: shape, planes: planes, origin: origin, fullSize: fullSize)
            canvas.draw(shading.shadow, opacity: Float(bevel.shadowOpacity), color: bevel.shadowColor, mode: bevel.shadowMode)
            canvas.draw(shading.highlight, opacity: Float(bevel.highlightOpacity), color: bevel.highlightColor, mode: bevel.highlightMode)
        }
        return try canvas.image(space: source.colorSpace ?? WorkingColorSpace.current)
    }

    /// A bevel's light and shade: the layer's shape turned into a height map by its style and technique, bent by its
    /// contour, pressed with its texture, then lit from its angle and altitude. `fullSize` is the layer's true size
    /// (see `render`); size leaves a flat middle rather than letting opposite edges meet, regardless of how big a window is actually being drawn right now.
    static func bevelShading(_ bevel: BevelEffect, shape: [Float], planes: Planes, origin: CGPoint, fullSize: CGSize) -> (highlight: [Float], shadow: [Float]) {
        let width = planes.width, height = planes.height, count = shape.count
        let size = max(1, Float(bevel.size(clampedTo: fullSize)))
        // Distance from the actual silhouette keeps the bevel at the edge. Blurring alpha here would
        // let opposite edges pull each other's slopes into the middle of a small shape.
        let distances = BevelGeometry.edgeDistances(shape, width: width, height: height)
        var heights = [Float](repeating: 0, count: count)
        let range = max(0.01, Float(bevel.contourRange) / 100)
        for i in heights.indices {
            let distance = (shape[i] >= 0.5 ? 1 : -1) * distances[i]
            var h: Float
            switch bevel.style {
            case .innerBevel: h = min(1, max(0, distance / size))
            case .outerBevel: h = min(1, max(0, 1 + distance / size))
            case .emboss: h = min(1, max(0, 0.5 + distance / (2 * size)))
            case .pillowEmboss: h = min(1, abs(distance) / size)
            }
            if bevel.technique == .smooth { h = h * h * (3 - 2 * h) }
            if bevel.hasContour { h = bevel.contour.value(min(1, h / (2 * range))) }
            heights[i] = h
        }
        if bevel.technique == .chiselSoft { heights = planes.gaussian(heights, sigma: 1.5) }
        if bevel.soften > 0 { heights = planes.gaussian(heights, sigma: Float(bevel.soften) / 2) }
        let lift = size * Float(bevel.depth) / 100 * (bevel.up ? 1 : -1)
        let textureScale = Float(bevel.textureScale) / 100, textureLift = 2 * Float(bevel.textureDepth) / 100 * (bevel.up ? 1 : -1)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                var h = heights[i] * lift
                if bevel.hasTexture, shape[i] > 0 {
                    var t = bevel.texture.value(x: Float(x) + Float(origin.x), y: Float(y) + Float(origin.y), scale: textureScale)
                    if bevel.textureInvert { t = 1 - t }
                    h += shape[i] * t * textureLift
                }
                heights[i] = h
            }
        }
        // Light from the dial's angle (counterclockwise from the right, y up) and altitude above the horizon; the
        // layer's rows count downward, so y turns over.
        let azimuth = Float(bevel.angle) * .pi / 180, altitude = Float(bevel.altitude) * .pi / 180
        let light = SIMD3<Float>(cos(altitude) * cos(azimuth), -cos(altitude) * sin(azimuth), sin(altitude))
        let flat = sin(altitude)
        var highlight = [Float](repeating: 0, count: count), shadow = [Float](repeating: 0, count: count)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let region: Float
                switch bevel.style {
                case .innerBevel: region = shape[i]
                case .outerBevel: region = 1 - shape[i]
                case .emboss, .pillowEmboss: region = 1
                }
                guard region > 0 else { continue }
                let left = heights[y * width + max(0, x - 1)], right = heights[y * width + min(width - 1, x + 1)]
                let up = heights[max(0, y - 1) * width + x], down = heights[min(height - 1, y + 1) * width + x]
                let slope = SIMD3<Float>(-(right - left) / 2, -(down - up) / 2, 1)
                let normal = slope / (slope * slope).sum().squareRoot()
                let lit = (normal * light).sum()
                if lit > flat, flat < 1 {
                    highlight[i] = bevel.gloss.value((lit - flat) / (1 - flat)) * region
                } else if lit < flat, flat > 0.001 {
                    shadow[i] = bevel.gloss.value((flat - lit) / flat) * region
                }
            }
        }
        return (highlight, shadow)
    }

    /// Single-channel planes the size of the image, and the blurs and shifts the effects make of them. Past the
    /// image's edge there is nothing (0).
    struct Planes {
        let width: Int
        let height: Int

        /// A Gaussian blur, as three box blurs each way (within a few percent of a true Gaussian, at a cost that
        /// doesn't grow with the radius).
        func gaussian(_ plane: [Float], sigma: Float) -> [Float] {
            guard sigma > 0.01 else { return plane }
            var result = plane
            for radius in Self.boxRadii(sigma: sigma) {
                result = box(result, radius: radius, horizontal: true)
                result = box(result, radius: radius, horizontal: false)
            }
            return result
        }

        static func boxRadii(sigma: Float, passes: Int = 3) -> [Int] {
            let n = Float(passes)
            let ideal = (12 * sigma * sigma / n + 1).squareRoot()
            var lower = Int(ideal.rounded(.down))
            if lower % 2 == 0 { lower -= 1 }
            lower = max(1, lower)
            let upper = lower + 2
            let wl = Float(lower)
            let m = Int(((12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4)).rounded())
            return (0..<passes).map { ($0 < m ? lower : upper) / 2 }
        }

        /// The average over `radius` pixels either side, along rows or columns.
        func box(_ plane: [Float], radius: Int, horizontal: Bool) -> [Float] {
            guard radius > 0, plane.count == width * height else { return plane }
            var result = [Float](repeating: 0, count: plane.count)
            let lines = horizontal ? height : width, length = horizontal ? width : height
            let step = horizontal ? 1 : width, lineStep = horizontal ? width : 1
            let scale = 1 / Float(2 * radius + 1)
            plane.withUnsafeBufferPointer { input in
                result.withUnsafeMutableBufferPointer { output in
                    let source = input.baseAddress!, target = output.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: min(lines, 64)) { chunk in
                        var sums = [Double](repeating: 0, count: length + 1)
                        var line = chunk
                        while line < lines {
                            let base = line * lineStep
                            for i in 0..<length { sums[i + 1] = sums[i] + Double(source[base + i * step]) }
                            for i in 0..<length {
                                let low = max(0, i - radius), high = min(length, i + radius + 1)
                                target[base + i * step] = Float(sums[high] - sums[low]) * scale
                            }
                            line += min(lines, 64)
                        }
                    }
                }
            }
            return result
        }

        /// The plane moved by (`dx`, `dy`) pixels, between pixels where it lands between them.
        func shift(_ plane: [Float], dx: Float, dy: Float) -> [Float] {
            guard dx != 0 || dy != 0 else { return plane }
            var result = [Float](repeating: 0, count: plane.count)
            for y in 0..<height {
                let sy = Float(y) - dy
                guard sy >= 0, sy <= Float(height - 1) else { continue }
                let y0 = Int(sy.rounded(.down)), y1 = min(y0 + 1, height - 1), fy = sy - Float(y0)
                for x in 0..<width {
                    let sx = Float(x) - dx
                    guard sx >= 0, sx <= Float(width - 1) else { continue }
                    let x0 = Int(sx.rounded(.down)), x1 = min(x0 + 1, width - 1), fx = sx - Float(x0)
                    let top = plane[y0 * width + x0] * (1 - fx) + plane[y0 * width + x1] * fx
                    let bottom = plane[y1 * width + x0] * (1 - fx) + plane[y1 * width + x1] * fx
                    result[y * width + x] = top * (1 - fy) + bottom * fy
                }
            }
            return result
        }
    }

    /// The layer as it's being built up: premultiplied color and coverage, each effect drawn over what is there.
    struct Canvas {
        let width: Int
        let height: Int
        var pixels: [SIMD4<Float>]

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            pixels = [SIMD4<Float>](repeating: .zero, count: width * height)
        }

        /// The layer's own pixels (premultiplied), at `fill` of their strength, over what is there.
        mutating func drawPixels(_ layer: [SIMD4<Float>], fill: Float) {
            for i in pixels.indices {
                let source = layer[i] * fill
                pixels[i] = source + pixels[i] * (1 - source.w)
            }
        }

        mutating func draw(_ coverage: [Float], opacity: Float, color: PaletteColor, mode: LayerBlendMode) {
            draw(coverage, opacity: opacity, uniform: SIMD3(Float(color.red), Float(color.green), Float(color.blue)), colors: nil, mode: mode)
        }

        mutating func draw(_ coverage: [Float], opacity: Float, colors: [SIMD3<Float>], mode: LayerBlendMode) {
            draw(coverage, opacity: opacity, uniform: .zero, colors: colors, mode: mode)
        }

        /// One effect's color where `coverage` × `opacity` says, blended with what is under it in `mode` — the
        /// W3C compositing formula Photoshop's modes follow: where nothing is under it, just its color.
        private mutating func draw(_ coverage: [Float], opacity: Float, uniform: SIMD3<Float>, colors: [SIMD3<Float>]?, mode: LayerBlendMode) {
            guard opacity > 0, coverage.count == pixels.count else { return }
            for i in pixels.indices {
                let amount = min(1, max(0, coverage[i] * opacity))
                guard amount > 0 else { continue }
                let color = colors?[i] ?? uniform
                let under = pixels[i]
                let backdropAlpha = under.w
                var blended = color
                if mode != .normal, backdropAlpha > 0 {
                    let backdrop = SIMD3(under.x, under.y, under.z) / backdropAlpha
                    let mixed = LayerStyleBlend.apply(mode, backdrop: simd_clamp01(backdrop), source: color)
                    blended = color * (1 - backdropAlpha) + mixed * backdropAlpha
                }
                let premultiplied = blended * amount + SIMD3(under.x, under.y, under.z) * (1 - amount)
                pixels[i] = SIMD4(premultiplied.x, premultiplied.y, premultiplied.z, amount + backdropAlpha * (1 - amount))
            }
        }

        func image(space: CGColorSpace) throws -> CGImage {
            var bytes = [UInt8](repeating: 0, count: pixels.count * 4)
            for i in pixels.indices {
                let pixel = pixels[i]
                let alpha = min(1, max(0, pixel.w))
                bytes[i * 4 + 3] = UInt8(alpha * 255 + 0.5)
                // Premultiplied, so no channel may exceed its coverage.
                bytes[i * 4] = UInt8(min(alpha, max(0, pixel.x)) * 255 + 0.5)
                bytes[i * 4 + 1] = UInt8(min(alpha, max(0, pixel.y)) * 255 + 0.5)
                bytes[i * 4 + 2] = UInt8(min(alpha, max(0, pixel.z)) * 255 + 0.5)
            }
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            else { throw ExportError.render }
            return image
        }
    }
}

nonisolated private func simd_clamp01(_ value: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(min(1, max(0, value.x)), min(1, max(0, value.y)), min(1, max(0, value.z)))
}

/// Photoshop's blend modes on unpremultiplied colors (0–1): what `source` makes of `backdrop`.
nonisolated enum LayerStyleBlend {
    static func apply(_ mode: LayerBlendMode, backdrop b: SIMD3<Float>, source s: SIMD3<Float>) -> SIMD3<Float> {
        switch mode {
        case .normal: return s
        case .hue: return setLuminosity(setSaturation(s, saturation(b)), luminosity(b))
        case .saturation: return setLuminosity(setSaturation(b, saturation(s)), luminosity(b))
        case .color: return setLuminosity(s, luminosity(b))
        case .luminosity: return setLuminosity(b, luminosity(s))
        default:
            return SIMD3(channel(mode, b.x, s.x), channel(mode, b.y, s.y), channel(mode, b.z, s.z))
        }
    }

    static func channel(_ mode: LayerBlendMode, _ b: Float, _ s: Float) -> Float {
        switch mode {
        case .normal: return s
        case .multiply: return b * s
        case .screen: return b + s - b * s
        case .overlay: return hardLight(s: b, b: s)
        case .darken: return min(b, s)
        case .lighten: return max(b, s)
        case .colorDodge: return dodge(b, s)
        case .colorBurn: return burn(b, s)
        case .linearBurn: return max(0, b + s - 1)
        case .linearDodge: return min(1, b + s)
        case .hardLight: return hardLight(s: s, b: b)
        case .softLight:
            if s <= 0.5 { return b - (1 - 2 * s) * b * (1 - b) }
            let d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : b.squareRoot()
            return b + (2 * s - 1) * (d - b)
        case .vividLight: return s <= 0.5 ? burn(b, 2 * s) : dodge(b, 2 * (s - 0.5))
        case .linearLight: return min(1, max(0, b + 2 * s - 1))
        case .pinLight: return s <= 0.5 ? min(b, 2 * s) : max(b, 2 * s - 1)
        case .hardMix: return b + s >= 1 ? 1 : 0
        case .difference: return abs(b - s)
        case .exclusion: return b + s - 2 * b * s
        case .subtract: return max(0, b - s)
        case .divide: return s <= 0 ? (b > 0 ? 1 : 0) : min(1, b / s)
        case .hue, .saturation, .color, .luminosity: return s
        }
    }

    private static func hardLight(s: Float, b: Float) -> Float {
        s <= 0.5 ? 2 * s * b : 1 - 2 * (1 - s) * (1 - b)
    }
    private static func dodge(_ b: Float, _ s: Float) -> Float {
        if b <= 0 { return 0 }
        if s >= 1 { return 1 }
        return min(1, b / (1 - s))
    }
    private static func burn(_ b: Float, _ s: Float) -> Float {
        if b >= 1 { return 1 }
        if s <= 0 { return 0 }
        return 1 - min(1, (1 - b) / s)
    }
    private static func luminosity(_ c: SIMD3<Float>) -> Float { 0.3 * c.x + 0.59 * c.y + 0.11 * c.z }
    private static func setLuminosity(_ c: SIMD3<Float>, _ l: Float) -> SIMD3<Float> {
        let d = l - luminosity(c)
        return clip(c + SIMD3(repeating: d))
    }
    private static func clip(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = luminosity(c)
        let n = min(c.x, c.y, c.z), x = max(c.x, c.y, c.z)
        var result = c
        if n < 0, l - n > 0 { result = SIMD3(repeating: l) + (result - SIMD3(repeating: l)) * l / (l - n) }
        if x > 1, x - l > 0 { result = SIMD3(repeating: l) + (result - SIMD3(repeating: l)) * (1 - l) / (x - l) }
        return result
    }
    private static func saturation(_ c: SIMD3<Float>) -> Float { max(c.x, c.y, c.z) - min(c.x, c.y, c.z) }
    private static func setSaturation(_ c: SIMD3<Float>, _ s: Float) -> SIMD3<Float> {
        let high = max(c.x, c.y, c.z), low = min(c.x, c.y, c.z)
        guard high > low else { return .zero }
        return (c - SIMD3(repeating: low)) * s / (high - low)
    }
}
