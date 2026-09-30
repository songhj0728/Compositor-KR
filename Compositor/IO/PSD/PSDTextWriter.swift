import AppKit
import CoreGraphics
import Foundation

/// Writes a text layer as a Photoshop type layer (`TySh`), so the text opens in Photoshop as text it can edit: its
/// words, faces, size, colors (letter by letter), tracking, leading and alignment, point or paragraph, placed by the
/// layer's transform. The layer's pixels are still saved alongside, which Photoshop shows until it sets the text
/// again. From Adobe's *Photoshop File Formats Specification* (Type Tool Object Setting) and the text engine's own
/// dictionary format that `PSDText.parse` reads back.
nonisolated enum PSDTextWriter {
    /// The `TySh` block for `style`, drawn into an image `width` × `height` pixels that `transform` places; nil when the
    /// text can't be written as type (nothing to write, or a transform Photoshop can't take).
    static func block(_ style: LayerTextStyle, transform: LayerTransform, width: Int, height: Int) -> Data? {
        guard style.isValid, !style.content.isEmpty, width > 0, height > 0 else { return nil }
        let padding = LayerTextStyle.padding
        let image = CGSize(width: width, height: height)
        let isBox = style.boxSize != nil
        // Where text space's origin sits in the layer's pixels: a paragraph's frame corner, or point text's first
        // baseline at its alignment point.
        let origin = isBox
            ? CGPoint(x: padding, y: padding)
            : CGPoint(x: PSDText.horizontalAnchor(style, width: image.width), y: PSDText.baseline(style, image: image))
        let matrix = CGAffineTransform(translationX: origin.x, y: origin.y)
            .concatenating(BrushRaster.pixelToDocument(transform, width: width, height: height))
        guard [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty].allSatisfy(\.isFinite),
              abs(matrix.a * matrix.d - matrix.b * matrix.c) > 1e-9 else { return nil }

        // The text's frame in text space.
        let frame: CGRect
        if isBox {
            frame = CGRect(x: 0, y: 0, width: max(1, image.width - padding * 2), height: max(1, image.height - padding * 2))
        } else {
            let textWidth = max(1, image.width - padding * 2)
            let left: CGFloat = style.alignment == .left ? 0 : style.alignment == .center ? -textWidth / 2 : -textWidth
            frame = CGRect(x: left, y: padding - origin.y, width: textWidth, height: max(1, image.height - padding * 2))
        }
        let glyphs = isBox ? usedFrame(style, in: frame.size) : frame

        let text = style.content.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        var descriptor = PSDWriteBuffer()
        descriptor.u16(1)
        // Adobe's matrix is row-vector style: x' = xx·x + yx·y + tx, y' = xy·x + yy·y + ty.
        for value in [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty] { descriptor.f64(Double(value)) }
        descriptor.u16(50)
        descriptor.u32(16)
        func rect(_ classID: String, _ rect: CGRect) -> PSDDescriptorItem {
            .object(classID: classID, items: [("Left", .unit("#Pnt", Double(rect.minX))), ("Top ", .unit("#Pnt", Double(rect.minY))),
                                              ("Rght", .unit("#Pnt", Double(rect.maxX))), ("Btom", .unit("#Pnt", Double(rect.maxY)))])
        }
        PSDDescriptorItem.body(&descriptor, classID: "TxLr", items: [
            ("Txt ", .text(text)),
            ("textGridding", .enumeration(type: "textGridding", value: "None")),
            ("Ornt", .enumeration(type: "Ornt", value: "Hrzn")),
            ("AntA", .enumeration(type: "Annt", value: "AnSm")),
            ("bounds", rect("bounds", frame)),
            ("boundingBox", rect("boundingBox", glyphs)),
            ("TextIndex", .long(0)),
            ("EngineData", .raw(engineData(style, text: text, box: isBox ? frame.size : nil)))
        ])
        descriptor.u16(1)
        descriptor.u32(16)
        PSDDescriptorItem.body(&descriptor, classID: "warp", items: [
            ("warpStyle", .enumeration(type: "warpStyle", value: "warpNone")),
            ("warpValue", .double(0)),
            ("warpPerspective", .double(0)),
            ("warpPerspectiveOther", .double(0)),
            ("warpRotate", .enumeration(type: "Ornt", value: "Hrzn"))
        ])
        // Left, top, right and bottom, which Photoshop works out again itself.
        for _ in 0..<4 { descriptor.i32(0) }
        return descriptor.data
    }

    /// Where the letters of a paragraph actually reach inside its frame.
    private static func usedFrame(_ style: LayerTextStyle, in size: CGSize) -> CGRect {
        let storage = NSTextStorage(attributedString: NSAttributedString(string: style.content, attributes: EditorSession.textAttributes(style)))
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, size.width), height: max(1, size.height)))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let used = layout.usedRect(for: container)
        return CGRect(x: 0, y: 0, width: min(size.width, max(1, ceil(used.width))), height: min(size.height, max(1, ceil(used.height))))
    }

    // MARK: The text engine's dictionary

    /// A value in the text engine's PostScript-like dictionary.
    indirect enum Value {
        case dict([(String, Value)]), array([Value]), int(Int), double(Double), bool(Bool), text(String)
    }

    /// Runs of letters sharing a face and a color, in UTF-16 units of `content`.
    struct Run: Equatable {
        var length: Int
        var font: String
        var color: PaletteColor
    }

    static func runs(_ style: LayerTextStyle) -> [Run] {
        let units = style.content.utf16.count
        guard units > 0 else { return [Run(length: 0, font: style.fontName, color: PaletteColor(red: style.red, green: style.green, blue: style.blue))] }
        var runs: [Run] = []
        for index in 0..<units {
            let font = style.fontName(at: index), color = style.color(at: index)
            if let last = runs.last, last.font == font, last.color == color { runs[runs.count - 1].length += 1 }
            else { runs.append(Run(length: 1, font: font, color: color)) }
        }
        return runs
    }

    static func engineData(_ style: LayerTextStyle, text: String, box: CGSize?) -> Data {
        var runs = runs(style)
        // Photoshop's text always ends in a return, which belongs to the last run.
        runs[runs.count - 1].length += 1
        var fonts: [String] = []
        for run in runs where !fonts.contains(run.font) { fonts.append(run.font) }
        let tracking = style.fontSize > 0 ? Int((style.tracking * 1000 / style.fontSize).rounded()) : 0
        func color(_ color: PaletteColor) -> Value {
            .dict([("Type", .int(1)), ("Values", .array([.double(1), .double(Double(color.red)), .double(Double(color.green)), .double(Double(color.blue))]))])
        }
        let styleRuns: [Value] = runs.map { run in
            .dict([("StyleSheet", .dict([("StyleSheetData", .dict([
                ("Font", .int(fonts.firstIndex(of: run.font) ?? 0)),
                ("FontSize", .double(Double(style.fontSize))),
                ("FauxBold", .bool(false)),
                ("FauxItalic", .bool(false)),
                ("AutoLeading", .bool(style.leading <= 0)),
                ("Leading", .double(Double(style.lineHeight))),
                ("HorizontalScale", .double(1)),
                ("VerticalScale", .double(1)),
                ("Tracking", .int(tracking)),
                ("AutoKerning", .bool(true)),
                ("Kerning", .int(0)),
                ("BaselineShift", .double(0)),
                ("FontCaps", .int(0)),
                ("FontBaseline", .int(0)),
                ("Underline", .bool(false)),
                ("Strikethrough", .bool(false)),
                ("Ligatures", .bool(true)),
                ("DLigatures", .bool(false)),
                ("BaselineDirection", .int(2)),
                ("Tsume", .double(0)),
                ("StyleRunAlignment", .int(2)),
                ("Language", .int(0)),
                ("NoBreak", .bool(false)),
                ("FillColor", color(run.color)),
                ("StrokeColor", color(.black)),
                ("FillFlag", .bool(true)),
                ("StrokeFlag", .bool(false)),
                ("FillFirst", .bool(true)),
                ("YUnderline", .int(1)),
                ("OutlineWidth", .double(1)),
                ("CharacterDirection", .int(0)),
                ("HindiNumbers", .bool(false)),
                ("Kashida", .int(1)),
                ("DiacriticPos", .int(2))
            ]))]))])
        }
        let justification = style.alignment == .left ? 0 : style.alignment == .right ? 1 : 2
        let adjustments: Value = .dict([("Axis", .array([.double(1), .double(0), .double(1)])), ("XY", .array([.double(0), .double(0)]))])
        let paragraphRun: Value = .dict([
            ("ParagraphSheet", .dict([("DefaultStyleSheet", .int(0)), ("Properties", paragraphProperties(justification: justification))])),
            ("Adjustments", adjustments)
        ])
        let total = runs.reduce(0) { $0 + $1.length }
        let shapeType = box == nil ? 0 : 1
        var photoshop: [(String, Value)] = [("ShapeType", .int(shapeType))]
        if let box {
            photoshop.append(("BoxBounds", .array([.double(0), .double(0), .double(Double(box.width)), .double(Double(box.height))])))
        } else {
            photoshop.append(("PointBase", .array([.double(0), .double(0)])))
        }
        photoshop.append(("Base", .dict([("ShapeType", .int(shapeType)),
                                         ("TransformPoint0", .array([.double(1), .double(0)])),
                                         ("TransformPoint1", .array([.double(0), .double(1)])),
                                         ("TransformPoint2", .array([.double(0), .double(0)]))])))
        let engineDict: Value = .dict([
            ("Editor", .dict([("Text", .text(text + "\r"))])),
            ("ParagraphRun", .dict([
                ("DefaultRunData", .dict([("ParagraphSheet", .dict([("DefaultStyleSheet", .int(0)), ("Properties", .dict([]))])),
                                          ("Adjustments", adjustments)])),
                ("RunArray", .array([paragraphRun])),
                ("RunLengthArray", .array([.int(total)])),
                ("IsJoinable", .int(1))
            ])),
            ("StyleRun", .dict([
                ("DefaultRunData", .dict([("StyleSheet", .dict([("StyleSheetData", .dict([]))]))])),
                ("RunArray", .array(styleRuns)),
                ("RunLengthArray", .array(runs.map { .int($0.length) })),
                ("IsJoinable", .int(2))
            ])),
            ("GridInfo", .dict([
                ("GridIsOn", .bool(false)), ("ShowGrid", .bool(false)), ("GridSize", .double(18)), ("GridLeading", .double(22)),
                ("GridColor", .dict([("Type", .int(1)), ("Values", .array([.double(0), .double(0), .double(0), .double(1)]))])),
                ("GridLeadingFillColor", .dict([("Type", .int(1)), ("Values", .array([.double(0), .double(0), .double(0), .double(1)]))])),
                ("AlignLineHeightToGridFlags", .bool(false))
            ])),
            ("AntiAlias", .int(4)),
            ("UseFractionalGlyphWidths", .bool(true)),
            ("Rendered", .dict([
                ("Version", .int(1)),
                ("Shapes", .dict([
                    ("WritingDirection", .int(0)),
                    ("Children", .array([.dict([
                        ("ShapeType", .int(shapeType)),
                        ("Procession", .int(0)),
                        ("Lines", .dict([("WritingDirection", .int(0)), ("Children", .array([]))])),
                        ("Cookie", .dict([("Photoshop", .dict(photoshop))]))
                    ])]))
                ]))
            ]))
        ])
        let resources = resourceDict(fonts: fonts)
        let root: Value = .dict([("EngineDict", engineDict), ("ResourceDict", resources), ("DocumentResources", resources)])
        var bytes: [UInt8] = Array("\n\n".utf8)
        serialize(root, depth: 0, into: &bytes)
        bytes.append(contentsOf: Array("\n".utf8))
        return Data(bytes)
    }

    private static func paragraphProperties(justification: Int) -> Value {
        .dict([
            ("Justification", .int(justification)),
            ("FirstLineIndent", .double(0)),
            ("StartIndent", .double(0)),
            ("EndIndent", .double(0)),
            ("SpaceBefore", .double(0)),
            ("SpaceAfter", .double(0)),
            ("AutoHyphenate", .bool(true)),
            ("HyphenatedWordSize", .int(6)),
            ("PreHyphen", .int(2)),
            ("PostHyphen", .int(2)),
            ("ConsecutiveHyphens", .int(8)),
            ("Zone", .double(36)),
            ("WordSpacing", .array([.double(0.8), .double(1), .double(1.33)])),
            ("LetterSpacing", .array([.double(0), .double(0), .double(0)])),
            ("GlyphSpacing", .array([.double(1), .double(1), .double(1)])),
            ("AutoLeading", .double(1.2)),
            ("LeadingType", .int(0)),
            ("Hanging", .bool(false)),
            ("Burasagari", .bool(false)),
            ("KinsokuOrder", .int(0)),
            ("EveryLineComposer", .bool(false))
        ])
    }

    private static func resourceDict(fonts: [String]) -> Value {
        let normalStyle: Value = .dict([
            ("Font", .int(0)), ("FontSize", .double(12)), ("FauxBold", .bool(false)), ("FauxItalic", .bool(false)),
            ("AutoLeading", .bool(true)), ("Leading", .double(0)), ("HorizontalScale", .double(1)), ("VerticalScale", .double(1)),
            ("Tracking", .int(0)), ("AutoKerning", .bool(true)), ("Kerning", .int(0)), ("BaselineShift", .double(0)),
            ("FontCaps", .int(0)), ("FontBaseline", .int(0)), ("Underline", .bool(false)), ("Strikethrough", .bool(false)),
            ("Ligatures", .bool(true)), ("DLigatures", .bool(false)), ("BaselineDirection", .int(2)), ("Tsume", .double(0)),
            ("StyleRunAlignment", .int(2)), ("Language", .int(0)), ("NoBreak", .bool(false)),
            ("FillColor", .dict([("Type", .int(1)), ("Values", .array([.double(1), .double(0), .double(0), .double(0)]))])),
            ("StrokeColor", .dict([("Type", .int(1)), ("Values", .array([.double(1), .double(0), .double(0), .double(0)]))])),
            ("FillFlag", .bool(true)), ("StrokeFlag", .bool(false)), ("FillFirst", .bool(true)), ("YUnderline", .int(1)),
            ("OutlineWidth", .double(1)), ("CharacterDirection", .int(0)), ("HindiNumbers", .bool(false)),
            ("Kashida", .int(1)), ("DiacriticPos", .int(2))
        ])
        let kinsoku: Value = .array([
            .dict([("Name", .text("PhotoshopKinsokuHard")), ("NoStart", .text("、。，．・：；？！ー―’”）〕］｝〉》」』】ヽヾゝゞ々ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ゛゜?!)]},.:;")),
                   ("NoEnd", .text("‘“（〔［｛〈《「『【([{")), ("Keep", .text("―‥")), ("Hanging", .text("、。.,"))]),
            .dict([("Name", .text("PhotoshopKinsokuSoft")), ("NoStart", .text("、。，．・：；？！’”）〕］｝〉》」』】ヽヾゝゞ々")),
                   ("NoEnd", .text("‘“（〔［｛〈《「『【")), ("Keep", .text("―‥")), ("Hanging", .text("、。.,"))])
        ])
        let mojiKumi: Value = .array((1...4).map { .dict([("InternalName", .text("Photoshop6MojiKumiSet\($0)"))]) })
        var fontSet: [Value] = fonts.map { .dict([("Name", .text($0)), ("Script", .int(0)), ("FontType", .int(0)), ("Synthetic", .int(0))]) }
        fontSet.append(.dict([("Name", .text("AdobeInvisFont")), ("Script", .int(0)), ("FontType", .int(0)), ("Synthetic", .int(0))]))
        return .dict([
            ("KinsokuSet", kinsoku),
            ("MojiKumiSet", mojiKumi),
            ("TheNormalStyleSheet", .int(0)),
            ("TheNormalParagraphSheet", .int(0)),
            ("ParagraphSheetSet", .array([.dict([("Name", .text("Normal RGB")), ("DefaultStyleSheet", .int(0)),
                                                 ("Properties", paragraphProperties(justification: 0))])])),
            ("StyleSheetSet", .array([.dict([("Name", .text("Normal RGB")), ("StyleSheetData", normalStyle)])])),
            ("FontSet", .array(fontSet)),
            ("SuperscriptSize", .double(0.583)),
            ("SuperscriptPosition", .double(0.333)),
            ("SubscriptSize", .double(0.583)),
            ("SubscriptPosition", .double(0.333)),
            ("SmallCapSize", .double(0.7))
        ])
    }

    /// The dictionary as Photoshop writes it: tab-indented, one key to a line, strings as UTF-16 with a byte-order mark.
    static func serialize(_ value: Value, depth: Int, into bytes: inout [UInt8]) {
        func indent(_ level: Int) { bytes.append(contentsOf: [UInt8](repeating: 0x09, count: max(0, level))) }
        switch value {
        case .dict(let items):
            bytes.append(contentsOf: Array("<<\n".utf8))
            for (key, item) in items {
                indent(depth + 1)
                bytes.append(contentsOf: Array("/\(key)".utf8))
                switch item {
                case .dict, .array:
                    bytes.append(0x0A)
                    indent(depth + 1)
                    serialize(item, depth: depth + 1, into: &bytes)
                default:
                    bytes.append(0x20)
                    serialize(item, depth: depth + 1, into: &bytes)
                }
                bytes.append(0x0A)
            }
            indent(depth)
            bytes.append(contentsOf: Array(">>".utf8))
        case .array(let items):
            let simple = items.allSatisfy { if case .dict = $0 { return false } else { return true } }
            if simple {
                bytes.append(contentsOf: Array("[".utf8))
                for item in items {
                    bytes.append(0x20)
                    serialize(item, depth: depth, into: &bytes)
                }
                bytes.append(contentsOf: Array(" ]".utf8))
            } else {
                bytes.append(contentsOf: Array("[\n".utf8))
                for item in items {
                    indent(depth + 1)
                    serialize(item, depth: depth + 1, into: &bytes)
                    bytes.append(0x0A)
                }
                indent(depth)
                bytes.append(contentsOf: Array("]".utf8))
            }
        case .int(let number):
            bytes.append(contentsOf: Array(String(number).utf8))
        case .double(let number):
            bytes.append(contentsOf: Array(format(number).utf8))
        case .bool(let flag):
            bytes.append(contentsOf: Array((flag ? "true" : "false").utf8))
        case .text(let string):
            bytes.append(0x28)
            var encoded: [UInt8] = [0xFE, 0xFF]
            for unit in string.utf16 { encoded.append(UInt8(unit >> 8)); encoded.append(UInt8(unit & 0xFF)) }
            // The string's own parentheses and backslashes are escaped, byte by byte.
            for byte in encoded {
                if byte == 0x28 || byte == 0x29 || byte == 0x5C { bytes.append(0x5C) }
                bytes.append(byte)
            }
            bytes.append(0x29)
        }
    }

    /// A number as the engine writes it: always with a decimal point, no leading zero (".583").
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "0.0" }
        if value == value.rounded(), abs(value) < 1e9 { return String(format: "%.1f", value) }
        var text = String(format: "%.5f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasPrefix("0.") { text.removeFirst() }
        else if text.hasPrefix("-0.") { text = "-" + text.dropFirst(2) }
        return text
    }
}
