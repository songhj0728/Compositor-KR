import CoreModel
import XCTest

final class DocumentTests: XCTestCase {
    func testAddingStacksLayersBottomToTop() throws {
        var document = Document(width: 800, height: 600)
        let background = try document.addLayer(named: "Background")
        let top = try document.addLayer(named: "Top", width: 100, height: 50)
        XCTAssertEqual(document.layers.map(\.id), [background, top])
        guard case .layer(let layer)? = document.node(top) else { return XCTFail("not a layer") }
        XCTAssertEqual(layer.width, 100)
        XCTAssertEqual(layer.height, 50)
    }

    func testGroupingKeepsOrderAndTakesTheTopmostPlace() throws {
        var document = Document(width: 10, height: 10)
        let a = try document.addLayer(named: "A")
        let b = try document.addLayer(named: "B")
        let c = try document.addLayer(named: "C")
        let d = try document.addLayer(named: "D")
        let group = try document.group([c, a], named: "Group")
        XCTAssertEqual(document.layers.map(\.id), [b, group, d])
        guard case .group(let made)? = document.node(group) else { return XCTFail("not a group") }
        XCTAssertEqual(made.children.map(\.id), [a, c])
        XCTAssertEqual(document.location(of: c)?.parent, group)
    }

    func testGroupingNeedsSiblings() throws {
        var document = Document(width: 10, height: 10)
        let a = try document.addLayer(named: "A")
        let group = try document.addGroup(named: "G")
        let inside = try document.addLayer(named: "Inside", in: group)
        XCTAssertThrowsError(try document.group([a, inside], named: "X")) {
            XCTAssertEqual($0 as? DocumentError, .notSiblings)
        }
    }

    // Found through the WinUI spike: the same layer twice once took the process down.
    func testGroupingRejectsTheSameLayerTwice() throws {
        var document = Document(width: 10, height: 10)
        let a = try document.addLayer(named: "A")
        try document.addLayer(named: "B")
        let before = document
        XCTAssertThrowsError(try document.group([a, a], named: "X")) {
            XCTAssertEqual($0 as? DocumentError, .duplicateLayer(a))
        }
        XCTAssertEqual(document, before)
    }

    func testUngroupPutsChildrenBackInPlace() throws {
        var document = Document(width: 10, height: 10)
        let a = try document.addLayer(named: "A")
        let b = try document.addLayer(named: "B")
        let c = try document.addLayer(named: "C")
        let group = try document.group([a, b], named: "G")
        try document.ungroup(group)
        XCTAssertEqual(document.layers.map(\.id), [a, b, c])
        XCTAssertNil(document.node(group))
    }

    func testAGroupCantMoveIntoItself() throws {
        var document = Document(width: 10, height: 10)
        let outer = try document.addGroup(named: "Outer")
        let inner = try document.addGroup(named: "Inner", in: outer)
        XCTAssertThrowsError(try document.move(outer, to: inner, at: 0)) {
            XCTAssertEqual($0 as? DocumentError, .wouldContainItself)
        }
        XCTAssertThrowsError(try document.move(outer, to: outer, at: 0))
        XCTAssertEqual(document.location(of: inner)?.parent, outer)
    }

    func testMoveBetweenGroups() throws {
        var document = Document(width: 10, height: 10)
        let layer = try document.addLayer(named: "L")
        let group = try document.addGroup(named: "G")
        try document.move(layer, to: group, at: 0)
        XCTAssertEqual(document.location(of: layer)?.parent, group)
        XCTAssertEqual(document.layers.map(\.id), [group])
    }

    func testVisibleLayersFollowGroupsVisibilityAndOpacity() throws {
        var document = Document(width: 10, height: 10)
        let group = try document.addGroup(named: "G")
        let a = try document.addLayer(named: "A", in: group)
        let hidden = try document.addLayer(named: "Hidden", in: group)
        let b = try document.addLayer(named: "B")
        try document.updateGroup(group) { $0.opacity = 0.5 }
        try document.updateLayer(a) { $0.opacity = 0.5 }
        try document.updateLayer(hidden) { $0.isVisible = false }
        let visible = document.visibleLayers
        XCTAssertEqual(visible.map(\.layer.id), [a, b])
        XCTAssertEqual(visible[0].opacity, 0.25, accuracy: 1e-12)
        XCTAssertEqual(visible[1].opacity, 1)
    }

    func testOutlineListsTopFirstWithDepth() throws {
        var document = Document(width: 10, height: 10)
        let bottom = try document.addLayer(named: "Bottom")
        let group = try document.addGroup(named: "G")
        let inside = try document.addLayer(named: "Inside", in: group)
        XCTAssertEqual(document.outline.map(\.node.id), [group, inside, bottom])
        XCTAssertEqual(document.outline.map(\.depth), [0, 1, 0])
    }

    func testMissingLayersThrow() {
        var document = Document(width: 10, height: 10)
        XCTAssertThrowsError(try document.remove(LayerID(99))) {
            XCTAssertEqual($0 as? DocumentError, .noSuchLayer(LayerID(99)))
        }
    }
}

final class TransformTests: XCTestCase {
    func testConcatenationAppliesInOrder() {
        let t = Transform.scale(2, 3).concatenating(.translation(10, 20))
        XCTAssertEqual(t.apply(to: Point(x: 1, y: 1)), Point(x: 12, y: 23))
    }

    func testRotationIsClockwiseOnScreen() {
        let p = Transform.rotation(.pi / 2).apply(to: Point(x: 1, y: 0))
        XCTAssertEqual(p.x, 0, accuracy: 1e-12)
        XCTAssertEqual(p.y, 1, accuracy: 1e-12)
    }

    func testInverseUndoesTheTransform() throws {
        let t = Transform.rotation(0.7).concatenating(.scale(2, 0.5)).concatenating(.translation(-3, 9))
        let inverse = try XCTUnwrap(t.inverted)
        let p = t.concatenating(inverse).apply(to: Point(x: 5, y: -7))
        XCTAssertEqual(p.x, 5, accuracy: 1e-9)
        XCTAssertEqual(p.y, -7, accuracy: 1e-9)
        XCTAssertNil(Transform.scale(0, 1).inverted)
    }
}

final class HistoryTests: XCTestCase {
    func testUndoAndRedoRestoreWholeDocuments() throws {
        var history = History(Document(width: 10, height: 10))
        let a = try history.perform("Add A") { try $0.addLayer(named: "A") }
        try history.perform("Rename") { try $0.updateLayer(a) { $0.name = "Renamed" } }
        XCTAssertEqual(history.undoName, "Rename")
        XCTAssertEqual(history.undo(), "Rename")
        XCTAssertEqual(history.document.node(a)?.name, "A")
        XCTAssertEqual(history.undo(), "Add A")
        XCTAssertTrue(history.document.layers.isEmpty)
        XCTAssertNil(history.undo())
        XCTAssertEqual(history.redo(), "Add A")
        XCTAssertEqual(history.redo(), "Rename")
        XCTAssertEqual(history.document.node(a)?.name, "Renamed")
    }

    func testAFailedChangeLeavesNoTrace() throws {
        var history = History(Document(width: 10, height: 10))
        try history.perform("Add") { try $0.addLayer(named: "A") }
        let before = history.document
        XCTAssertThrowsError(try history.perform("Bad") { document in
            try document.addLayer(named: "B")
            try document.ungroup(LayerID(999))
        })
        XCTAssertEqual(history.document, before)
        XCTAssertEqual(history.undoName, "Add")
    }

    func testANewChangeClearsRedo() throws {
        var history = History(Document(width: 10, height: 10))
        try history.perform("A") { try $0.addLayer(named: "A") }
        history.undo()
        try history.perform("B") { try $0.addLayer(named: "B") }
        XCTAssertFalse(history.canRedo)
    }

    func testNoOpChangesAreNotRecorded() throws {
        var history = History(Document(width: 10, height: 10))
        history.perform("Nothing") { _ in }
        XCTAssertFalse(history.canUndo)
    }

    func testLimitDropsTheOldestSteps() throws {
        var history = History(Document(width: 10, height: 10), limit: 3)
        for i in 0..<5 { try history.perform("Step \(i)") { try $0.addLayer(named: "\(i)") } }
        var names: [String] = []
        while let name = history.undo() { names.append(name) }
        XCTAssertEqual(names, ["Step 4", "Step 3", "Step 2"])
        XCTAssertEqual(history.document.layers.count, 2)
    }
}
