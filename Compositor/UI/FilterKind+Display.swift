import SwiftUI

extension FilterKind {
    /// `rawValue` as a localizable display name; `rawValue` itself stays the stable, unlocalized identifier.
    nonisolated var displayName: LocalizedStringKey {
        switch self {
        case .gaussianBlur: return "Gaussian Blur"
        case .motionBlur: return "Motion Blur"
        case .addNoise: return "Add Noise"
        case .vignette: return "Vignette"
        case .bloomGlow: return "Bloom / Glow"
        case .dither: return "Dither"
        case .tonalContrast: return "Tonal Contrast"
        case .lensCorrection: return "Lens Correction"
        case .cameraRaw: return "Camera Raw Filter"
        case .removeBackground: return "Remove Background"
        case .contentAwareFill: return "Content-Aware Fill"
        case .curves: return "Curves"
        case .exposure: return "Exposure"
        case .gradientMap: return "Gradient Map"
        case .grain: return "Grain"
        case .blackWhite: return "Black & White"
        case .colorBalance: return "Color Balance"
        }
    }
}
