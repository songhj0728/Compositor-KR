import AppKit
import CoreGraphics
import os
import SwiftUI

/// A project's color space, chosen when it's made. Its pixels are numbers in `workingSpace`: new layers, fills,
/// brush strokes and imported images are made in it, and saved and exported images carry it as their profile.
/// Images that arrive in another space keep their own tag, so Core Graphics converts them wherever they're drawn.
nonisolated enum DocumentColorProfile: String, CaseIterable, Identifiable, Sendable, Codable {
    // Raw values are what project manifests store; "sRGB" is what every project before these had.
    case sRGB = "sRGB"
    case displayP3 = "Display P3"
    case adobeRGB = "Adobe RGB (1998)"
    case rec709 = "Rec. 709"
    case rec2020 = "Rec. 2020"
    case cmyk = "CMYK"
    var id: String { rawValue }

    private static let spaces: [DocumentColorProfile: CGColorSpace] = {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        func space(_ name: CFString) -> CGColorSpace { CGColorSpace(name: name) ?? srgb }
        return [.sRGB: srgb, .displayP3: space(CGColorSpace.displayP3), .adobeRGB: space(CGColorSpace.adobeRGB1998),
                .rec709: space(CGColorSpace.itur_709), .rec2020: space(CGColorSpace.itur_2020),
                // Pixels with transparency can't be CMYK in Core Graphics, so CMYK projects are edited in sRGB and
                // become CMYK on the way out (`outputSpace`).
                .cmyk: srgb]
    }()
    private static let cmykSpace = CGColorSpace(name: CGColorSpace.genericCMYK)!

    /// The RGB space the project's pixels are edited in.
    var workingSpace: CGColorSpace { Self.spaces[self]! }
    /// What an exported JPEG is converted to: CMYK for a CMYK project, the working space otherwise. PNG has no CMYK,
    /// so a CMYK project's PNGs stay in its working RGB.
    var jpegSpace: CGColorSpace { self == .cmyk ? Self.cmykSpace : workingSpace }
}

extension DocumentColorProfile {
    var displayName: LocalizedStringKey {
        switch self {
        case .sRGB: return "sRGB"
        case .displayP3: return "Display P3"
        case .adobeRGB: return "Adobe RGB (1998)"
        case .rec709: return "Rec. 709"
        case .rec2020: return "Rec. 2020"
        case .cmyk: return "CMYK"
        }
    }
    var detail: LocalizedStringKey {
        switch self {
        case .sRGB: return "The web and most screens"
        case .displayP3: return "Wide-gamut Apple displays"
        case .adobeRGB: return "Photography and print proofs"
        case .rec709: return "HD video"
        case .rec2020: return "Ultra HD and HDR video"
        case .cmyk: return "Print: edited in RGB, JPEG export converts to CMYK"
        }
    }
}

/// The space new pixels are made in: the working space of the project being edited. Buffers are made all over, on
/// and off the main thread, so they read it from here rather than each being handed the document.
nonisolated enum WorkingColorSpace {
    private static let state = OSAllocatedUnfairLock<DocumentColorProfile>(initialState: .sRGB)
    static var profile: DocumentColorProfile {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
    static var current: CGColorSpace { profile.workingSpace }
}

extension NSColor {
    /// A color from components in the project's working space, as brush colors are.
    nonisolated static func working(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
        let space = NSColorSpace(cgColorSpace: WorkingColorSpace.current) ?? .sRGB
        return NSColor(colorSpace: space, components: [red, green, blue, alpha], count: 4)
    }
}
