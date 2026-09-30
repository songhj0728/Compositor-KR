/// Filters from the Filter menu. Each runs on the active image layer, inside the selection if
/// there is one, with a live preview and one undo step on OK.
nonisolated enum FilterKind: String, CaseIterable, Sendable {
    case gaussianBlur = "Gaussian Blur"
    case motionBlur = "Motion Blur"
    case addNoise = "Add Noise"
    case vignette = "Vignette"
    case bloomGlow = "Bloom / Glow"
    case dither = "Dither"
    case tonalContrast = "Tonal Contrast"
    case lensCorrection = "Lens Correction"
    case cameraRaw = "Camera Raw Filter"
    case removeBackground = "Remove Background"
    case contentAwareFill = "Content-Aware Fill"
    case curves = "Curves"
    case exposure = "Exposure"
    case gradientMap = "Gradient Map"
    case grain = "Grain"
    case blackWhite = "Black & White"
    case colorBalance = "Color Balance"
    var isAutomatic: Bool { self == .contentAwareFill || self == .removeBackground }
    /// Color adjustments: in the Image menu (and editable as adjustment layers), not under Filter.
    var isImageAdjustment: Bool {
        self == .curves || self == .exposure || self == .gradientMap || self == .grain
            || self == .blackWhite || self == .colorBalance
    }
}
