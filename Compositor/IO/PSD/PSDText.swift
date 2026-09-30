import AppKit
import CoreGraphics
import Foundation

/// Reads a Photoshop 6 type layer (`TySh`) into the editor's text model.
/// Adobe’s *Photoshop File Formats Specification* (2019), Type Tool Object Setting:
/// version, a 2×3 transform, a text descriptor, and a warp descriptor.
/// The engine dictionary inside `EngineData` supplies the font, size, color,
/// tracking, leading and alignment. Anything this model cannot represent
/// (vertical text, shear, uneven scale) stays a raster.
nonisolated enum PSDText {
    struct Source: Sendable {
        var style: LayerTextStyle
        var notes: [String]
        /// Document point that `imageAnchor` should land on.
        var documentAnchor: CGPoint
        var rotation: CGFloat
        var flipY: Bool
        /// The anchor is the paragraph frame's top-left. Otherwise it is the point-text baseline.
        var anchorIsFrame: Bool
    }

    static let rasterizedNote = "Editable Photoshop text becomes pixels and can’t be retyped."
    static let firstStyleNote = "Only the first text style was kept."
    static let warpNote = "The Photoshop text warp was omitted."
    static let fauxNote = "Faux bold or faux italic was omitted."
    static let justifyNote = "Full justification was imported as left alignment."

    static func missingFontNote(_ name: String) -> String? {
        guard NSFont(name: name, size: 12) == nil else { return nil }
        return "The font “\(name)” isn’t installed, so the text was drawn with the system font."
    }

    static func parse(extra: [String: Data]) -> Source? {
        guard let data = extra["TySh"] ?? extra["tySh"], data.count <= 8_000_000 else { return nil }
        var reader = Reader(data: data)
        guard reader.u16() == 1 else { return nil }
        guard let xx = reader.f64(), let xy = reader.f64(), let yx = reader.f64(),
              let yy = reader.f64(), let tx = reader.f64(), let ty = reader.f64(),
              [xx, xy, yx, yy, tx, ty].allSatisfy(\.isFinite) else { return nil }
        guard reader.u16() == 50, let text = reader.descriptor(versioned: true) else { return nil }
        if let orientation = text.enumeration("Ornt"), orientation == "Vrtc" { return nil }
        // Adobe's matrix is row-vector style — x' = xx·x + yx·y + tx, y' = xy·x + yy·y + ty — where `placement` takes
        // (xx, xy) as its first row, so the two off-diagonal terms trade places.
        guard let placed = placement(xx: xx, xy: yx, yx: xy, yy: yy, tx: tx, ty: ty) else { return nil }

        var notes: [String] = []
        if reader.remaining >= 2, reader.u16() == 1, let warp = reader.descriptor(versioned: true),
           let style = warp.enumeration("warpStyle"), style != "warpNone", style != "none" {
            notes.append(warpNote)
        }

        let engine = text.data("EngineData").flatMap(engineValue)
        let content = cleaned(text.string("Txt ") ?? text.string("Txt"))
            ?? engine.flatMap { cleaned(string(walk($0, "EngineDict", "Editor", "Text"))) }
        guard let content, !content.isEmpty, content.utf16.count <= 100_000 else { return nil }

        var style = LayerTextStyle()
        style.content = content
        if let engine {
            applyStyle(&style, engine: engine, pixelScale: placed.pixelScale, notes: &notes)
        } else {
            style.fontSize = CGFloat(min(2000, max(1, 12 * placed.pixelScale)))
        }
        guard style.fontSize.isFinite, style.fontSize > 0 else { return nil }

        var anchor = CGPoint(x: placed.tx, y: placed.ty)
        var anchorIsFrame = false
        if let bounds = text.rect("bounds"), let glyphs = text.rect("boundingBox"),
           bounds.width > glyphs.width + 4, bounds.height > glyphs.height + 4,
           bounds.width > 1, bounds.height > 1 {
            let frame = CGSize(width: bounds.width * placed.pixelScale, height: bounds.height * placed.pixelScale)
            let pad = LayerTextStyle.padding
            var boxed = style
            boxed.boxSize = CGSize(width: frame.width + pad * 2, height: frame.height + pad * 2)
            // A paragraph frame the model cannot store is dropped entirely: importing as point
            // text would lose the wrap without saying so. Vertical text already falls back the same way.
            guard boxed.isValid else { return nil }
            style = boxed
            anchor = placed.map(CGPoint(x: bounds.minX, y: bounds.minY))
            anchorIsFrame = true
        }
        guard style.isValid else { return nil }
        return Source(style: style, notes: notes, documentAnchor: anchor, rotation: placed.rotation,
                      flipY: placed.flipY, anchorIsFrame: anchorIsFrame)
    }

    @MainActor
    static func render(_ source: Source) throws -> (image: CGImage, transform: LayerTransform) {
        let image = try EditorSession.textImage(source.style)
        let size = CGSize(width: image.width, height: image.height)
        let anchor = source.anchorIsFrame
            ? CGPoint(x: LayerTextStyle.padding, y: LayerTextStyle.padding)
            : CGPoint(x: horizontalAnchor(source.style, width: size.width), y: baseline(source.style, image: size))
        let transform = layerTransform(image: size, imageAnchor: anchor, documentAnchor: source.documentAnchor,
                                       rotation: source.rotation, flipY: source.flipY)
        guard transform.isValid else { throw ProjectError.tooLarge }
        return (image, transform)
    }

    private struct Placement {
        var pixelScale: Double
        var rotation: CGFloat
        var flipY: Bool
        var tx: Double
        var ty: Double
        var map: (CGPoint) -> CGPoint
    }

    /// Uniform scale, rotation and an optional vertical flip. Shear and uneven scale return nil.
    /// Engine sizes are already in text-space units that the matrix maps into document pixels;
    /// document PPI is print metadata and must not multiply that product again.
    private static func placement(xx: Double, xy: Double, yx: Double, yy: Double, tx: Double, ty: Double) -> Placement? {
        let scaleX = hypot(xx, yx)
        guard scaleX > 1e-6 else { return nil }
        let cosR = xx / scaleX
        let sinR = yx / scaleX
        let localX = cosR * xy + sinR * yy
        let localY = -sinR * xy + cosR * yy
        let scaleY = abs(localY)
        guard scaleY > 1e-6 else { return nil }
        let largest = max(scaleX, scaleY)
        guard abs(localX) <= 0.02 * largest, abs(scaleX - scaleY) <= 0.02 * largest else { return nil }
        let pixelScale = scaleX
        guard pixelScale.isFinite, pixelScale > 0 else { return nil }
        let ySign = localY < 0 ? -1.0 : 1.0
        let exx = cosR * pixelScale
        let eyx = sinR * pixelScale
        let exy = -sinR * pixelScale * ySign
        let eyy = cosR * pixelScale * ySign
        return Placement(pixelScale: pixelScale, rotation: CGFloat(atan2(sinR, cosR) * 180 / .pi), flipY: localY < 0, tx: tx, ty: ty) { point in
            CGPoint(x: exx * point.x + exy * point.y + tx, y: eyx * point.x + eyy * point.y + ty)
        }
    }

    private static func applyStyle(_ style: inout LayerTextStyle, engine: Engine, pixelScale: Double, notes: inout [String]) {
        let runs = array(walk(engine, "EngineDict", "StyleRun", "RunArray"))
        let first = runs.first ?? engine
        let sheet = walk(first, "StyleSheet", "StyleSheetData") ?? walk(engine, "EngineDict", "StyleRun", "RunArray")
        let data = sheet ?? first
        let points = number(walk(data, "FontSize")) ?? 12
        guard points.isFinite, points > 0 else { return }
        style.fontSize = CGFloat(min(2000, max(1, points * pixelScale)))
        let fonts = array(walk(engine, "ResourceDict", "FontSet"))
        let index = Int((number(walk(data, "Font")) ?? 0).rounded())
        if fonts.indices.contains(index), let name = string(walk(fonts[index], "Name")), !name.isEmpty {
            style.fontName = name
        }
        let values = array(walk(data, "FillColor", "Values"))
        if !values.isEmpty {
            let channels = values.compactMap { number($0) }
            let rgb = color(channels)
            style.red = rgb.0
            style.green = rgb.1
            style.blue = rgb.2
        }
        let tracking = number(walk(data, "Tracking")) ?? 0
        if tracking.isFinite {
            style.tracking = CGFloat(min(1000, max(-100, tracking * Double(style.fontSize) / 1000)))
        }
        let auto = bool(walk(data, "AutoLeading")) ?? true
        if !auto, let leading = number(walk(data, "Leading")), leading.isFinite, leading > 0 {
            style.leading = CGFloat(min(5000, max(0, leading * pixelScale)))
        }
        if bool(walk(data, "FauxBold")) == true || bool(walk(data, "FauxItalic")) == true {
            notes.append(fauxNote)
        }
        // Letters in other faces and colors keep them; a run that differs in anything else (size, leading, scale)
        // takes the first run's, and says so.
        if runs.count > 1 {
            let lengths = array(walk(engine, "EngineDict", "StyleRun", "RunLengthArray")).compactMap { number($0) }
            if lengths.count == runs.count {
                var location = 0
                for (run, length) in zip(runs, lengths) {
                    let count = max(0, Int(length.rounded()))
                    let range = NSRange(location: location, length: min(count, max(0, style.content.utf16.count - location)))
                    location += count
                    guard range.length > 0 else { continue }
                    let runData = walk(run, "StyleSheet", "StyleSheetData") ?? run
                    let face = Int((number(walk(runData, "Font")) ?? 0).rounded())
                    if fonts.indices.contains(face), let name = string(walk(fonts[face], "Name")), !name.isEmpty, name != style.fontName(at: range.location) {
                        style.setFont(name, in: range)
                    }
                    let channels = array(walk(runData, "FillColor", "Values")).compactMap { number($0) }
                    if !channels.isEmpty {
                        let rgb = color(channels)
                        let runColor = PaletteColor(red: rgb.0, green: rgb.1, blue: rgb.2)
                        if runColor != style.color(at: range.location) { style.setColor(runColor, in: range) }
                    }
                }
            }
            if runs.dropFirst().contains(where: { signature($0) != signature(first) }) {
                notes.append(firstStyleNote)
            }
        }
        let paragraphs = array(walk(engine, "EngineDict", "ParagraphRun", "RunArray"))
        let justification = number(walk(paragraphs.first ?? engine, "ParagraphSheet", "Properties", "Justification"))
        switch Int((justification ?? 0).rounded()) {
        case 1: style.alignment = .right
        case 2: style.alignment = .center
        case 0: style.alignment = .left
        default:
            style.alignment = .left
            notes.append(justifyNote)
        }
    }

    private struct Signature: Equatable {
        var font = 0.0
        var size = 0.0
        var tracking = 0.0
        var leading = 0.0
        var autoLeading = true
        var horizontalScale = 1.0
        var verticalScale = 1.0
        var bold = false
        var italic = false
        var red = 0.0
        var green = 0.0
        var blue = 0.0
    }

    private static func signature(_ run: Engine) -> Signature {
        let data = walk(run, "StyleSheet", "StyleSheetData") ?? run
        var sign = Signature()
        sign.font = number(walk(data, "Font")) ?? 0
        sign.size = number(walk(data, "FontSize")) ?? 0
        sign.tracking = number(walk(data, "Tracking")) ?? 0
        sign.autoLeading = bool(walk(data, "AutoLeading")) ?? true
        sign.leading = number(walk(data, "Leading")) ?? 0
        sign.horizontalScale = number(walk(data, "HorizontalScale")) ?? 1
        sign.verticalScale = number(walk(data, "VerticalScale")) ?? 1
        sign.bold = bool(walk(data, "FauxBold")) ?? false
        sign.italic = bool(walk(data, "FauxItalic")) ?? false
        // Face and color are kept letter by letter, so they don't count as a difference.
        sign.font = 0
        return sign
    }

    private static func color(_ values: [Double]) -> (CGFloat, CGFloat, CGFloat) {
        func unit(_ value: Double) -> CGFloat {
            CGFloat(value > 1 ? min(255, max(0, value)) / 255 : min(1, max(0, value)))
        }
        if values.count >= 4 { return (unit(values[1]), unit(values[2]), unit(values[3])) }
        if values.count == 3 { return (unit(values[0]), unit(values[1]), unit(values[2])) }
        if let gray = values.first { let g = unit(gray); return (g, g, g) }
        return (0, 0, 0)
    }

    static func horizontalAnchor(_ style: LayerTextStyle, width: CGFloat) -> CGFloat {
        switch style.alignment {
        case .left: LayerTextStyle.padding
        case .center: width / 2
        case .right: width - LayerTextStyle.padding
        }
    }

    static func baseline(_ style: LayerTextStyle, image: CGSize) -> CGFloat {
        let padding = LayerTextStyle.padding
        let sample = style.content.isEmpty ? " " : style.content
        let storage = NSTextStorage(attributedString: NSAttributedString(string: sample, attributes: EditorSession.textAttributes(style)))
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, image.width - 2 * padding), height: max(1, image.height - 2 * padding)))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let glyphs = layout.glyphRange(for: container)
        guard glyphs.length > 0 else { return padding + style.fontSize * 0.8 }
        let fragment = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let location = layout.location(forGlyphAt: glyphs.location)
        return padding + fragment.minY + location.y
    }

    /// Matches `BrushRaster.pixelToDocument`: flip, then clockwise rotation about the center.
    private static func layerTransform(image: CGSize, imageAnchor: CGPoint, documentAnchor: CGPoint, rotation: CGFloat, flipY: Bool) -> LayerTransform {
        var local = CGPoint(x: imageAnchor.x - image.width / 2, y: imageAnchor.y - image.height / 2)
        if flipY { local.y = -local.y }
        let radians = rotation * .pi / 180
        let rotated = CGPoint(x: local.x * cos(radians) - local.y * sin(radians),
                              y: local.x * sin(radians) + local.y * cos(radians))
        let center = CGPoint(x: documentAnchor.x - rotated.x, y: documentAnchor.y - rotated.y)
        return LayerTransform(origin: CGPoint(x: center.x - image.width / 2, y: center.y - image.height / 2),
                              size: image, rotation: rotation, flipY: flipY)
    }

    private static func cleaned(_ text: String?) -> String? {
        guard var text else { return nil }
        while text.first == "\u{feff}" || text.first == "\0" { text.removeFirst() }
        while text.last == "\0" { text.removeLast() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return text
    }
}

private nonisolated enum Engine {
    case number(Double)
    case bool(Bool)
    case string(String)
    case dict([String: Engine])
    case array([Engine])
}

private nonisolated func walk(_ value: Engine?, _ keys: String...) -> Engine? {
    var current = value
    for key in keys {
        guard case .dict(let items) = current, let next = items[key] else { return nil }
        current = next
    }
    return current
}

private nonisolated func number(_ value: Engine?) -> Double? {
    if case .number(let number) = value { return number }
    return nil
}

private nonisolated func bool(_ value: Engine?) -> Bool? {
    if case .bool(let flag) = value { return flag }
    return nil
}

private nonisolated func string(_ value: Engine?) -> String? {
    if case .string(let text) = value { return text }
    return nil
}

private nonisolated func array(_ value: Engine?) -> [Engine] {
    if case .array(let items) = value { return items }
    return []
}

/// Photoshop's text-engine dictionary: a small PostScript-like subset (`<< >>`, arrays, names, numbers, strings).
private nonisolated func engineValue(_ data: Data) -> Engine? {
    if let dict = dictionary(in: data, at: 0) { return dict }
    guard let start = data.firstRange(of: Data("<<".utf8))?.lowerBound, start > 0 else { return nil }
    return dictionary(in: data, at: start)
}

private nonisolated func dictionary(in data: Data, at start: Int) -> Engine? {
    var cursor = EngineCursor(data: data)
    cursor.index = start
    guard case .dict(let items) = cursor.parseValue() else { return nil }
    return .dict(items)
}

private nonisolated struct EngineCursor {
    let bytes: [UInt8]
    var index = 0

    init(data: Data) { bytes = [UInt8](data) }

    mutating func parseValue() -> Engine? {
        skipWhitespace()
        guard let byte = peek else { return nil }
        if byte == UInt8(ascii: "<") {
            if peek(ahead: 1) == UInt8(ascii: "<") { return parseDictionary() }
            return parseHex()
        }
        if byte == UInt8(ascii: "[") { return parseArray() }
        if byte == UInt8(ascii: "(") { return parseString() }
        if byte == UInt8(ascii: "/") {
            index += 1
            return .string(readToken())
        }
        if byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") || byte == UInt8(ascii: ".") || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) {
            return parseNumber().map(Engine.number)
        }
        if takeWord("true") { return .bool(true) }
        if takeWord("false") { return .bool(false) }
        if takeWord("null") { return .string("") }
        return nil
    }

    mutating func parseDictionary() -> Engine? {
        guard take("<<") else { return nil }
        var items: [String: Engine] = [:]
        while true {
            skipWhitespace()
            if peek == nil || peek == UInt8(ascii: ">") { break }
            guard peek == UInt8(ascii: "/") else { return nil }
            index += 1
            let key = readToken()
            guard let value = parseValue() else { return nil }
            items[key] = value
        }
        guard take(">>") else { return nil }
        return .dict(items)
    }

    mutating func parseArray() -> Engine? {
        guard take("[") else { return nil }
        var items: [Engine] = []
        while true {
            skipWhitespace()
            if peek == nil || peek == UInt8(ascii: "]") { break }
            guard let value = parseValue() else { return nil }
            items.append(value)
        }
        guard take("]") else { return nil }
        return .array(items)
    }

    mutating func parseNumber() -> Double? {
        let start = index
        if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { index += 1 }
        while let byte = peek, byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { index += 1 }
        if peek == UInt8(ascii: ".") {
            index += 1
            while let byte = peek, byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { index += 1 }
        }
        if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
            index += 1
            if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { index += 1 }
            while let byte = peek, byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { index += 1 }
        }
        guard index > start, let text = String(bytes: bytes[start..<index], encoding: .ascii) else { return nil }
        return Double(text)
    }

    mutating func parseString() -> Engine? {
        guard take("(") else { return nil }
        var raw: [UInt8] = []
        while let byte = peek {
            index += 1
            if byte == UInt8(ascii: ")") { break }
            if byte == UInt8(ascii: "\\") {
                guard let escaped = peek else { return nil }
                index += 1
                if escaped == UInt8(ascii: "n") { raw.append(0x0A) }
                else if escaped == UInt8(ascii: "r") { raw.append(0x0D) }
                else if escaped == UInt8(ascii: "t") { raw.append(0x09) }
                else if escaped >= UInt8(ascii: "0") && escaped <= UInt8(ascii: "7") {
                    var value = Int(escaped - UInt8(ascii: "0"))
                    for _ in 0..<2 {
                        guard let digit = peek, digit >= UInt8(ascii: "0"), digit <= UInt8(ascii: "7") else { break }
                        index += 1
                        value = value * 8 + Int(digit - UInt8(ascii: "0"))
                    }
                    raw.append(UInt8(value & 0xFF))
                } else if escaped != UInt8(ascii: "\n") && escaped != UInt8(ascii: "\r") {
                    raw.append(escaped)
                }
            } else {
                raw.append(byte)
            }
        }
        return .string(decodeEngine(raw))
    }

    mutating func parseHex() -> Engine? {
        guard take("<") else { return nil }
        var nibbles: [UInt8] = []
        while let byte = peek, byte != UInt8(ascii: ">") {
            index += 1
            guard let nibble = hex(byte) else { continue }
            nibbles.append(nibble)
        }
        guard take(">") else { return nil }
        var raw: [UInt8] = []
        var i = 0
        while i + 1 < nibbles.count {
            raw.append(nibbles[i] << 4 | nibbles[i + 1])
            i += 2
        }
        return .string(decodeEngine(raw))
    }

    func decodeEngine(_ raw: [UInt8]) -> String {
        if raw.count >= 2, raw[0] == 0xFE, raw[1] == 0xFF {
            return String(data: Data(raw.dropFirst(2)), encoding: .utf16BigEndian) ?? ""
        }
        return String(bytes: raw, encoding: .isoLatin1) ?? ""
    }

    func hex(_ byte: UInt8) -> UInt8? {
        if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { return byte - UInt8(ascii: "0") }
        if byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "f") { return byte - UInt8(ascii: "a") + 10 }
        if byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "F") { return byte - UInt8(ascii: "A") + 10 }
        return nil
    }

    mutating func readToken() -> String {
        let start = index
        while let byte = peek, !isDelimiter(byte) { index += 1 }
        return String(bytes: bytes[start..<index], encoding: .ascii) ?? ""
    }

    func isDelimiter(_ byte: UInt8) -> Bool {
        byte <= 0x20 || byte == UInt8(ascii: "/") || byte == UInt8(ascii: "<") || byte == UInt8(ascii: ">")
            || byte == UInt8(ascii: "[") || byte == UInt8(ascii: "]") || byte == UInt8(ascii: "(") || byte == UInt8(ascii: ")")
    }

    mutating func takeWord(_ word: String) -> Bool {
        let encoded = Array(word.utf8)
        guard index + encoded.count <= bytes.count, Array(bytes[index..<index + encoded.count]) == encoded else { return false }
        let after = index + encoded.count
        if after < bytes.count, !isDelimiter(bytes[after]) { return false }
        index = after
        return true
    }

    mutating func take(_ token: String) -> Bool {
        let encoded = Array(token.utf8)
        guard index + encoded.count <= bytes.count, Array(bytes[index..<index + encoded.count]) == encoded else { return false }
        index += encoded.count
        return true
    }

    @discardableResult
    mutating func skipWhitespace() -> Bool {
        while let byte = peek, byte <= 0x20 || byte == UInt8(ascii: "%") {
            if byte == UInt8(ascii: "%") {
                while let next = peek, next != UInt8(ascii: "\n") && next != UInt8(ascii: "\r") { index += 1 }
            } else {
                index += 1
            }
        }
        return index <= bytes.count
    }

    var peek: UInt8? { index < bytes.count ? bytes[index] : nil }
    func peek(ahead: Int) -> UInt8? {
        let at = index + ahead
        return at < bytes.count ? bytes[at] : nil
    }
}

private nonisolated enum DescriptorValue {
    case text(String)
    case number(Double)
    case enumeration(String)
    case data(Data)
    case descriptor([String: DescriptorValue])
    case list([DescriptorValue])
}

private nonisolated extension Dictionary where Key == String, Value == DescriptorValue {
    func string(_ key: String) -> String? {
        if case .text(let text) = self[key] { return text }
        return nil
    }
    func enumeration(_ key: String) -> String? {
        if case .enumeration(let value) = self[key] { return value }
        return nil
    }
    func data(_ key: String) -> Data? {
        if case .data(let data) = self[key] { return data }
        return nil
    }
    func rect(_ key: String) -> CGRect? {
        guard case .descriptor(let items) = self[key] else { return nil }
        func side(_ name: String) -> Double? {
            if case .number(let value) = items[name] ?? items[name.trimmingCharacters(in: .whitespaces)] { return value }
            return nil
        }
        guard let left = side("Left"), let top = side("Top "), let right = side("Rght"), let bottom = side("Btom"),
              [left, top, right, bottom].allSatisfy(\.isFinite) else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

/// Descriptor walker from the same specification (class and keys are length-prefixed, or 4 bytes when the length is 0).
private nonisolated struct Reader {
    let data: Data
    var offset = 0
    var remaining: Int { data.count - offset }

    mutating func descriptor(versioned: Bool) -> [String: DescriptorValue]? {
        if versioned, u32() != 16 { return nil }
        guard unicode() != nil, identifier() != nil, let count = u32(), count <= 10_000 else { return nil }
        var items: [String: DescriptorValue] = [:]
        for _ in 0..<Int(count) {
            guard let key = identifier(), let type = fourCC(), let value = value(type) else { return nil }
            items[key] = value
        }
        return items
    }

    mutating func value(_ type: String) -> DescriptorValue? {
        switch type {
        case "doub":
            guard let number = f64() else { return nil }
            return .number(number)
        case "UntF":
            guard fourCC() != nil, let number = f64() else { return nil }
            return .number(number)
        case "long":
            guard let number = i32() else { return nil }
            return .number(Double(number))
        case "comp":
            guard let raw = bytes(8) else { return nil }
            let bits = raw.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            return .number(Double(Int64(bitPattern: bits)))
        case "bool":
            guard let flag = u8() else { return nil }
            return .number(flag == 0 ? 0 : 1)
        case "TEXT":
            guard let text = unicode() else { return nil }
            return .text(text)
        case "enum":
            guard identifier() != nil, let name = identifier() else { return nil }
            return .enumeration(name)
        case "tdta":
            guard let length = u32(), length <= 8_000_000, let raw = bytes(Int(length)) else { return nil }
            return .data(raw)
        case "Objc", "GlbO":
            guard let nested = descriptor(versioned: false) else { return nil }
            return .descriptor(nested)
        case "VlLs":
            guard let count = u32(), count <= 10_000 else { return nil }
            var items: [DescriptorValue] = []
            for _ in 0..<Int(count) {
                guard let itemType = fourCC(), let item = value(itemType) else { return nil }
                items.append(item)
            }
            return .list(items)
        case "alis":
            guard let length = u32(), length <= 8_000_000, bytes(Int(length)) != nil else { return nil }
            return .number(0)
        case "obj ":
            return reference() ? .number(0) : nil
        case "type", "GlbC":
            guard unicode() != nil, identifier() != nil else { return nil }
            return .number(0)
        default:
            return nil
        }
    }

    /// Skips a descriptor reference so a later `EngineData` item can still be read.
    mutating func reference() -> Bool {
        guard let count = u32(), count <= 10_000 else { return false }
        for _ in 0..<Int(count) {
            guard let form = fourCC() else { return false }
            switch form {
            case "prop":
                guard unicode() != nil, identifier() != nil, identifier() != nil else { return false }
            case "Clss":
                guard unicode() != nil, identifier() != nil else { return false }
            case "Enmr":
                guard unicode() != nil, identifier() != nil, identifier() != nil, identifier() != nil else { return false }
            case "rele":
                guard unicode() != nil, identifier() != nil, i32() != nil else { return false }
            case "Idnt", "indx":
                guard i32() != nil else { return false }
            case "name":
                guard unicode() != nil else { return false }
            default:
                return false
            }
        }
        return true
    }

    mutating func unicode() -> String? {
        guard let count = u32(), count <= 1_000_000, let raw = bytes(Int(count) * 2) else { return nil }
        if raw.isEmpty { return "" }
        return String(data: raw, encoding: .utf16BigEndian)
    }

    mutating func identifier() -> String? {
        guard let length = u32() else { return nil }
        if length == 0 { return fourCC() }
        guard length <= 10_000, let raw = bytes(Int(length)) else { return nil }
        return String(bytes: raw, encoding: .ascii)
    }

    mutating func fourCC() -> String? {
        guard let raw = bytes(4) else { return nil }
        return String(bytes: raw, encoding: .ascii)
    }

    mutating func bytes(_ count: Int) -> Data? {
        guard count >= 0, offset + count <= data.count else { return nil }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        return slice
    }

    mutating func u8() -> UInt8? {
        guard offset < data.count else { return nil }
        let value = data[offset]
        offset += 1
        return value
    }

    mutating func u16() -> UInt16? {
        guard let raw = bytes(2) else { return nil }
        return UInt16(raw[0]) << 8 | UInt16(raw[1])
    }

    mutating func u32() -> UInt32? {
        guard let raw = bytes(4) else { return nil }
        return raw.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func i32() -> Int32? {
        guard let value = u32() else { return nil }
        return Int32(bitPattern: value)
    }

    mutating func f64() -> Double? {
        guard let raw = bytes(8) else { return nil }
        return Double(bitPattern: raw.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
    }
}

/// Photoshop's Layer Style (`lfx2`) read back into Compositor's effects, from the same descriptors `PSDLayerStyle`
/// writes. Styles it has no form for (a Gradient Overlay, a Pattern Overlay from Photoshop's library) are left out.
nonisolated extension PSDText {
    static func layerStyle(_ data: Data) -> LayerEffects? {
        guard data.count <= 8_000_000 else { return nil }
        var reader = Reader(data: data)
        guard reader.u32() == 0, let root = reader.descriptor(versioned: true) else { return nil }
        if case .number(let on) = root["masterFXSwitch"], on == 0 { return nil }
        /// The first of a kind: newer Photoshop lists several of one style under a `…Multi` key.
        func style(_ key: String, _ multi: String) -> [String: DescriptorValue]? {
            if case .descriptor(let items) = root[key] { return items }
            if case .list(let list) = root[multi], case .descriptor(let items)? = list.first { return items }
            return nil
        }
        func number(_ items: [String: DescriptorValue], _ key: String) -> Double? {
            if case .number(let value) = items[key], value.isFinite { return value }
            return nil
        }
        func pixels(_ items: [String: DescriptorValue], _ key: String, _ range: ClosedRange<Double>, _ fallback: Double) -> CGFloat {
            CGFloat(min(range.upperBound, max(range.lowerBound, number(items, key) ?? fallback)))
        }
        func opacity(_ items: [String: DescriptorValue], _ key: String = "Opct") -> Double {
            min(1, max(0, (number(items, key) ?? 100) / 100))
        }
        func color(_ items: [String: DescriptorValue], _ key: String = "Clr ") -> PaletteColor? {
            guard case .descriptor(let rgb) = items[key], let red = number(rgb, "Rd  "), let green = number(rgb, "Grn "),
                  let blue = number(rgb, "Bl  ") else { return nil }
            func unit(_ value: Double) -> CGFloat { CGFloat(min(255, max(0, value)) / 255) }
            return PaletteColor(red: unit(red), green: unit(green), blue: unit(blue))
        }
        func mode(_ items: [String: DescriptorValue], _ key: String = "Md  ") -> LayerBlendMode? {
            guard case .enumeration(let value) = items[key] else { return nil }
            return LayerBlendMode.allCases.first { PSDLayerStyle.descriptorKey($0) == value }
        }
        func enabled(_ items: [String: DescriptorValue]) -> Bool? { number(items, "enab").map { $0 == 0 ? false : nil } ?? nil }
        func contour(_ items: [String: DescriptorValue], _ key: String) -> EffectContour? {
            guard case .descriptor(let shape) = items[key], case .text(let name)? = shape["Nm  "] else { return nil }
            let cleaned = name.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            return EffectContour.allCases.first { $0.rawValue == cleaned }
        }
        func enumeration(_ items: [String: DescriptorValue], _ key: String) -> String? {
            if case .enumeration(let value) = items[key] { return value }
            return nil
        }
        var effects = LayerEffects()
        if let items = style("DrSh", "dropShadowMulti") {
            var effect = ShadowEffect()
            effect.enabled = enabled(items)
            effect.angle = pixels(items, "lagl", -360...360, 120)
            effect.distance = pixels(items, "Dstn", 0...5000, 5)
            effect.blur = pixels(items, "blur", 0...500, 5)
            effect.opacity = opacity(items)
            if let spread = number(items, "Ckmt"), spread > 0 { effect.spread = CGFloat(min(100, spread)) }
            if let value = color(items) { effect.red = value.red; effect.green = value.green; effect.blue = value.blue }
            effect.blendMode = mode(items)
            effect.contour = contour(items, "TrnS").flatMap { $0 == .linear ? nil : $0 }
            effects.shadow = effect
        }
        if let items = style("IrSh", "innerShadowMulti") {
            var effect = InnerShadowEffect()
            effect.enabled = enabled(items)
            effect.angle = pixels(items, "lagl", -360...360, 120)
            effect.distance = pixels(items, "Dstn", 0...5000, 5)
            effect.blur = pixels(items, "blur", 0...500, 5)
            effect.opacity = opacity(items)
            if let choke = number(items, "Ckmt"), choke > 0 { effect.choke = CGFloat(min(100, choke)) }
            if let value = color(items) { effect.red = value.red; effect.green = value.green; effect.blue = value.blue }
            effect.blendMode = mode(items)
            effect.contour = contour(items, "TrnS").flatMap { $0 == .linear ? nil : $0 }
            effects.innerShadow = effect
        }
        if let items = style("OrGl", "outerGlowMulti") {
            var effect = OuterGlowEffect()
            effect.enabled = enabled(items)
            effect.size = pixels(items, "blur", 0...500, 5)
            effect.opacity = opacity(items)
            if let spread = number(items, "Ckmt"), spread > 0 { effect.spread = CGFloat(min(100, spread)) }
            if let value = color(items) { effect.red = value.red; effect.green = value.green; effect.blue = value.blue }
            effect.blendMode = mode(items)
            effect.contour = contour(items, "TrnS").flatMap { $0 == .linear ? nil : $0 }
            effects.outerGlow = effect
        }
        if let items = style("IrGl", "innerGlowMulti") {
            var effect = InnerGlowEffect()
            effect.enabled = enabled(items)
            effect.size = pixels(items, "blur", 0...500, 5)
            effect.opacity = opacity(items)
            if let choke = number(items, "Ckmt"), choke > 0 { effect.choke = CGFloat(min(100, choke)) }
            if let value = color(items) { effect.red = value.red; effect.green = value.green; effect.blue = value.blue }
            effect.blendMode = mode(items)
            effect.contour = contour(items, "TrnS").flatMap { $0 == .linear ? nil : $0 }
            if enumeration(items, "glwS") == "SrcC" { effect.fromCenter = true }
            effects.innerGlow = effect
        }
        if let items = style("ebbl", "bevelEmbossMulti") {
            var effect = BevelEffect()
            effect.enabled = enabled(items)
            switch enumeration(items, "bvlS") {
            case "OtrB": effect.style = .outerBevel
            case "Embs": effect.style = .emboss
            case "PlEb": effect.style = .pillowEmboss
            default: effect.style = .innerBevel
            }
            switch enumeration(items, "bvlT") {
            case "PrBL": effect.technique = .chiselHard
            case "Slmt": effect.technique = .chiselSoft
            default: effect.technique = .smooth
            }
            effect.depth = pixels(items, "srgR", 1...1000, 100)
            effect.up = enumeration(items, "bvlD") != "Out "
            effect.size = pixels(items, "blur", 0...250, 5)
            effect.soften = pixels(items, "Sftn", 0...16, 0)
            effect.angle = pixels(items, "lagl", -360...360, 120)
            effect.altitude = pixels(items, "Lald", 0...90, 30)
            effect.gloss = contour(items, "TrnS") ?? .linear
            effect.highlightMode = mode(items, "hglM") ?? .screen
            effect.shadowMode = mode(items, "sdwM") ?? .multiply
            effect.highlightOpacity = opacity(items, "hglO")
            effect.shadowOpacity = opacity(items, "sdwO")
            if let value = color(items, "hglC") { effect.highlightRed = value.red; effect.highlightGreen = value.green; effect.highlightBlue = value.blue }
            if let value = color(items, "sdwC") { effect.shadowRed = value.red; effect.shadowGreen = value.green; effect.shadowBlue = value.blue }
            if number(items, "useShape") == 1 {
                effect.usesContour = true
                effect.contour = contour(items, "MpgS") ?? .halfRound
                effect.contourRange = pixels(items, "Inpr", 1...100, 50)
            }
            effects.bevel = effect
        }
        if let items = style("ChFX", "satinMulti") {
            var effect = SatinEffect()
            effect.enabled = enabled(items)
            effect.opacity = opacity(items)
            effect.angle = pixels(items, "lagl", -360...360, 19)
            effect.distance = pixels(items, "Dstn", 1...250, 11)
            effect.size = pixels(items, "blur", 0...250, 14)
            effect.invert = number(items, "Invr").map { $0 != 0 } ?? true
            if let value = color(items) { effect.red = value.red; effect.green = value.green; effect.blue = value.blue }
            effect.blendMode = mode(items) ?? .multiply
            effect.contour = contour(items, "MpgS") ?? .gaussian
            effects.satin = effect
        }
        if let items = style("SoFi", "solidFillMulti") {
            var effect = ColorOverlayEffect()
            effect.enabled = enabled(items)
            effect.opacity = opacity(items)
            if let value = color(items) { effect.red = value.red; effect.green = value.green; effect.blue = value.blue }
            effect.blendMode = mode(items)
            effects.colorOverlay = effect
        }
        if let items = style("FrFX", "frameFXMulti") {
            var effect = StrokeEffect()
            effect.enabled = enabled(items)
            effect.size = pixels(items, "Sz  ", 0...Double(StrokeEffect.maxSize), 3)
            effect.opacity = opacity(items)
            switch enumeration(items, "Styl") {
            case "InsF": effect.inside = true
            case "CtrF": effect.centered = true
            default: break
            }
            if let value = color(items) { effect.red = value.red; effect.green = value.green; effect.blue = value.blue }
            effect.blendMode = mode(items)
            effects.stroke = effect
        }
        // Normal is what a missing mode draws, so it isn't kept (which keeps plain effects on the GPU pass).
        for kind in LayerEffectKind.allCases where kind != .bevel && effects.blendMode(kind) == .normal {
            effects.clearBlendMode(kind)
        }
        return effects.kinds.isEmpty || !effects.isValid ? nil : effects
    }
}
