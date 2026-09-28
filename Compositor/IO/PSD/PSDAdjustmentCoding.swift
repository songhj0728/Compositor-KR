import CoreGraphics
import Foundation

/// Big-endian bytes for Photoshop files, as Adobe's *Photoshop File Formats Specification* lays them out.
nonisolated struct PSDWriteBuffer: Sendable {
    var data = Data()
    mutating func u8(_ value: UInt8) { data.append(value) }
    mutating func u16(_ value: UInt16) { data.append(UInt8(truncatingIfNeeded: value >> 8)); data.append(UInt8(truncatingIfNeeded: value)) }
    mutating func i16(_ value: Int16) { u16(UInt16(bitPattern: value)) }
    mutating func u32(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
    }
    mutating func i32(_ value: Int32) { u32(UInt32(bitPattern: value)) }
    mutating func f32(_ value: Float) { u32(value.bitPattern) }
    mutating func f64(_ value: Double) {
        let bits = value.bitPattern
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
    }
    mutating func bytes(_ value: Data) { data.append(value) }
    mutating func ascii(_ value: String) { data.append(contentsOf: Array(value.utf8)) }
    /// A Unicode string: a count of UTF-16 units, then the units.
    mutating func unicode(_ value: String) {
        let units = Array(value.utf16)
        u32(UInt32(units.count))
        for unit in units { u16(unit) }
    }
    /// A descriptor key or class ID: four-character codes as a zero length and the code, others with their length.
    mutating func key(_ value: String) {
        let bytes = Array(value.utf8)
        u32(bytes.count == 4 ? 0 : UInt32(bytes.count))
        data.append(contentsOf: bytes)
    }
}

/// Descriptor items (Photoshop's "Action descriptor" structure), for the adjustment blocks that use one.
nonisolated enum PSDDescriptorItem {
    case long(Int32), double(Double), bool(Bool), text(String), object(classID: String, items: [(String, PSDDescriptorItem)])

    func write(_ buffer: inout PSDWriteBuffer) {
        switch self {
        case .long(let value): buffer.ascii("long"); buffer.i32(value)
        case .double(let value): buffer.ascii("doub"); buffer.f64(value)
        case .bool(let value): buffer.ascii("bool"); buffer.u8(value ? 1 : 0)
        case .text(let value): buffer.ascii("TEXT"); buffer.unicode(value + "\0")
        case .object(let classID, let items): buffer.ascii("Objc"); Self.body(&buffer, classID: classID, items: items)
        }
    }
    /// A descriptor's name (empty), class and items.
    static func body(_ buffer: inout PSDWriteBuffer, classID: String, items: [(String, PSDDescriptorItem)]) {
        buffer.unicode("\0")
        buffer.key(classID)
        buffer.u32(UInt32(items.count))
        for (key, item) in items {
            buffer.key(key)
            item.write(&buffer)
        }
    }
    /// A descriptor as an additional-layer-info block carries it: version 16, then the descriptor.
    static func block(classID: String, items: [(String, PSDDescriptorItem)]) -> Data {
        var buffer = PSDWriteBuffer()
        buffer.u32(16)
        body(&buffer, classID: classID, items: items)
        return buffer.data
    }
}

/// Adjustment layers as Photoshop stores them: each kind's additional-layer-info key and its data.
nonisolated enum PSDAdjustmentCoding {
    /// The key and data for `adjustment`, or nil for the kinds Photoshop has no adjustment layer for (Grain, Add
    /// Noise and the blurs are filters there). `notes` gathers what doesn't carry over exactly.
    static func encode(_ adjustment: LayerAdjustment, notes: inout [String]) -> (key: String, data: Data)? {
        switch adjustment.kind {
        case .levels: return ("levl", levels(adjustment.levels))
        case .curves: return ("curv", curves(adjustment.curves, notes: &notes))
        case .hsv: return ("hue2", hue(adjustment.resolvedHSV, notes: &notes))
        case .exposure: return ("expA", exposure(adjustment.exposure))
        case .invert: return ("nvrt", Data())
        case .colorBalance: return ("blnc", colorBalance(adjustment.colorBalance))
        case .blackWhite: return ("blwh", blackWhite(adjustment.blackWhite))
        case .gradientMap: return ("grdm", gradientMap(adjustment.gradientMap))
        case .grain, .addNoise, .gaussianBlur, .motionBlur: return nil
        }
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    }

    /// Version 2, then 29 records — composite, red, green, blue, and unused others — of input black and white,
    /// output black and white, and gamma × 100.
    static func levels(_ settings: LevelsSettings) -> Data {
        var buffer = PSDWriteBuffer()
        buffer.u16(2)
        for index in 0..<29 {
            let range = index < settings.ranges.count ? settings.ranges[index].normalized : LevelRange()
            let black = clamp(range.black.rounded(), 0...253)
            let white = clamp(range.white.rounded(), (black + 2)...255)
            buffer.u16(UInt16(black))
            buffer.u16(UInt16(white))
            buffer.u16(UInt16(clamp(range.outputBlack.rounded(), 0...255)))
            buffer.u16(UInt16(clamp(range.outputWhite.rounded(), 0...255)))
            buffer.u16(UInt16(clamp((range.gamma * 100).rounded(), 10...999)))
        }
        return buffer.data
    }

    /// A padding byte, version 1, a bitmap of the curves present and each curve's points (output, input); then the
    /// `Crv ` extension Photoshop reads first, with the same curves by channel.
    static func curves(_ settings: CurvesSettings, notes: inout [String]) -> Data {
        let curves = settings.channels.prefix(4).map { points -> [CurvePoint] in
            // Photoshop's curves take at most 16 points; more are thinned out evenly, keeping both ends.
            guard points.count > 16 else { return points }
            notes.append("Curves with more than 16 points were simplified to 16.")
            return (0..<16).map { points[Int((Double($0) * Double(points.count - 1) / 15).rounded())] }
        }
        func write(_ points: [CurvePoint], _ buffer: inout PSDWriteBuffer) {
            buffer.u16(UInt16(points.count))
            for point in points {
                buffer.u16(UInt16(clamp(point.y.rounded(), 0...255)))
                buffer.u16(UInt16(clamp(point.x.rounded(), 0...255)))
            }
        }
        var buffer = PSDWriteBuffer()
        buffer.u8(0)
        buffer.u16(1)
        buffer.u32(UInt32((1 << curves.count) - 1))
        for points in curves { write(points, &buffer) }
        buffer.ascii("Crv ")
        buffer.u16(4)
        buffer.u32(UInt32(curves.count))
        for (channel, points) in curves.enumerated() {
            buffer.u16(UInt16(channel))
            write(points, &buffer)
        }
        return buffer.data
    }

    /// Version 2, Colorize, the colorize and master settings, then each color range's band and settings.
    static func hue(_ settings: HueSaturationSettings, notes: inout [String]) -> Data {
        if settings.invertRange { notes.append("Hue/Saturation's inverted range isn't in Photoshop and was saved as a normal range.") }
        func triple(_ adjustment: RangeAdjustment, hue: ClosedRange<Double>, saturation: ClosedRange<Double>,
                    _ buffer: inout PSDWriteBuffer) {
            buffer.i16(Int16(clamp(adjustment.hue.rounded(), hue)))
            buffer.i16(Int16(clamp(adjustment.saturation.rounded(), saturation)))
            buffer.i16(Int16(clamp(adjustment.lightness.rounded(), -100...100)))
        }
        let master = settings.adjustments[.master] ?? RangeAdjustment()
        var buffer = PSDWriteBuffer()
        buffer.u16(2)
        buffer.u8(settings.colorize ? 1 : 0)
        buffer.u8(0)
        // Colorize keeps its hue (0…360) and saturation (0…100) apart from the master shift.
        triple(settings.colorize ? master : RangeAdjustment(hue: 0, saturation: 25, lightness: 0),
               hue: 0...360, saturation: 0...100, &buffer)
        triple(settings.colorize ? RangeAdjustment() : master, hue: -180...180, saturation: -100...100, &buffer)
        for range in ColorRange.colorRanges {
            let band = settings.bands[range] ?? range.defaultBand
            for degrees in [band.falloffStart, band.rangeStart, band.rangeEnd, band.falloffEnd] {
                let wrapped = degrees.isFinite ? (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) : 0
                buffer.i16(Int16(wrapped.rounded()) % 360)
            }
            triple(settings.adjustments[range] ?? RangeAdjustment(), hue: -180...180, saturation: -100...100, &buffer)
        }
        return buffer.data
    }

    /// Version 1, then exposure, offset and gamma as 4-byte floats.
    static func exposure(_ settings: ExposureSettings) -> Data {
        let value = settings.normalized
        var buffer = PSDWriteBuffer()
        buffer.u16(1)
        buffer.f32(Float(value.exposure))
        buffer.f32(Float(value.offset))
        buffer.f32(Float(value.gamma))
        return buffer.data
    }

    /// Cyan–red, magenta–green and yellow–blue for shadows, midtones and highlights, then Preserve Luminosity.
    static func colorBalance(_ settings: ColorBalanceSettings) -> Data {
        var buffer = PSDWriteBuffer()
        for value in [settings.shadowCyanRed, settings.shadowMagentaGreen, settings.shadowYellowBlue,
                      settings.midCyanRed, settings.midMagentaGreen, settings.midYellowBlue,
                      settings.highlightCyanRed, settings.highlightMagentaGreen, settings.highlightYellowBlue] {
            buffer.i16(Int16(clamp(value.rounded(), -100...100)))
        }
        buffer.u8(settings.preserveLuminosity ? 1 : 0)
        return buffer.data
    }

    /// A descriptor with each color's weight (percent) and the tint.
    static func blackWhite(_ settings: BlackWhiteSettings) -> Data {
        // The tint is a color in Photoshop; this one has the hue and saturation, at Photoshop's default brightness.
        let tint = rgb(hue: settings.tintHue, saturation: settings.tintSaturation / 100, brightness: 0.88)
        func weight(_ value: Double) -> PSDDescriptorItem { .long(Int32(clamp(value.rounded(), -200...300))) }
        return PSDDescriptorItem.block(classID: "null", items: [
            ("Rd  ", weight(settings.reds)), ("Yllw", weight(settings.yellows)), ("Grn ", weight(settings.greens)),
            ("Cyn ", weight(settings.cyans)), ("Bl  ", weight(settings.blues)), ("Mgnt", weight(settings.magentas)),
            ("useTint", .bool(settings.tint)),
            ("tintColor", .object(classID: "RGBC", items: [("Rd  ", .double(tint.red * 255)), ("Grn ", .double(tint.green * 255)),
                                                           ("Bl  ", .double(tint.blue * 255))])),
            ("bwPresetKind", .long(1)),
            ("blackAndWhitePresetFileName", .text("")),
        ])
    }

    /// Photoshop 6's gradient settings: two color stops (shadows, highlights) and two opaque transparency stops.
    static func gradientMap(_ settings: GradientMapSettings) -> Data {
        let value = settings.normalized
        var buffer = PSDWriteBuffer()
        buffer.u16(1)
        buffer.u8(value.reversed ? 1 : 0)
        buffer.u8(0)
        buffer.unicode("Custom")
        buffer.u16(2)
        for (location, color) in [(UInt32(0), value.shadows), (UInt32(4096), value.highlights)] {
            buffer.u32(location)
            buffer.u32(50)
            buffer.u16(0)
            for component in [color.red, color.green, color.blue] { buffer.u16(UInt16(clamp((component * 65535).rounded(), 0...65535))) }
            buffer.u16(0)
            buffer.u16(0)
        }
        buffer.u16(2)
        for location in [UInt32(0), 4096] {
            buffer.u32(location)
            buffer.u32(50)
            buffer.u16(255)
        }
        buffer.u16(2)
        buffer.u16(4096)
        buffer.u16(32)
        buffer.u16(0)
        buffer.u32(0)
        buffer.u16(0)
        buffer.u16(0)
        buffer.u32(2048)
        buffer.u16(3)
        for _ in 0..<4 { buffer.u16(0) }
        for _ in 0..<4 { buffer.u16(0x8000) }
        buffer.u16(0)
        return buffer.data
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> (red: Double, green: Double, blue: Double) {
        let h = ((hue.isFinite ? hue : 0).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let s = clamp(saturation, 0...1), v = clamp(brightness, 0...1)
        let c = v * s, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}
