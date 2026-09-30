import AppKit
import SwiftUI
import Testing
@testable import Compositor

struct TextAlignmentTests {
    // Qualify the domain enum: SwiftUI has a different TextAlignment type.
    private let expected: [(Compositor.TextAlignment, String)] = [
        (.left, "Left"), (.center, "Center"), (.right, "Right"),
    ]

    @Test func casesOrderAndPresentationStayStable() {
        #expect(Compositor.TextAlignment.allCases == expected.map { $0.0 })
        #expect(Set(Compositor.TextAlignment.allCases).count == 3)
        for (alignment, value) in expected {
            #expect(alignment.rawValue == value)
            #expect(Compositor.TextAlignment(rawValue: value) == alignment)
            #expect(alignment.displayName == LocalizedStringKey(value))
        }
    }

    @Test func codableKeepsExistingWireValues() throws {
        for (alignment, value) in expected {
            let wire = Data("\"\(value)\"".utf8)
            #expect(try JSONEncoder().encode(alignment) == wire)
            #expect(try JSONDecoder().decode(Compositor.TextAlignment.self, from: wire) == alignment)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Compositor.TextAlignment.self, from: Data("\"Justified\"".utf8))
        }
    }

    @Test func textStyleKeepsItsSerializedAlignment() throws {
        for (alignment, value) in expected {
            var style = LayerTextStyle()
            style.content = "한글 alignment"
            style.alignment = alignment
            let data = try JSONEncoder().encode(style)
            let record = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(record["alignment"] as? String == value)
            #expect(try JSONDecoder().decode(LayerTextStyle.self, from: data) == style)
        }
    }

    @MainActor @Test func rendererParagraphMappingStaysStable() throws {
        let mappings: [(Compositor.TextAlignment, NSTextAlignment)] = [
            (.left, .left), (.center, .center), (.right, .right),
        ]
        for (alignment, native) in mappings {
            var style = LayerTextStyle()
            style.alignment = alignment
            let paragraph = try #require(EditorSession.textAttributes(style)[.paragraphStyle] as? NSParagraphStyle)
            #expect(paragraph.alignment == native)
        }
    }
}
