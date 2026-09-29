// The C++ Core called straight from Swift. What this has to do — and can't — is part of the spike's findings.
import CoreModelCpp
import XCTest

final class SwiftUsesCppTests: XCTestCase {
    func testSwiftCanDriveTheCppDocument() {
        var document = compositor.core.Document(800, 600)
        // C++ default arguments aren't imported: every optional is spelled out.
        let none = compositor.core.Document.OptionalID()
        let noIndex = compositor.core.Document.OptionalIndex()
        let noSize = compositor.core.Document.OptionalSize()
        let background = document.addLayer(std.string("배경"), none, noIndex, noSize, noSize)
        let group = document.addGroup(std.string("Group"), none, noIndex)
        _ = document.addLayer(std.string("Inside"), compositor.core.Document.OptionalID(group), noIndex, noSize, noSize)

        let outline = document.outline()
        XCTAssertEqual(outline.size(), 3)
        XCTAssertEqual(outline[0].node.pointee.id(), group)
        // `name()` returns `const std::string &` and `layer()` a pointer into the node; Swift imports neither (it
        // can't tell how long they stay valid), so the C++ Core had to grow copying accessors for it.
        XCTAssertEqual(String(outline[2].node.pointee.nameCopy()), "배경")
        XCTAssertTrue(outline[0].node.pointee.isGroupNode())
        XCTAssertEqual(outline[2].node.pointee.id(), background)
    }

    func testTransformsAreSimpleValues() {
        let t = compositor.core.Transform.scale(2, 3).concatenating(compositor.core.Transform.translation(10, 20))
        let p = t.apply(compositor.core.Point(x: 1, y: 1))
        XCTAssertEqual(p.x, 12)
        XCTAssertEqual(p.y, 23)
    }
}
