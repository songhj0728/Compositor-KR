import AppKit
import CoreGraphics
import CoreImage
import SwiftUI

/// Photoshop's contours: the curve an effect's falloff (a glow, a shadow, a satin, a bevel's slope) is bent through,
/// from 0 (far edge) to 1 (full).
nonisolated enum EffectContour: String, Codable, CaseIterable, Sendable {
    case linear = "Linear", cone = "Cone", coneInverted = "Cone - Inverted", gaussian = "Gaussian"
    case halfRound = "Half Round", ring = "Ring", ringDouble = "Ring - Double", rollingSlope = "Rolling Slope"
    case roundedSteps = "Rounded Steps", sawtooth = "Sawtooth", cove = "Cove - Deep"
    var displayName: LocalizedStringKey { LocalizedStringKey(rawValue) }
    func value(_ x: Float) -> Float {
        let x = min(1, max(0, x))
        switch self {
        case .linear: return x
        case .cone: return 1 - abs(2 * x - 1)
        case .coneInverted: return abs(2 * x - 1)
        case .gaussian: return x * x * (3 - 2 * x)
        case .halfRound: return (1 - (1 - x) * (1 - x)).squareRoot()
        case .ring: return 0.5 - 0.5 * cos(2 * .pi * x)
        case .ringDouble: return 0.5 - 0.5 * cos(4 * .pi * x)
        case .rollingSlope: return min(1, max(0, x + 0.12 * sin(4 * .pi * x)))
        case .roundedSteps:
            let steps: Float = 4, scaled = x * steps, step = min(steps - 1, scaled.rounded(.down)), t = scaled - step
            return min(1, (step + t * t * (3 - 2 * t)) / (steps - 1 + 1))
        case .sawtooth: return x >= 1 ? 1 : (x * 2).truncatingRemainder(dividingBy: 1)
        case .cove: return x * x * x
        }
    }
}

/// The tiles a Pattern Overlay or a bevel's Texture repeats: drawn in the effect's two colors (or as heights), at any
/// scale, so they stay sharp.
nonisolated enum EffectPattern: String, Codable, CaseIterable, Sendable {
    case checker = "Checkerboard", stripes = "Stripes", diagonal = "Diagonal Stripes", dots = "Dots", grid = "Grid"
    case bricks = "Bricks", noise = "Noise", waves = "Waves"
    var displayName: LocalizedStringKey { LocalizedStringKey(rawValue) }
    /// 0 (paper) to 1 (ink) at layer pixel (`x`, `y`); `scale` is 1 at 100%.
    func value(x: Float, y: Float, scale: Float) -> Float {
        let cell = 8 * max(0.01, scale)
        let u = x / cell, v = y / cell
        func fraction(_ value: Float) -> Float { value - value.rounded(.down) }
        switch self {
        case .checker:
            return (Int(u.rounded(.down)) + Int(v.rounded(.down))) & 1 == 0 ? 1 : 0
        case .stripes:
            return fraction(v / 2) < 0.5 ? 1 : 0
        case .diagonal:
            return fraction((u + v) / 2) < 0.5 ? 1 : 0
        case .dots:
            let dx = fraction(u / 2) - 0.5, dy = fraction(v / 2) - 0.5
            let distance = (dx * dx + dy * dy).squareRoot() * 2 * cell
            return min(1, max(0, 0.35 * 2 * cell - distance + 0.5))
        case .grid:
            let line = max(1, cell / 8)
            let px = fraction(u / 2) * 2 * cell, py = fraction(v / 2) * 2 * cell
            return px < line || py < line ? 1 : 0
        case .bricks:
            let row = (v / 1).rounded(.down)
            let shifted = u / 2 + (Int(row) & 1 == 0 ? 0 : 0.5)
            let px = fraction(shifted) * 2 * cell, py = fraction(v) * cell
            let line = max(1, cell / 8)
            return px < line || py < line ? 0 : 1
        case .noise:
            // Value noise on a cell grid, the same wherever it's drawn.
            let cellX = Int32(truncatingIfNeeded: Int((x / max(0.25, scale)).rounded(.down)))
            let cellY = Int32(truncatingIfNeeded: Int((y / max(0.25, scale)).rounded(.down)))
            var hash = UInt32(bitPattern: cellX) &* 374_761_393 &+ UInt32(bitPattern: cellY) &* 668_265_263
            hash = (hash ^ (hash >> 13)) &* 1_274_126_177
            hash ^= hash >> 16
            return Float(hash & 0xFFFF) / 65535
        case .waves:
            return 0.5 + 0.5 * sin(2 * .pi * (v / 2 + 0.25 * sin(2 * .pi * u / 4)))
        }
    }
}

/// A line drawn around what the layer shows, outside its edge, inside it or centered on it.
nonisolated struct StrokeEffect: Codable, Equatable, Sendable {
    /// Supported document-pixel width; preview work is bounded independently of this value.
    static let maxSize: CGFloat = 500
    var enabled: Bool? = nil // Missing in older projects means visible.
    var isEnabled: Bool { enabled ?? true }
    var size: CGFloat = 4
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var opacity: Double = 1
    var inside = false
    /// Straddling the edge, half in and half out. Missing means as `inside` says.
    var centered: Bool? = nil
    var blendMode: LayerBlendMode? = nil
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var isValid: Bool {
        size.isFinite && (0...StrokeEffect.maxSize).contains(size) && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// The layer's shape repeated behind it, offset and softened.
nonisolated struct ShadowEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    /// Where the light comes from, in degrees counterclockwise from the right, as Photoshop's dial is: 90 is from
    /// straight above, which drops the shadow straight down.
    var angle: CGFloat = 90
    var distance: CGFloat = 20
    var blur: CGFloat = 20
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var opacity: Double = 0.5
    /// How much of the size is solid before it softens, 0–100 (Photoshop's Spread).
    var spread: CGFloat? = nil
    var contour: EffectContour? = nil
    var blendMode: LayerBlendMode? = nil
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    /// Where the shadow sits, in layer pixels (y grows downward, as the layer's own pixels do).
    var offset: CGSize {
        let radians = angle * .pi / 180
        // The shadow falls away from the light, and a layer's pixels count y downward.
        return CGSize(width: -cos(radians) * distance, height: sin(radians) * distance)
    }
    var isValid: Bool {
        [angle, distance, blur].allSatisfy(\.isFinite) && (-360...360).contains(angle)
            && (0...5000).contains(distance) && (0...500).contains(blur)
            && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
            && spread.map { $0.isFinite && (0...100).contains($0) } ?? true
    }
}

/// A flat color over everything the layer shows.
nonisolated struct ColorOverlayEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var opacity: Double = 1
    var blendMode: LayerBlendMode? = nil
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var isValid: Bool {
        opacity.isFinite && (0...1).contains(opacity) && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// A shadow cast inside the layer's own edges, as though it were cut out of what is behind it.
nonisolated struct InnerShadowEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var angle: CGFloat = 90
    var distance: CGFloat = 10
    var blur: CGFloat = 10
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var opacity: Double = 0.5
    /// How much of the size is solid before it softens, 0–100 (Photoshop's Choke).
    var choke: CGFloat? = nil
    var contour: EffectContour? = nil
    var blendMode: LayerBlendMode? = nil
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    /// Where the shadow falls, in layer pixels (y grows downward).
    var offset: CGSize {
        let radians = angle * .pi / 180
        return CGSize(width: -cos(radians) * distance, height: sin(radians) * distance)
    }
    var isValid: Bool {
        [angle, distance, blur].allSatisfy(\.isFinite) && (-360...360).contains(angle)
            && (0...5000).contains(distance) && (0...500).contains(blur)
            && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
            && choke.map { $0.isFinite && (0...100).contains($0) } ?? true
    }
}

/// A soft glow drawn omnidirectionally around the outside of what the layer shows.
nonisolated struct OuterGlowEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var size: CGFloat = 20
    var red: CGFloat = 1
    var green: CGFloat = 1
    var blue: CGFloat = 1
    var opacity: Double = 0.75
    var spread: CGFloat? = nil
    var contour: EffectContour? = nil
    var blendMode: LayerBlendMode? = nil
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var isValid: Bool {
        size.isFinite && (0...500).contains(size)
            && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
            && spread.map { $0.isFinite && (0...100).contains($0) } ?? true
    }
}

/// A glow cast inside the layer's own edges, emanating inward from its boundary (or outward from its middle).
nonisolated struct InnerGlowEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var size: CGFloat = 10
    var red: CGFloat = 1
    var green: CGFloat = 1
    var blue: CGFloat = 1
    var opacity: Double = 0.75
    var choke: CGFloat? = nil
    var contour: EffectContour? = nil
    /// Photoshop's Source: the glow comes from the middle rather than the edge.
    var fromCenter: Bool? = nil
    var blendMode: LayerBlendMode? = nil
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var isValid: Bool {
        size.isFinite && (0...500).contains(size)
            && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
            && choke.map { $0.isFinite && (0...100).contains($0) } ?? true
    }
}

/// Light and shade that make the layer look raised (or pressed in): Photoshop's Bevel & Emboss, with its Contour and
/// Texture.
nonisolated struct BevelEffect: Codable, Equatable, Sendable {
    nonisolated enum Style: String, Codable, CaseIterable, Sendable {
        case outerBevel = "Outer Bevel", innerBevel = "Inner Bevel", emboss = "Emboss", pillowEmboss = "Pillow Emboss"
        var displayName: LocalizedStringKey { LocalizedStringKey(rawValue) }
    }
    nonisolated enum Technique: String, Codable, CaseIterable, Sendable {
        case smooth = "Smooth", chiselHard = "Chisel Hard", chiselSoft = "Chisel Soft"
        var displayName: LocalizedStringKey { LocalizedStringKey(rawValue) }
    }
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var style: Style = .innerBevel
    var technique: Technique = .smooth
    /// 1–1000 percent.
    var depth: CGFloat = 100
    /// Raised (true) or pressed in.
    var up = true
    /// 0–250 layer pixels.
    var size: CGFloat = 5
    /// 0–16 layer pixels.
    var soften: CGFloat = 0
    var angle: CGFloat = 120
    /// 0–90 degrees above the horizon.
    var altitude: CGFloat = 30
    var gloss: EffectContour = .linear
    var highlightMode: LayerBlendMode = .screen
    var highlightRed: CGFloat = 1
    var highlightGreen: CGFloat = 1
    var highlightBlue: CGFloat = 1
    var highlightOpacity: Double = 0.75
    var shadowMode: LayerBlendMode = .multiply
    var shadowRed: CGFloat = 0
    var shadowGreen: CGFloat = 0
    var shadowBlue: CGFloat = 0
    var shadowOpacity: Double = 0.75
    /// The Contour sub-effect: the slope bent through a curve, over `contourRange` percent (1–100) of it.
    var usesContour: Bool? = nil
    var contour: EffectContour = .halfRound
    var contourRange: CGFloat = 50
    /// The Texture sub-effect: a pattern pressed into the surface, at `textureScale` (1–1000%) and `textureDepth`
    /// (−1000–1000%).
    var usesTexture: Bool? = nil
    var texture: EffectPattern = .noise
    var textureScale: CGFloat = 100
    var textureDepth: CGFloat = 100
    var textureInvert = false
    var highlightColor: PaletteColor { PaletteColor(red: highlightRed, green: highlightGreen, blue: highlightBlue) }
    var shadowColor: PaletteColor { PaletteColor(red: shadowRed, green: shadowGreen, blue: shadowBlue) }
    var hasContour: Bool { usesContour ?? false }
    var hasTexture: Bool { usesTexture ?? false }
    /// How far outside the layer's edge the bevel reaches.
    var outerReach: CGFloat { style == .innerBevel ? 0 : size + soften * 2 + 2 }
    /// Leave a flat center even on small layers; opposite edge slopes must not meet in the middle.
    func size(clampedTo layer: CGSize) -> CGFloat { min(size, max(1, min(layer.width, layer.height) / 4)) }
    var isValid: Bool {
        [depth, size, soften, angle, altitude, contourRange, textureScale, textureDepth].allSatisfy(\.isFinite)
            && (1...1000).contains(depth) && (0...250).contains(size) && (0...16).contains(soften)
            && (-360...360).contains(angle) && (0...90).contains(altitude) && (1...100).contains(contourRange)
            && (1...1000).contains(textureScale) && (-1000...1000).contains(textureDepth)
            && [highlightOpacity, shadowOpacity].allSatisfy { $0.isFinite && (0...1).contains($0) }
            && [highlightRed, highlightGreen, highlightBlue, shadowRed, shadowGreen, shadowBlue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// Soft, silky shading inside the layer: its shape offset both ways along an angle and compared (Photoshop's Satin).
nonisolated struct SatinEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var opacity: Double = 0.5
    var blendMode: LayerBlendMode? = .multiply
    var angle: CGFloat = 19
    var distance: CGFloat = 11
    var size: CGFloat = 14
    var contour: EffectContour = .gaussian
    var invert = true
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var offset: CGSize {
        let radians = angle * .pi / 180
        return CGSize(width: cos(radians) * distance, height: -sin(radians) * distance)
    }
    var isValid: Bool {
        [angle, distance, size].allSatisfy(\.isFinite) && (-360...360).contains(angle)
            && (1...250).contains(distance) && (0...250).contains(size)
            && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// A repeating pattern over everything the layer shows, in two colors: ink where the pattern is, paper between.
nonisolated struct PatternOverlayEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var pattern: EffectPattern = .checker
    /// 1–1000 percent.
    var scale: CGFloat = 100
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var paperRed: CGFloat = 1
    var paperGreen: CGFloat = 1
    var paperBlue: CGFloat = 1
    var opacity: Double = 1
    var blendMode: LayerBlendMode? = nil
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var paperColor: PaletteColor { PaletteColor(red: paperRed, green: paperGreen, blue: paperBlue) }
    var isValid: Bool {
        scale.isFinite && (1...1000).contains(scale) && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue, paperRed, paperGreen, paperBlue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// What a layer draws around itself. Kept with the layer, so it follows every edit and can be changed or removed
/// at any time; the pixels themselves are never touched.
nonisolated struct LayerEffects: Codable, Equatable, Sendable {
    var stroke: StrokeEffect? = nil
    var shadow: ShadowEffect? = nil
    var colorOverlay: ColorOverlayEffect? = nil
    var innerShadow: InnerShadowEffect? = nil
    var outerGlow: OuterGlowEffect? = nil
    var innerGlow: InnerGlowEffect? = nil
    var bevel: BevelEffect? = nil
    var satin: SatinEffect? = nil
    var patternOverlay: PatternOverlayEffect? = nil
    /// Blending Options' Fill Opacity (0–1): the layer's own pixels fade, while its effects keep their strength.
    /// Missing means 1.
    var fillOpacity: Double? = nil
    var fill: Double { fillOpacity ?? 1 }
    var isEmpty: Bool { LayerEffectKind.allCases.allSatisfy { !contains($0) } && fill >= 1 }
    var isValid: Bool {
        (stroke?.isValid ?? true) && (shadow?.isValid ?? true)
            && (colorOverlay?.isValid ?? true) && (innerShadow?.isValid ?? true)
            && (outerGlow?.isValid ?? true) && (innerGlow?.isValid ?? true)
            && (bevel?.isValid ?? true) && (satin?.isValid ?? true) && (patternOverlay?.isValid ?? true)
            && fillOpacity.map { $0.isFinite && (0...1).contains($0) } ?? true
    }
    var kinds: [LayerEffectKind] { LayerEffectKind.allCases.filter { contains($0) } }
    func contains(_ kind: LayerEffectKind) -> Bool {
        switch kind {
        case .stroke: return stroke != nil
        case .shadow: return shadow != nil
        case .colorOverlay: return colorOverlay != nil
        case .innerShadow: return innerShadow != nil
        case .outerGlow: return outerGlow != nil
        case .innerGlow: return innerGlow != nil
        case .bevel: return bevel != nil
        case .satin: return satin != nil
        case .patternOverlay: return patternOverlay != nil
        }
    }
    func isEnabled(_ kind: LayerEffectKind) -> Bool {
        switch kind {
        case .stroke: return stroke?.isEnabled == true
        case .shadow: return shadow?.isEnabled == true
        case .colorOverlay: return colorOverlay?.isEnabled == true
        case .innerShadow: return innerShadow?.isEnabled == true
        case .outerGlow: return outerGlow?.isEnabled == true
        case .innerGlow: return innerGlow?.isEnabled == true
        case .bevel: return bevel?.isEnabled == true
        case .satin: return satin?.isEnabled == true
        case .patternOverlay: return patternOverlay?.isEnabled == true
        }
    }
    /// The effect's own color, and a way to put a new one back. A bevel's is its highlight; `secondary` asks for the
    /// other one an effect has (a bevel's shadow, a pattern's paper).
    func color(_ kind: LayerEffectKind, secondary: Bool = false) -> PaletteColor? {
        switch kind {
        case .stroke: return stroke?.color
        case .shadow: return shadow?.color
        case .colorOverlay: return colorOverlay?.color
        case .innerShadow: return innerShadow?.color
        case .outerGlow: return outerGlow?.color
        case .innerGlow: return innerGlow?.color
        case .bevel: return secondary ? bevel?.shadowColor : bevel?.highlightColor
        case .satin: return satin?.color
        case .patternOverlay: return secondary ? patternOverlay?.paperColor : patternOverlay?.color
        }
    }
    mutating func setColor(_ color: PaletteColor, for kind: LayerEffectKind, secondary: Bool = false) {
        switch kind {
        case .stroke: stroke?.red = color.red; stroke?.green = color.green; stroke?.blue = color.blue
        case .shadow: shadow?.red = color.red; shadow?.green = color.green; shadow?.blue = color.blue
        case .colorOverlay: colorOverlay?.red = color.red; colorOverlay?.green = color.green; colorOverlay?.blue = color.blue
        case .innerShadow: innerShadow?.red = color.red; innerShadow?.green = color.green; innerShadow?.blue = color.blue
        case .outerGlow: outerGlow?.red = color.red; outerGlow?.green = color.green; outerGlow?.blue = color.blue
        case .innerGlow: innerGlow?.red = color.red; innerGlow?.green = color.green; innerGlow?.blue = color.blue
        case .bevel:
            if secondary { bevel?.shadowRed = color.red; bevel?.shadowGreen = color.green; bevel?.shadowBlue = color.blue }
            else { bevel?.highlightRed = color.red; bevel?.highlightGreen = color.green; bevel?.highlightBlue = color.blue }
        case .satin: satin?.red = color.red; satin?.green = color.green; satin?.blue = color.blue
        case .patternOverlay:
            if secondary { patternOverlay?.paperRed = color.red; patternOverlay?.paperGreen = color.green; patternOverlay?.paperBlue = color.blue }
            else { patternOverlay?.red = color.red; patternOverlay?.green = color.green; patternOverlay?.blue = color.blue }
        }
    }
    mutating func remove(_ kind: LayerEffectKind) {
        var none = LayerEffects()
        none.fillOpacity = fillOpacity
        take(kind, from: none)
    }
    /// Puts `other`'s effect of this kind (or its absence) in place of this one's.
    mutating func take(_ kind: LayerEffectKind, from other: LayerEffects) {
        switch kind {
        case .stroke: stroke = other.stroke
        case .shadow: shadow = other.shadow
        case .colorOverlay: colorOverlay = other.colorOverlay
        case .innerShadow: innerShadow = other.innerShadow
        case .outerGlow: outerGlow = other.outerGlow
        case .innerGlow: innerGlow = other.innerGlow
        case .bevel: bevel = other.bevel
        case .satin: satin = other.satin
        case .patternOverlay: patternOverlay = other.patternOverlay
        }
    }
    mutating func setEnabled(_ enabled: Bool, for kind: LayerEffectKind) {
        switch kind {
        case .stroke: stroke?.enabled = enabled
        case .shadow: shadow?.enabled = enabled
        case .colorOverlay: colorOverlay?.enabled = enabled
        case .innerShadow: innerShadow?.enabled = enabled
        case .outerGlow: outerGlow?.enabled = enabled
        case .innerGlow: innerGlow?.enabled = enabled
        case .bevel: bevel?.enabled = enabled
        case .satin: satin?.enabled = enabled
        case .patternOverlay: patternOverlay?.enabled = enabled
        }
    }
    /// The blend mode an effect draws in (a bevel's highlight for a bevel). Missing means Normal.
    func blendMode(_ kind: LayerEffectKind, secondary: Bool = false) -> LayerBlendMode {
        switch kind {
        case .stroke: return stroke?.blendMode ?? .normal
        case .shadow: return shadow?.blendMode ?? .normal
        case .colorOverlay: return colorOverlay?.blendMode ?? .normal
        case .innerShadow: return innerShadow?.blendMode ?? .normal
        case .outerGlow: return outerGlow?.blendMode ?? .normal
        case .innerGlow: return innerGlow?.blendMode ?? .normal
        case .bevel: return (secondary ? bevel?.shadowMode : bevel?.highlightMode) ?? .normal
        case .satin: return satin?.blendMode ?? .normal
        case .patternOverlay: return patternOverlay?.blendMode ?? .normal
        }
    }
    mutating func setBlendMode(_ mode: LayerBlendMode, for kind: LayerEffectKind, secondary: Bool = false) {
        switch kind {
        case .stroke: stroke?.blendMode = mode
        case .shadow: shadow?.blendMode = mode
        case .colorOverlay: colorOverlay?.blendMode = mode
        case .innerShadow: innerShadow?.blendMode = mode
        case .outerGlow: outerGlow?.blendMode = mode
        case .innerGlow: innerGlow?.blendMode = mode
        case .bevel: if secondary { bevel?.shadowMode = mode } else { bevel?.highlightMode = mode }
        case .satin: satin?.blendMode = mode
        case .patternOverlay: patternOverlay?.blendMode = mode
        }
    }
    /// Leaves an effect's blend mode unset (Normal).
    mutating func clearBlendMode(_ kind: LayerEffectKind) {
        switch kind {
        case .stroke: stroke?.blendMode = nil
        case .shadow: shadow?.blendMode = nil
        case .colorOverlay: colorOverlay?.blendMode = nil
        case .innerShadow: innerShadow?.blendMode = nil
        case .outerGlow: outerGlow?.blendMode = nil
        case .innerGlow: innerGlow?.blendMode = nil
        case .bevel: break
        case .satin: satin?.blendMode = nil
        case .patternOverlay: patternOverlay?.blendMode = nil
        }
    }
    /// A new effect of this kind with Photoshop's defaults, in `color` where the effect takes the one being painted with.
    static func standard(_ kind: LayerEffectKind, color: PaletteColor) -> LayerEffects {
        var effects = LayerEffects()
        switch kind {
        case .stroke:
            var new = StrokeEffect()
            new.red = color.red; new.green = color.green; new.blue = color.blue
            effects.stroke = new
        case .shadow: effects.shadow = ShadowEffect()
        case .colorOverlay:
            var new = ColorOverlayEffect()
            new.red = color.red; new.green = color.green; new.blue = color.blue
            effects.colorOverlay = new
        case .innerShadow: effects.innerShadow = InnerShadowEffect()
        case .outerGlow: effects.outerGlow = OuterGlowEffect()
        case .innerGlow: effects.innerGlow = InnerGlowEffect()
        case .bevel: effects.bevel = BevelEffect()
        case .satin: effects.satin = SatinEffect()
        case .patternOverlay: effects.patternOverlay = PatternOverlayEffect()
        }
        return effects
    }
    var visible: LayerEffects {
        LayerEffects(stroke: stroke?.isEnabled == true ? stroke : nil,
                     shadow: shadow?.isEnabled == true ? shadow : nil,
                     colorOverlay: colorOverlay?.isEnabled == true ? colorOverlay : nil,
                     innerShadow: innerShadow?.isEnabled == true ? innerShadow : nil,
                     outerGlow: outerGlow?.isEnabled == true ? outerGlow : nil,
                     innerGlow: innerGlow?.isEnabled == true ? innerGlow : nil,
                     bevel: bevel?.isEnabled == true ? bevel : nil,
                     satin: satin?.isEnabled == true ? satin : nil,
                     patternOverlay: patternOverlay?.isEnabled == true ? patternOverlay : nil,
                     fillOpacity: fill < 1 ? fillOpacity : nil)
    }
    /// The same effects for the layer drawn `factor` times its size, as the canvas previews it.
    func scaled(by factor: CGFloat) -> LayerEffects {
        guard factor != 1 else { return self }
        var effects = self
        effects.stroke?.size *= factor
        effects.shadow?.distance *= factor
        effects.shadow?.blur *= factor
        effects.innerShadow?.distance *= factor
        effects.innerShadow?.blur *= factor
        effects.outerGlow?.size *= factor
        effects.innerGlow?.size *= factor
        if var bevel = effects.bevel {
            bevel.size *= factor
            bevel.soften *= factor
            bevel.textureScale = min(1000, max(1, bevel.textureScale * factor))
            effects.bevel = bevel
        }
        if var satin = effects.satin {
            satin.distance = max(1, satin.distance * factor)
            satin.size *= factor
            effects.satin = satin
        }
        if let scale = effects.patternOverlay?.scale { effects.patternOverlay?.scale = min(1000, max(1, scale * factor)) }
        return effects
    }
    /// Whether anything here needs format version 12: the effects and settings Photoshop's Layer Style dialog added.
    var usesLayerStyle: Bool {
        if bevel != nil || satin != nil || patternOverlay != nil || fillOpacity != nil { return true }
        if stroke?.blendMode != nil || stroke?.centered != nil { return true }
        if shadow?.blendMode != nil || shadow?.spread != nil || shadow?.contour != nil { return true }
        if colorOverlay?.blendMode != nil { return true }
        if innerShadow?.blendMode != nil || innerShadow?.choke != nil || innerShadow?.contour != nil { return true }
        if outerGlow?.blendMode != nil || outerGlow?.spread != nil || outerGlow?.contour != nil { return true }
        return innerGlow?.blendMode != nil || innerGlow?.choke != nil || innerGlow?.contour != nil || innerGlow?.fromCenter != nil
    }
    /// Whether these effects need `LayerStyleRenderer`: anything past what the GPU's single pass draws — the effects
    /// Photoshop's Layer Style adds, blend modes, spread and choke, contours, a fading fill.
    var needsStyleRenderer: Bool {
        let effects = visible
        if effects.bevel != nil || effects.satin != nil || effects.patternOverlay != nil || effects.fill < 1 { return true }
        func special(_ mode: LayerBlendMode?) -> Bool { mode.map { $0 != .normal } ?? false }
        func curved(_ contour: EffectContour?) -> Bool { contour.map { $0 != .linear } ?? false }
        func spreads(_ amount: CGFloat?) -> Bool { (amount ?? 0) > 0 }
        if let stroke = effects.stroke, special(stroke.blendMode) || stroke.centered == true { return true }
        if let shadow = effects.shadow, special(shadow.blendMode) || spreads(shadow.spread) || curved(shadow.contour) { return true }
        if let overlay = effects.colorOverlay, special(overlay.blendMode) { return true }
        if let inner = effects.innerShadow, special(inner.blendMode) || spreads(inner.choke) || curved(inner.contour) { return true }
        if let glow = effects.outerGlow, special(glow.blendMode) || spreads(glow.spread) || curved(glow.contour) { return true }
        if let glow = effects.innerGlow, special(glow.blendMode) || spreads(glow.choke) || curved(glow.contour) || glow.fromCenter == true { return true }
        return false
    }
}

/// Every layer style, in the order Photoshop's Layer Style dialog lists them (and the Layers panel shows them): the
/// top of the list draws on top.
nonisolated enum LayerEffectKind: String, CaseIterable, Sendable {
    case bevel = "Bevel & Emboss", stroke = "Stroke", innerShadow = "Inner Shadow", innerGlow = "Inner Glow"
    case satin = "Satin", colorOverlay = "Color Overlay", patternOverlay = "Pattern Overlay"
    case outerGlow = "Outer Glow", shadow = "Drop Shadow"
    /// `rawValue` as a localizable display name; `rawValue` itself stays the stable, unlocalized identifier.
    var displayName: LocalizedStringKey {
        switch self {
        case .stroke: return "Stroke"
        case .shadow: return "Drop Shadow"
        case .colorOverlay: return "Color Overlay"
        case .innerShadow: return "Inner Shadow"
        case .outerGlow: return "Outer Glow"
        case .innerGlow: return "Inner Glow"
        case .bevel: return "Bevel & Emboss"
        case .satin: return "Satin"
        case .patternOverlay: return "Pattern Overlay"
        }
    }
    /// `displayName`, resolved to a plain `String` for AppKit APIs (labels, tooltips, accessibility)
    /// that don't consult String Catalogs on their own the way SwiftUI's `Text` does.
    var localizedText: String { String(localized: String.LocalizationValue(rawValue)) }
    /// The blend mode a new effect of this kind takes in the Layer Style dialog, as Photoshop's does.
    var standardBlendMode: LayerBlendMode {
        switch self {
        case .shadow, .innerShadow, .satin: return .multiply
        case .outerGlow, .innerGlow: return .screen
        default: return .normal
        }
    }
}

struct LayerEffectSelection: Equatable {
    let layerID: UUID
    let kind: LayerEffectKind
}

/// Which page of the Layer Style dialog is showing: Blending Options, or one effect.
nonisolated enum LayerStylePage: Hashable, Sendable {
    case blending
    case effect(LayerEffectKind)
    /// Bevel & Emboss's own Contour and Texture, listed under it as in Photoshop.
    case bevelContour, bevelTexture
}

/// The Layer Style dialog, open on one layer. Its changes show on the canvas as they're made and become one undo
/// step on OK; Cancel puts back what the layer had when the dialog opened.
struct LayerStyleEdit: Equatable {
    let layerID: UUID
    let originalEffects: LayerEffects?
    let originalOpacity: Double
    let originalBlendMode: LayerBlendMode
    var page: LayerStylePage
}

extension EditorSession {
    var canEditEffects: Bool { canEditLayers && activeLayer?.isGroup == false && activeLayer?.asset != nil }
    var activeEffects: LayerEffects { activeLayer?.effects ?? LayerEffects() }
    /// The effects of the layer the Layer Style dialog is open on.
    var editingEffects: LayerEffects {
        document?.layers.first(where: { $0.id == layerStyle?.layerID })?.effects ?? LayerEffects()
    }
    var layerStyleLayer: ImageLayer? { document?.layers.first(where: { $0.id == layerStyle?.layerID }) }
    var selectedEffect: LayerEffectSelection? {
        guard let effectSelection, effectSelection.layerID == activeLayerID,
              activeEffects.contains(effectSelection.kind) else { return nil }
        return effectSelection
    }

    /// Adds an effect from the Layers panel's menu: the Layer Style dialog opens on it, as Photoshop's does, and
    /// Cancel takes it away again.
    func addEffect(_ kind: LayerEffectKind) {
        guard canEditEffects, let id = activeLayerID else { return }
        openLayerStyle(on: id, page: .effect(kind))
        setLayerStyleEffect(kind, on: true)
    }

    /// Opens the Layer Style dialog on `id` (the active layer when nil), at `page`.
    func openLayerStyle(on id: UUID? = nil, page: LayerStylePage = .blending) {
        guard let id = id ?? activeLayerID else { return }
        if let open = layerStyle {
            if open.layerID == id { layerStyle?.page = page; return }
            finishLayerStyle(commit: true)
        }
        guard canEditLayers, let layer = document?.layers.first(where: { $0.id == id }), !layer.isGroup, layer.asset != nil else { return }
        finishOpacityEdit()
        if id != activeLayerID { selectLayer(id); selectedLayerIDs = [id] }
        layerStyle = LayerStyleEdit(layerID: id, originalEffects: layer.effects, originalOpacity: layer.opacity,
                                    originalBlendMode: layer.blendMode, page: page)
    }

    func selectEffect(_ kind: LayerEffectKind, on id: UUID, editing: Bool = false) {
        guard canEditLayers || layerStyle != nil, document?.layers.first(where: { $0.id == id })?.effects?.contains(kind) == true else { return }
        let selection = LayerEffectSelection(layerID: id, kind: kind)
        if layerStyle == nil || layerStyle?.layerID != id { selectLayer(id) }
        selectedLayerIDs = [id]
        isMaskSelected = false
        effectSelection = selection
        if editing { openLayerStyle(on: id, page: .effect(kind)) }
    }

    /// Puts the layer's style straight into the document while the dialog is open: the canvas follows, and OK makes
    /// the whole visit one undo step.
    private func applyLayerStyle(effects: LayerEffects? = nil, opacity: Double? = nil, blendMode: LayerBlendMode? = nil) {
        guard let edit = layerStyle, let index = document?.layers.firstIndex(where: { $0.id == edit.layerID }) else { return }
        if let effects {
            guard effects.isValid else { return }
            let stored = effects.isEmpty ? nil : effects
            if document?.layers[index].effects != stored { document?.layers[index].effects = stored }
        }
        if let opacity, opacity.isFinite, document?.layers[index].opacity != opacity {
            document?.layers[index].opacity = min(1, max(0, opacity))
        }
        if let blendMode, document?.layers[index].blendMode != blendMode { document?.layers[index].blendMode = blendMode }
    }

    /// Changes the effects of the layer the Layer Style dialog is open on.
    func changeLayerStyle(_ change: (inout LayerEffects) -> Void) {
        guard layerStyle != nil else { return }
        var effects = editingEffects
        change(&effects)
        applyLayerStyle(effects: effects)
    }
    /// Kept for the effect color picker: the dialog's effects.
    func changeEffects(_ change: (inout LayerEffects) -> Void) { changeLayerStyle(change) }

    func setLayerStyleOpacity(_ opacity: Double) { applyLayerStyle(opacity: opacity) }
    func setLayerStyleBlendMode(_ mode: LayerBlendMode) { applyLayerStyle(blendMode: mode) }

    /// The dialog's checkbox for an effect: on adds it with Photoshop's defaults (or shows it again), off hides it.
    func setLayerStyleEffect(_ kind: LayerEffectKind, on: Bool) {
        changeLayerStyle { effects in
            if on, !effects.contains(kind) {
                var added = LayerEffects.standard(kind, color: backgroundColor)
                if kind != .bevel { added.setBlendMode(kind.standardBlendMode, for: kind) }
                effects.take(kind, from: added)
            } else {
                effects.setEnabled(on, for: kind)
            }
        }
    }

    /// OK keeps what the dialog made, as one undo step; Cancel puts the layer back as it was.
    func finishLayerStyle(commit: Bool) {
        guard let edit = layerStyle else { return }
        if let picker = colorPicker, case .effect = picker.target { closeColorPicker(commit: commit) }
        layerStyle = nil
        guard let index = document?.layers.firstIndex(where: { $0.id == edit.layerID }), let layer = document?.layers[index] else { return }
        let made = (layer.effects, layer.opacity, layer.blendMode)
        document?.layers[index].effects = edit.originalEffects
        document?.layers[index].opacity = edit.originalOpacity
        document?.layers[index].blendMode = edit.originalBlendMode
        guard commit, made.0 != edit.originalEffects || made.1 != edit.originalOpacity || made.2 != edit.originalBlendMode else {
            if selectedEffect == nil { effectSelection = nil }
            return
        }
        beginEdit("Layer Style")
        document?.layers[index].effects = made.0
        document?.layers[index].opacity = made.1
        document?.layers[index].blendMode = made.2
        endEdit()
        if selectedEffect == nil { effectSelection = nil }
    }

    func setEffects(_ effects: LayerEffects, on id: UUID? = nil, name: String = "Layer Effects") {
        guard canEditLayers, effects.isValid,
              let index = document?.layers.firstIndex(where: { $0.id == (id ?? activeLayerID) }),
              document?.layers[index].isGroup == false, document?.layers[index].asset != nil,
              document?.layers[index].effects != (effects.isEmpty ? nil : effects) else { return }
        finishOpacityEdit()
        beginEdit(name)
        document?.layers[index].effects = effects.isEmpty ? nil : effects
        endEdit()
    }

    func canCopyEffect(_ kind: LayerEffectKind, from source: UUID, to target: UUID) -> Bool {
        guard canEditLayers, layerStyle == nil, source != target,
              document?.layers.first(where: { $0.id == source })?.effects?.contains(kind) == true,
              let layer = document?.layers.first(where: { $0.id == target }),
              !layer.isGroup, layer.asset != nil else { return false }
        return true
    }

    func copyEffect(_ kind: LayerEffectKind, from source: UUID, to target: UUID) {
        guard canCopyEffect(kind, from: source, to: target),
              let original = document?.layers.first(where: { $0.id == source })?.effects else { return }
        var effects = document?.layers.first(where: { $0.id == target })?.effects ?? LayerEffects()
        effects.take(kind, from: original)
        setEffects(effects, on: target, name: "Copy " + kind.rawValue)
        selectEffect(kind, on: target)
    }

    func toggleEffect(_ kind: LayerEffectKind, on id: UUID) {
        if layerStyle?.layerID == id {
            setLayerStyleEffect(kind, on: !editingEffects.isEnabled(kind))
            return
        }
        guard var effects = document?.layers.first(where: { $0.id == id })?.effects else { return }
        let enabled = effects.isEnabled(kind)
        effects.setEnabled(!enabled, for: kind)
        setEffects(effects, on: id, name: (enabled ? "Hide " : "Show ") + kind.rawValue)
    }

    func removeSelectedEffect() {
        guard let selectedEffect else { return }
        if layerStyle?.layerID == selectedEffect.layerID {
            changeLayerStyle { $0.remove(selectedEffect.kind) }
            effectSelection = nil
            return
        }
        guard canEditLayers, var effects = document?.layers.first(where: { $0.id == selectedEffect.layerID })?.effects else { return }
        effects.remove(selectedEffect.kind)
        setEffects(effects, on: selectedEffect.layerID, name: "Remove " + selectedEffect.kind.rawValue)
        effectSelection = nil
    }
}

/// Draws a layer's effects around its pixels. The result is the layer as it should appear — shadow behind, stroke
/// around, pixels on top — on a canvas grown by `inset` pixels on every side, so the caller places it by growing
/// the layer's transform in the same proportion.
nonisolated enum LayerEffectsRenderer {
    /// The last few layers drawn with effects, so the canvas doesn't rebuild them on every redraw.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(image: CGImage, mask: CGImage?, effects: LayerEffects, result: CGImage, inset: CGFloat)] = []
        func result(image: CGImage, mask: CGImage?, effects: LayerEffects,
                    make: () throws -> (image: CGImage, inset: CGFloat)) throws -> (image: CGImage, inset: CGFloat) {
            lock.lock()
            let hit = entries.first { $0.image === image && $0.mask === mask && $0.effects == effects }
            lock.unlock()
            if let hit { return (hit.result, hit.inset) }
            let made = try make()
            lock.lock()
            let budget = 64 * 1024 * 1024
            let cost = made.image.bytesPerRow * made.image.height + image.bytesPerRow * image.height + (mask.map { $0.bytesPerRow * $0.height } ?? 0)
            if cost <= budget {
                entries.append((image, mask, effects, made.image, made.inset))
                while entries.count > 8 || entries.reduce(0, { $0 + $1.result.bytesPerRow * $1.result.height + $1.image.bytesPerRow * $1.image.height + ($1.mask.map { $0.bytesPerRow * $0.height } ?? 0) }) > budget {
                    entries.removeFirst()
                }
            }
            lock.unlock()
            return made
        }
    }
    private static let cache = Cache()

    /// `image` with `effects` around it, reusing the last result for the same pixels, mask and settings. Nil when
    /// there is nothing to draw or the effects can't be made, so the caller draws the layer as it is.
    static func cached(_ image: CGImage, mask: CGImage?, effects: LayerEffects?) -> (image: CGImage, inset: CGFloat)? {
        guard let effects = effects?.visible, !effects.isEmpty, effects.isValid else { return nil }
        return try? cache.result(image: image, mask: mask, effects: effects) {
            try render(image, mask: mask, effects: effects)
        }
    }

    /// The layer's transform grown by the margin its effects need, so the bigger image lands in the same place.
    static func placed(_ transform: LayerTransform, image: CGImage, inset: CGFloat) -> LayerTransform {
        var grown = transform
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard width > inset * 2, height > inset * 2 else { return transform }
        grown.size = CGSize(width: transform.size.width * width / (width - inset * 2),
                            height: transform.size.height * height / (height - inset * 2))
        grown.origin = CGPoint(x: transform.center.x - grown.size.width / 2, y: transform.center.y - grown.size.height / 2)
        return grown
    }

    static func margin(for effects: LayerEffects) -> CGFloat {
        let effects = effects.visible
        var margin: CGFloat = 0
        if let stroke = effects.stroke, !stroke.inside || stroke.centered == true { margin = max(margin, stroke.size) }
        if let shadow = effects.shadow {
            margin = max(margin, shadow.distance + shadow.blur * 3)
        }
        if let glow = effects.outerGlow {
            margin = max(margin, glow.size * 3)
        }
        if let bevel = effects.bevel { margin = max(margin, bevel.outerReach) }
        return ceil(margin) + 2
    }

    /// `image` with `effects` around it. `mask` (the layer's own mask, in its pixel grid) hides part of the layer
    /// before the effects are made, so they follow the shape that is actually shown, as in Photoshop.
    static func render(_ image: CGImage, mask: CGImage?, effects: LayerEffects) throws -> (image: CGImage, inset: CGFloat) {
        let effects = effects.visible
        guard effects.isValid else { throw ProjectError.invalid }
        let inset = margin(for: effects)
        let width = image.width + Int(inset) * 2, height = image.height + Int(inset) * 2
        guard width > 0, height > 0, width * height <= DocumentLimits.maxSurfacePixels else { throw ProjectError.tooLarge }
        let placed = CGRect(x: inset, y: inset, width: CGFloat(image.width), height: CGFloat(image.height))
        let full = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        // The layer as it is shown: its pixels through its mask.
        let shown = try masked(image, mask: mask)
        // Photoshop's Layer Style past the GPU pass's reach: drawn whole in floating point.
        if effects.needsStyleRenderer {
            let padded = try BrushRaster.context(width: width, height: height, mask: false)
            BrushRaster.draw(shown, in: placed, mask: false, context: padded)
            guard let room = padded.makeImage() else { throw ExportError.render }
            return (try LayerStyleRenderer.render(room, effects: effects, origin: CGPoint(x: -inset, y: -inset),
                                                  fullSize: CGSize(width: image.width, height: image.height)), inset)
        }
        if let metal = MetalLayerEffects.shared {
            // The pixels with room around them, then the stroke and shadow drawn on the GPU.
            let padded = try BrushRaster.context(width: width, height: height, mask: false)
            BrushRaster.draw(shown, in: placed, mask: false, context: padded)
            if let room = padded.makeImage(), let built = try? metal.render(room, effects: effects) {
                return (built, inset)
            }
        }
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        if let shadow = effects.shadow, shadow.opacity > 0 {
            let alpha = try coverage(shown, in: placed.offsetBy(dx: shadow.offset.width, dy: shadow.offset.height),
                                     size: CGSize(width: width, height: height), blur: shadow.blur)
            fill(shadow.color, alpha: shadow.opacity, coverage: alpha, in: full, context: context)
        }
        if let glow = effects.outerGlow, glow.opacity > 0 {
            let alpha = try outerGlowCoverage(shown, placed: placed, size: CGSize(width: width, height: height), glow: glow)
            fill(glow.color, alpha: glow.opacity, coverage: alpha, in: full, context: context)
        }
        // An outside stroke sits behind the layer's own pixels; an inside one is drawn over them, or the pixels
        // would simply cover it.
        let stroke = effects.stroke.flatMap { $0.size > 0 && $0.opacity > 0 ? $0 : nil }
        func drawStroke(_ stroke: StrokeEffect) throws {
            let alpha = try strokeCoverage(shown, placed: placed, size: CGSize(width: width, height: height), stroke: stroke)
            fill(stroke.color, alpha: stroke.opacity, coverage: alpha, in: full, context: context)
        }
        if let stroke, !stroke.inside { try drawStroke(stroke) }
        // Source-over preserves effects beneath transparent pixels. BrushRaster.draw uses .copy,
        // which would erase the stroke/shadow everywhere inside the source's rectangular bounds.
        context.saveGState()
        context.translateBy(x: placed.minX, y: placed.maxY)
        context.scaleBy(x: 1, y: -1)
        context.setBlendMode(.normal)
        context.draw(shown, in: CGRect(origin: .zero, size: placed.size))
        context.restoreGState()
        // Over the pixels: a flat color, then a shadow inside the layer's own edges.
        if let overlay = effects.colorOverlay, overlay.isEnabled, overlay.opacity > 0,
           let shape = try? coverage(shown, in: placed, size: CGSize(width: width, height: height), blur: 0) {
            fill(overlay.color, alpha: overlay.opacity, coverage: shape, in: full, context: context)
        }
        if let innerGlow = effects.innerGlow, innerGlow.isEnabled, innerGlow.opacity > 0,
           let insideGlow = try? innerGlowCoverage(shown, placed: placed, size: CGSize(width: width, height: height), glow: innerGlow) {
            fill(innerGlow.color, alpha: innerGlow.opacity, coverage: insideGlow, in: full, context: context)
        }
        if let inner = effects.innerShadow, inner.isEnabled, inner.opacity > 0,
           let inside = try? innerCoverage(shown, placed: placed, size: CGSize(width: width, height: height), shadow: inner) {
            fill(inner.color, alpha: inner.opacity, coverage: inside, in: full, context: context)
        }
        if let stroke, stroke.inside { try drawStroke(stroke) }
        guard let result = context.makeImage() else { throw ExportError.render }
        return (result, inset)
    }

    /// An inner glow's coverage: the source shape softened inward, kept to the layer's own shape.
    static func innerGlowCoverage(_ image: CGImage, placed: CGRect, size: CGSize, glow: InnerGlowEffect) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let shape = try coverage(image, in: placed, size: size, blur: 0)
        let blurred = try coverage(image, in: placed, size: size, blur: glow.size)
        var inside = try GuidedMatte.levels(of: shape, width: width, height: height)
        let outside = try GuidedMatte.levels(of: blurred, width: width, height: height)
        for i in inside.indices { inside[i] = max(0, min(1, inside[i] * (1 - outside[i]))) }
        return try GuidedMatte.image(inside, width: width, height: height)
    }

    /// The layer's pixels with its mask applied, or the pixels as they are when it has none.
    private static func masked(_ image: CGImage, mask: CGImage?) throws -> CGImage {
        guard let mask else { return image }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        // Draw the source and its grayscale mask in the same image coordinate system.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.clip(to: bounds, mask: mask)
        context.draw(image, in: bounds)
        guard let result = context.makeImage() else { throw ExportError.render }
        return result
    }

    /// A shadow's coverage for one piece of a layer: its shape, moved and softened.
    static func shadowCoverage(_ pixels: CGImage, in size: CGSize, offset: CGSize, blur: CGFloat) throws -> CGImage {
        let placed = CGRect(origin: .zero, size: CGSize(width: pixels.width, height: pixels.height))
        return try coverage(pixels, in: placed.offsetBy(dx: offset.width, dy: offset.height), size: size, blur: blur)
    }

    /// An inner shadow's coverage: what lies outside the layer, moved and softened, kept to the layer's own shape.
    static func innerCoverage(_ image: CGImage, placed: CGRect, size: CGSize, shadow: InnerShadowEffect) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let shape = try coverage(image, in: placed, size: size, blur: 0)
        let moved = try coverage(image, in: placed.offsetBy(dx: shadow.offset.width, dy: shadow.offset.height),
                                 size: size, blur: shadow.blur)
        var inside = try GuidedMatte.levels(of: shape, width: width, height: height)
        let outside = try GuidedMatte.levels(of: moved, width: width, height: height)
        for i in inside.indices { inside[i] = max(0, min(1, inside[i] * (1 - outside[i]))) }
        return try GuidedMatte.image(inside, width: width, height: height)
    }

    /// An outer glow's coverage: the layer's shape softened omnidirectionally, with the shape interior excluded.
    static func outerGlowCoverage(_ image: CGImage, placed: CGRect, size: CGSize, glow: OuterGlowEffect) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let shape = try coverage(image, in: placed, size: size, blur: 0)
        let soft = try coverage(image, in: placed, size: size, blur: glow.size)
        var levels = try GuidedMatte.levels(of: soft, width: width, height: height)
        let mask = try GuidedMatte.levels(of: shape, width: width, height: height)
        for i in levels.indices {
            levels[i] = max(0, min(1, levels[i] * (1 - mask[i])))
        }
        return try GuidedMatte.image(levels, width: width, height: height)
    }

    /// A stroke's ring for one piece of a layer.
    static func ringCoverage(_ pixels: CGImage, in size: CGSize, stroke: StrokeEffect) throws -> CGImage {
        try strokeCoverage(pixels, placed: CGRect(origin: .zero, size: CGSize(width: pixels.width, height: pixels.height)),
                           size: size, stroke: stroke)
    }

    /// The shape's own alpha, placed in a bigger canvas and optionally softened: gray, white where the layer is.
    static func coverage(_ image: CGImage, in rect: CGRect, size: CGSize, blur: CGFloat) throws -> CGImage {
        let context = try BrushRaster.context(width: Int(size.width), height: Int(size.height), mask: true)
        BrushRaster.draw(image, in: rect, mask: true, context: context)
        guard let sharp = context.makeImage() else { throw ExportError.render }
        guard blur > 0 else { return sharp }
        let extent = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let soft = CIImage(cgImage: sharp).clampedToExtent().applyingGaussianBlur(sigma: blur / 2).cropped(to: extent)
        return try PixelAdjust.render(soft, width: Int(size.width), height: Int(size.height), isMask: true)
    }

    /// Where a stroke lands: the shape grown (or shrunk) by its size, less the shape itself. A square reach, not a
    /// round one — a round one eats into the corners of a rectangle, which reads as a wobbly edge.
    static func strokeCoverage(_ image: CGImage, placed: CGRect, size: CGSize, stroke: StrokeEffect) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let shape = try coverage(image, in: placed, size: size, blur: 0)
        var levels = try GuidedMatte.levels(of: shape, width: width, height: height)
        let reach = max(1, Int(stroke.size.rounded()))
        let moved = extreme(levels, width: width, height: height, reach: reach, smallest: stroke.inside)
        // The ring between the two shapes.
        for i in levels.indices {
            levels[i] = stroke.inside ? max(0, levels[i] - moved[i]) : max(0, moved[i] - levels[i])
        }
        return try GuidedMatte.image(levels, width: width, height: height)
    }

    /// The largest (or smallest) value within `reach` on each side: two sliding-window passes, so the cost doesn't
    /// grow with the reach. Core Image's own morphology filters stall on a wide stroke.
    static func extreme(_ source: [Float], width: Int, height: Int, reach: Int, smallest: Bool) -> [Float] {
        guard width > 0, height > 0, source.count == width * height else { return [] }
        let radius = max(0, reach)
        var pass = [Float](repeating: 0, count: source.count)
        var result = [Float](repeating: 0, count: source.count)
        // Each index enters and leaves the deque at most once. A head index avoids Array.removeFirst's
        // shifting cost; one reusable buffer avoids allocating a queue and values array for every line.
        var queue = [Int](repeating: 0, count: max(width, height))
        func sweep(_ input: UnsafeBufferPointer<Float>, _ output: UnsafeMutableBufferPointer<Float>,
                   lines: Int, count: Int, lineStep: Int, elementStep: Int) {
            for line in 0..<lines {
                let base = line * lineStep
                var head = 0, tail = 0, next = 0
                for center in 0..<count {
                    while next <= min(count - 1, center + radius) {
                        let value = input[base + next * elementStep]
                        while tail > head {
                            let previous = input[base + queue[tail - 1] * elementStep]
                            if smallest ? previous < value : previous > value { break }
                            tail -= 1
                        }
                        queue[tail] = next
                        tail += 1
                        next += 1
                    }
                    while head < tail, queue[head] < center - radius { head += 1 }
                    let outside = center < radius || center + radius >= count
                    output[base + center * elementStep] = smallest && outside ? 0 : input[base + queue[head] * elementStep]
                }
            }
        }
        source.withUnsafeBufferPointer { input in
            pass.withUnsafeMutableBufferPointer { output in
                sweep(input, output, lines: height, count: width, lineStep: width, elementStep: 1)
            }
        }
        pass.withUnsafeBufferPointer { input in
            result.withUnsafeMutableBufferPointer { output in
                sweep(input, output, lines: width, count: height, lineStep: 1, elementStep: width)
            }
        }
        return result
    }

    private static func fill(_ color: PaletteColor, alpha: Double, coverage: CGImage, in rect: CGRect, context: CGContext) {
        // Coverage is a CGImage: use the same local image flip as the source, so asymmetric marks
        // and their effects line up instead of mirroring the coverage vertically.
        BrushRaster.fill(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1),
                         coverage: coverage, in: rect, alpha: CGFloat(alpha), context: context)
    }
}
