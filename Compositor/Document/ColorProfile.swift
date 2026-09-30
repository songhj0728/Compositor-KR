import Foundation

// MARK: - Core state (platform-neutral)
//
// Down to "Apple platform layer" below, only Foundation: which color profiles a project can have, and which one the
// front project is edited in. A future non-Apple port (e.g. Windows) reuses this section and maps each profile onto its
// own color management, the way the Apple layer below maps them onto Core Graphics color spaces.

/// A project's color space, chosen when it's made. Its pixels are numbers in the profile's working space: new layers,
/// fills, brush strokes and imported images are made in it, and saved and exported images carry it as their profile.
nonisolated enum DocumentColorProfile: String, CaseIterable, Identifiable, Sendable, Codable {
    // Raw values are what project manifests store; "sRGB" is what every project before these had.
    case sRGB = "sRGB"
    case displayP3 = "Display P3"
    case adobeRGB = "Adobe RGB (1998)"
    case rec709 = "Rec. 709"
    case rec2020 = "Rec. 2020"
    case cmyk = "CMYK"
    var id: String { rawValue }
    /// Pixels with transparency can't be CMYK, so a CMYK project is edited in sRGB and only becomes CMYK on the way
    /// out, as an exported JPEG.
    var editsInRGB: Bool { self == .cmyk }
}

/// The profile new pixels are made in: that of the project being edited. Buffers are made all over, on and off the main
/// thread, so they read it from here rather than each being handed the document.
nonisolated enum WorkingColorSpace {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = DocumentColorProfile.sRGB
    static var profile: DocumentColorProfile {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

// MARK: - Apple platform layer
//
// Everything below maps the profiles above onto Core Graphics and AppKit. A future non-Apple port replaces only this
// section.

import AppKit
import CoreGraphics
import os
import SwiftUI

extension DocumentColorProfile {
    nonisolated private static let spaces: [DocumentColorProfile: CGColorSpace] = {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        func space(_ name: CFString) -> CGColorSpace { CGColorSpace(name: name) ?? srgb }
        return [.sRGB: srgb, .displayP3: space(CGColorSpace.displayP3), .adobeRGB: space(CGColorSpace.adobeRGB1998),
                .rec709: space(CGColorSpace.itur_709), .rec2020: space(CGColorSpace.itur_2020),
                // Edited in RGB (see `editsInRGB`), made CMYK by `jpegSpace`.
                .cmyk: srgb]
    }()
    nonisolated private static let cmykSpace = CGColorSpace(name: CGColorSpace.genericCMYK)!

    /// The RGB space the project's pixels are edited in. Images that arrive in another space keep their own tag, so
    /// Core Graphics converts them wherever they're drawn.
    nonisolated var workingSpace: CGColorSpace { Self.spaces[self]! }
    /// What an exported JPEG is converted to: CMYK for a CMYK project, the working space otherwise. PNG has no CMYK,
    /// so a CMYK project's PNGs stay in its working RGB.
    nonisolated var jpegSpace: CGColorSpace { editsInRGB ? Self.cmykSpace : workingSpace }

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

extension WorkingColorSpace {
    /// The Core Graphics space of `profile`.
    nonisolated static var current: CGColorSpace { profile.workingSpace }
}

extension NSColor {
    /// A color from components in the project's working space, as brush colors are.
    nonisolated static func working(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
        let space = NSColorSpace(cgColorSpace: WorkingColorSpace.current) ?? .sRGB
        return NSColor(colorSpace: space, components: [red, green, blue, alpha], count: 4)
    }
}

extension CanvasDocument {
    /// Whether the canvas shows no transparency: its lowest visible layer is opaque pixels over the whole canvas,
    /// drawn plainly (full opacity, Normal, unmasked), as a Background layer is.
    var hasOpaqueBackground: Bool {
        guard let bottom = renderLayers.first, bottom.adjustment == nil, let image = bottom.asset?.image,
              bottom.opacity >= 1, bottom.blendMode == .normal, bottom.mask?.isEnabled != true,
              bottom.effectiveOpacity(in: Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })) >= 1 else { return false }
        let transform = bottom.transform
        let upright = transform.rotation.truncatingRemainder(dividingBy: 360) == 0
        guard upright, CGRect(origin: transform.origin, size: transform.size).contains(CGRect(origin: .zero, size: size)) else { return false }
        return OpaqueImageCheck.isOpaque(image)
    }
}

/// Whether an image's pixels are all opaque, read from a small copy and remembered for the last image asked about,
/// so the status bar can ask on every redraw.
nonisolated enum OpaqueImageCheck {
    private static let last = OSAllocatedUnfairLock<(image: CGImage, opaque: Bool)?>(uncheckedState: nil)

    static func isOpaque(_ image: CGImage) -> Bool {
        if let known = last.withLock({ $0 }), known.image === image { return known.opaque }
        let opaque = measure(image)
        last.withLock { $0 = (image, opaque) }
        return opaque
    }

    private static func measure(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return true
        default: break
        }
        let side = 64
        let width = min(side, image.width), height = min(side, image.height)
        guard let context = try? BrushRaster.context(width: width, height: height, mask: false),
              let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        context.interpolationQuality = .low
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), mask: false, context: context)
        for y in 0..<height {
            for x in 0..<width where data[y * context.bytesPerRow + x * 4 + 3] < 250 { return false }
        }
        return true
    }
}
