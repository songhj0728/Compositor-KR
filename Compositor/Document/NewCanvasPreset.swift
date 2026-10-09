import Foundation

// MARK: - Core state (platform-neutral)
//
// See AppSettings.swift for the platform-neutral / presentation split these follow: everything
// down to "Apple UI presentation layer" below uses only Foundation.

/// The kind of output a new canvas is meant for, each with its own way to size the canvas.
enum NewCanvasCategory: String, CaseIterable, Identifiable, Sendable {
    case digital, print
    var id: String { rawValue }
}

/// What a new canvas starts with: nothing (transparent), or a Background layer in white or a chosen color.
enum CanvasBackground: String, CaseIterable, Identifiable, Sendable {
    case transparent, white, custom
    var id: String { rawValue }
}

/// Everything New Canvas settles before the project is made.
struct NewCanvasSpec: Sendable {
    var width: Int
    var height: Int
    var resolution: Double
    var profile: DocumentColorProfile
    /// The Background layer's color, or nil for a transparent canvas.
    var background: PaletteColor?
}

/// Which way a canvas (or a sheet of paper) is long: landscape is wider than tall, portrait the reverse.
enum CanvasOrientation: String, CaseIterable, Identifiable, Sendable {
    case landscape, portrait
    var id: String { rawValue }
}

/// Common screen aspect ratios, each with a representative landscape-orientation pixel size.
enum DigitalAspectRatio: String, CaseIterable, Identifiable, Sendable {
    case widescreen, standard, square
    var id: String { rawValue }
    /// Width ÷ height in landscape orientation.
    var ratio: Double {
        switch self {
        case .widescreen: return 16.0 / 9.0
        case .standard: return 4.0 / 3.0
        case .square: return 1
        }
    }
    /// Width and height in lowest terms, landscape orientation.
    var terms: (width: Int, height: Int) {
        switch self {
        case .widescreen: return (16, 9)
        case .standard: return (4, 3)
        case .square: return (1, 1)
        }
    }
    /// The ratio `width` × `height` is, either way up; nil when it's none of these.
    static func matching(width: Int, height: Int) -> DigitalAspectRatio? {
        allCases.first { ratio in
            let t = ratio.terms
            return width * t.height == height * t.width || width * t.width == height * t.height
        }
    }
    /// A representative pixel size at this ratio, in landscape orientation.
    var landscapeSize: (width: Int, height: Int) {
        switch self {
        case .widescreen: return (1920, 1080)
        case .standard: return (1440, 1080)
        case .square: return (1080, 1080)
        }
    }
}

/// Where a canvas preset's size comes from; each has its own menu in the presets row.
enum CanvasPresetGroup: String, CaseIterable, Identifiable, Sendable {
    case social, device
    var id: String { rawValue }
}

/// New Canvas sizes: social formats and common screens and resolutions, in pixels, upright as the device is
/// usually held.
struct CanvasPreset: Identifiable, Hashable, Sendable {
    let title: String
    let width: Int
    let height: Int
    var id: String { title }
    /// Each group's presets, in sections the menu divides.
    static func sections(_ group: CanvasPresetGroup) -> [[CanvasPreset]] {
        switch group {
        case .social:
            return [[
                CanvasPreset(title: "Instagram Square", width: 1080, height: 1080),
                CanvasPreset(title: "Instagram Portrait", width: 1080, height: 1350),
                CanvasPreset(title: "Instagram Story", width: 1080, height: 1920),
                CanvasPreset(title: "YouTube Thumb", width: 1080, height: 608),
            ]]
        case .device:
            return [
                [
                    CanvasPreset(title: "4K", width: 3840, height: 2160),
                    CanvasPreset(title: "1440p", width: 2560, height: 1440),
                    CanvasPreset(title: "1080p", width: 1920, height: 1080),
                    CanvasPreset(title: "720p", width: 1280, height: 720),
                ],
                [
                    CanvasPreset(title: "iPhone 18 Pro", width: 1206, height: 2622),
                    CanvasPreset(title: "iPhone 18 Pro Max", width: 1320, height: 2868),
                    CanvasPreset(title: "MacBook Pro 14\"", width: 3024, height: 1964),
                    CanvasPreset(title: "MacBook Pro 16\"", width: 3456, height: 2234),
                    CanvasPreset(title: "Studio Display", width: 5120, height: 2880),
                ],
            ]
        }
    }
    static func all(_ group: CanvasPresetGroup) -> [CanvasPreset] { sections(group).flatMap { $0 } }
}

/// A width-to-height ratio as it reads best: "4:5" in lowest terms while those stay small, otherwise the long
/// side against 1, such as "1:2.17".
func aspectRatioText(width: Int, height: Int) -> String {
    guard width > 0, height > 0 else { return "" }
    func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    let divisor = gcd(width, height), w = width / divisor, h = height / divisor
    if max(w, h) <= 50 { return "\(w):\(h)" }
    let long = (Double(max(width, height)) / Double(min(width, height))).formatted(.number.precision(.fractionLength(0...2)))
    return width >= height ? "\(long):1" : "1:\(long)"
}

/// A unit paper sizes and other physical lengths are entered in.
enum LengthUnit: String, CaseIterable, Identifiable, Sendable {
    case millimeters, centimeters, inches
    var id: String { rawValue }
    /// Millimeters in one of this unit.
    var millimetersPerUnit: Double {
        switch self {
        case .millimeters: return 1
        case .centimeters: return 10
        case .inches: return 25.4
        }
    }
    func millimeters(from value: Double) -> Double { value * millimetersPerUnit }
    func value(fromMillimeters millimeters: Double) -> Double { millimeters / millimetersPerUnit }
    /// The unit's symbol, the same in every language.
    var symbol: String {
        switch self {
        case .millimeters: return "mm"
        case .centimeters: return "cm"
        case .inches: return "in"
        }
    }
}

/// A paper size for Print, upright (portrait) width × height in millimeters.
struct PaperPreset: Identifiable, Sendable {
    let id: String
    let title: LocalizedStringResource
    let width: Double
    let height: Double
    init(_ id: String, _ title: LocalizedStringResource, _ width: Double, _ height: Double) {
        self.id = id; self.title = title; self.width = width; self.height = height
    }
    init(_ title: String, _ width: Double, _ height: Double) {
        self.init(title, LocalizedStringResource(stringLiteral: title), width, height)
    }
    /// Inches, for the North American and photo sizes defined in them.
    static func inches(_ id: String, _ title: LocalizedStringResource, _ width: Double, _ height: Double) -> PaperPreset {
        PaperPreset(id, title, width * 25.4, height * 25.4)
    }

    /// Whether a sheet `width` × `height` mm is this size, either way up, to within half a millimeter.
    func matches(width w: Double, height h: Double) -> Bool {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 0.5 }
        return (near(w, width) && near(h, height)) || (near(w, height) && near(h, width))
    }

    /// The sizes most people reach for, above the menu's divider.
    static let common: [PaperPreset] = [
        PaperPreset("A4", 210, 297),
        PaperPreset("A3", 297, 420),
        PaperPreset("A5", 148, 210),
        PaperPreset("B4 (JIS)", 257, 364),
        PaperPreset("B5 (JIS)", 182, 257),
        .inches("Letter", "Letter", 8.5, 11),
        .inches("Legal", "Legal", 8.5, 14),
    ]

    /// Everything else, in headed sections below the divider.
    static let more: [(title: LocalizedStringResource, sizes: [PaperPreset])] = [
        ("ISO A", [
            PaperPreset("A0", 841, 1189), PaperPreset("A1", 594, 841), PaperPreset("A2", 420, 594),
            PaperPreset("A6", 105, 148), PaperPreset("A7", 74, 105),
        ]),
        ("ISO B", [
            PaperPreset("B0 (ISO)", 1000, 1414), PaperPreset("B1 (ISO)", 707, 1000), PaperPreset("B2 (ISO)", 500, 707),
            PaperPreset("B3 (ISO)", 353, 500), PaperPreset("B4 (ISO)", 250, 353), PaperPreset("B5 (ISO)", 176, 250),
        ]),
        ("JIS B", [
            PaperPreset("B0 (JIS)", 1030, 1456), PaperPreset("B1 (JIS)", 728, 1030), PaperPreset("B2 (JIS)", 515, 728),
            PaperPreset("B3 (JIS)", 364, 515), PaperPreset("B6 (JIS)", 128, 182),
        ]),
        ("North America", [
            .inches("Tabloid", "Tabloid", 11, 17), .inches("Executive", "Executive", 7.25, 10.5),
            .inches("Half Letter", "Half Letter", 5.5, 8.5),
        ]),
        ("Photo", [
            .inches("3.5×5 in", "3.5×5 in", 3.5, 5), .inches("4×6 in", "4×6 in", 4, 6),
            .inches("5×7 in", "5×7 in", 5, 7), .inches("8×10 in", "8×10 in", 8, 10),
        ]),
        ("Cards & Envelopes", [
            PaperPreset("businessCardKR", "Business Card (Korea)", 50, 90),
            .inches("businessCardUS", "Business Card (US)", 2, 3.5),
            PaperPreset("postcard", "Postcard", 100, 148),
            PaperPreset("envelopeDL", "Envelope DL", 110, 220),
            PaperPreset("envelopeC5", "Envelope C5", 162, 229),
            PaperPreset("envelopeC4", "Envelope C4", 229, 324),
        ]),
        ("Posters", [
            PaperPreset("poster50x70", "Poster 50×70 cm", 500, 700),
            .inches("poster18x24", "Poster 18×24 in", 18, 24),
            .inches("poster24x36", "Poster 24×36 in", 24, 36),
        ]),
    ]
    static let all: [PaperPreset] = common + more.flatMap(\.sizes)
}

// MARK: - Apple UI presentation layer
//
// Everything below maps the platform-neutral state above onto SwiftUI. A future non-Apple port
// replaces only this section, the same way AppSettings.swift's presentation extensions do.

import SwiftUI

extension NewCanvasCategory {
    var label: LocalizedStringKey {
        switch self {
        case .digital: return "Digital"
        case .print: return "Print"
        }
    }
}

extension CanvasBackground {
    var label: LocalizedStringKey {
        switch self {
        case .transparent: return "Transparent"
        case .white: return "White"
        case .custom: return "Color"
        }
    }
}

extension CanvasOrientation {
    var label: LocalizedStringKey {
        switch self {
        case .landscape: return "Landscape"
        case .portrait: return "Portrait"
        }
    }
}

extension DigitalAspectRatio {
    var label: LocalizedStringKey {
        switch self {
        case .widescreen: return "16:9"
        case .standard: return "4:3"
        case .square: return "1:1"
        }
    }
}

extension CanvasPresetGroup {
    var label: LocalizedStringKey {
        switch self {
        case .social: return "Social"
        case .device: return "Device"
        }
    }
}

extension LengthUnit {
    var label: LocalizedStringKey {
        switch self {
        case .millimeters: return "mm"
        case .centimeters: return "cm"
        case .inches: return "in"
        }
    }
}
