import AppKit
import Testing
@testable import Compositor

/// The Pen, Path Selection and Direct Selection tools, the Paths panel's commands, and the Channels view.
@MainActor
struct PathToolTests {
    private func session(width: Int = 200, height: Int = 100, profile: DocumentColorProfile = .sRGB) -> EditorSession {
        let session = EditorSession()
        session.createNewProject(width: width, height: height, profile: profile)
        return session
    }

    /// A click with the Pen at `point`, optionally dragged to `drag` before letting go.
    private func pen(_ session: EditorSession, _ point: CGPoint, drag: CGPoint? = nil, option: Bool = false) {
        session.penPress(at: point, tolerance: 4, option: option, shift: false)
        if let drag { session.pathDragMoved(to: drag, shift: false) }
        session.pathDragEnded()
    }

    @Test func penClicksMakeCornersAndDragsMakeCurvesAndTheFirstAnchorCloses() throws {
        let session = session()
        session.selectTool(.pen)
        pen(session, CGPoint(x: 20, y: 20))
        pen(session, CGPoint(x: 120, y: 20), drag: CGPoint(x: 150, y: 20))
        pen(session, CGPoint(x: 120, y: 80))
        let open = try #require(session.activePath)
        #expect(session.paths.count == 1 && open.name == String(localized: "Path") + " 1")
        #expect(open.contours.count == 1 && open.contours[0].anchors.count == 3 && !open.contours[0].isClosed)
        let curved = open.contours[0].anchors[1]
        #expect(curved.isSmooth && curved.outHandle == PathVector(150, 20) && curved.inHandle == PathVector(90, 20))
        #expect(!open.contours[0].anchors[0].hasOutHandle, "a plain click is a corner")
        pen(session, CGPoint(x: 21, y: 21)) // The first anchor, within the tolerance.
        let closed = try #require(session.activePath)
        #expect(closed.contours[0].isClosed && closed.contours[0].anchors.count == 3)
        #expect(session.penDraft == nil, "closing ends the contour; the next click starts another")
        pen(session, CGPoint(x: 170, y: 70))
        #expect(session.activePath?.contours.count == 2)
    }

    @Test func eachPenGestureIsOneUndoStepAndTheWholePathUndoesAway() throws {
        let session = session()
        session.selectTool(.pen)
        let before = session.history.undoCount
        pen(session, CGPoint(x: 20, y: 20))
        pen(session, CGPoint(x: 80, y: 20), drag: CGPoint(x: 100, y: 40))
        #expect(session.history.undoCount == before + 2)
        session.undo()
        #expect(session.activePath?.contours[0].anchors.count == 1)
        session.undo()
        #expect(session.paths.isEmpty)
        session.redo()
        #expect(session.paths.first?.contours.first?.anchors.count == 1)
    }

    @Test func penAddsOnASegmentDeletesAnAnchorAndOptionConverts() throws {
        let session = session()
        session.selectTool(.pen)
        pen(session, CGPoint(x: 20, y: 50))
        pen(session, CGPoint(x: 180, y: 50))
        session.finishPenContour()
        pen(session, CGPoint(x: 100, y: 51)) // On the segment.
        #expect(session.activePath?.contours[0].anchors.count == 3)
        pen(session, CGPoint(x: 100, y: 50), option: true) // Convert the new smooth anchor to a corner.
        #expect(session.activePath?.contours[0].anchors[1].hasOutHandle == false)
        pen(session, CGPoint(x: 100, y: 50)) // Delete it.
        #expect(session.activePath?.contours[0].anchors.map(\.point) == [PathVector(20, 50), PathVector(180, 50)])
    }

    @Test func pathSelectionMovesWholeContoursAndDirectSelectionMovesAnchorsAndHandles() throws {
        let session = session()
        session.selectTool(.pen)
        pen(session, CGPoint(x: 20, y: 20))
        pen(session, CGPoint(x: 60, y: 20), drag: CGPoint(x: 80, y: 20))
        pen(session, CGPoint(x: 60, y: 60))
        session.selectTool(.pathSelection)
        #expect(session.pathSelectionKind == .path)
        session.pathSelectionPress(at: CGPoint(x: 40, y: 21), tolerance: 4, shift: false, option: false)
        session.pathDragMoved(to: CGPoint(x: 50, y: 31), shift: false)
        session.pathDragEnded()
        let moved = try #require(session.activePath?.contours[0])
        #expect(moved.anchors.map(\.point) == [PathVector(30, 30), PathVector(70, 30), PathVector(70, 70)])
        #expect(moved.anchors[1].outHandle == PathVector(90, 30), "handles travel with their anchors")

        session.cycleToolMode()
        #expect(session.pathSelectionKind == .direct)
        session.pathSelectionPress(at: CGPoint(x: 70, y: 70), tolerance: 4, shift: false, option: false)
        session.pathDragMoved(to: CGPoint(x: 70, y: 90), shift: false)
        session.pathDragEnded()
        #expect(session.activePath?.contours[0].anchors[2].point == PathVector(70, 90))
        #expect(session.activePath?.contours[0].anchors[0].point == PathVector(30, 30), "only the picked anchor moves")

        // The smooth anchor's handle: picked, its handles show, and dragging one keeps the other in line.
        session.pathSelectionPress(at: CGPoint(x: 70, y: 30), tolerance: 4, shift: false, option: false)
        session.pathDragEnded()
        session.pathSelectionPress(at: CGPoint(x: 90, y: 30), tolerance: 4, shift: false, option: false)
        session.pathDragMoved(to: CGPoint(x: 70, y: 50), shift: false)
        session.pathDragEnded()
        let smooth = try #require(session.activePath?.contours[0].anchors[1])
        #expect(smooth.outHandle == PathVector(70, 50))
        #expect(abs(smooth.inHandle.x - 70) < 0.0001 && abs(smooth.inHandle.y - 10) < 0.0001)

        // A box around two anchors picks both; Delete removes them.
        session.pathSelectionPress(at: CGPoint(x: 150, y: 5), tolerance: 4, shift: false, option: false)
        session.pathDragMoved(to: CGPoint(x: 60, y: 40), shift: false)
        session.pathDragEnded()
        #expect(session.selectedPathAnchors == [PathAnchorRef(contour: 0, anchor: 1)])
        #expect(session.deleteSelectedPathParts())
        #expect(session.activePath?.contours[0].anchors.count == 2)
    }

    @Test func pathsBecomeSelectionsAndSelectionsBecomePaths() throws {
        let session = session()
        session.selectTool(.pen)
        for point in [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 10), CGPoint(x: 60, y: 40), CGPoint(x: 10, y: 40), CGPoint(x: 10, y: 10)] {
            pen(session, point)
        }
        session.loadPathAsSelection()
        let selection = try #require(session.selection)
        #expect(selection.path.boundingBoxOfPath == CGRect(x: 10, y: 10, width: 50, height: 30))
        #expect(selection.path.contains(CGPoint(x: 30, y: 25)) && !selection.path.contains(CGPoint(x: 80, y: 25)))

        session.applySelection(CGPath(ellipseIn: CGRect(x: 100, y: 20, width: 60, height: 60), transform: nil), mode: .replace, name: "Ellipse")
        session.makePathFromSelection()
        let made = try #require(session.activePath)
        #expect(session.paths.count == 2 && made.contours.count == 1 && made.contours[0].isClosed)
        let box = made.cgPath.boundingBoxOfPath
        #expect(abs(box.minX - 100) < 0.5 && abs(box.maxX - 160) < 0.5 && abs(box.minY - 20) < 0.5 && abs(box.maxY - 80) < 0.5)
    }

    @Test func pathsSaveInVersion14AndProjectsWithoutThemKeepTheOlderVersion() async throws {
        let plain = session()
        let plainSnapshot = try #require(plain.projectSnapshot())
        #expect(plainSnapshot.manifest.paths == nil && plainSnapshot.manifest.neededVersion < 14)

        let session = session()
        session.selectTool(.pen)
        pen(session, CGPoint(x: 10, y: 10))
        pen(session, CGPoint(x: 90, y: 50), drag: CGPoint(x: 120, y: 50))
        session.renamePath(try #require(session.activePathID), to: "Outline")
        let snapshot = try #require(session.projectSnapshot())
        #expect(snapshot.manifest.neededVersion == 14)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Paths-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(snapshot, to: url)
        let loaded = try await ProjectStore.shared.load(from: url)
        #expect(loaded.manifest.version == 14)
        let reopened = EditorSession()
        reopened.installProject(loaded, from: url)
        #expect(reopened.paths == session.paths)
        #expect(reopened.paths.first?.name == "Outline")
    }

    @Test func pathsTurnScaleAndFlipWithTheCanvasAndRotationKeepsTheColorProfile() async throws {
        let session = session(width: 200, height: 100, profile: .displayP3)
        session.selectTool(.pen)
        pen(session, CGPoint(x: 20, y: 10))
        pen(session, CGPoint(x: 180, y: 90))
        session.rotateCanvas(clockwise: true)
        #expect(session.document?.colorProfile == .displayP3, "rotating keeps the project's profile")
        #expect(session.activePath?.contours[0].anchors.map(\.point) == [PathVector(90, 20), PathVector(10, 180)])
        session.flipCanvas(horizontally: true)
        #expect(session.activePath?.contours[0].anchors.map(\.point) == [PathVector(10, 20), PathVector(90, 180)])
        let snapshot = try #require(session.projectSnapshot())
        let resized = try await ImageResizer.shared.resize(snapshot, to: ImageSizeOptions(width: 50, height: 100, resolution: 72))
        session.applyImageSize(resized)
        #expect(session.activePath?.contours[0].anchors.map(\.point) == [PathVector(5, 10), PathVector(45, 90)])
    }

    @Test func aChannelShowsInGrayLaidOverWhite() {
        let pixels: [UInt8] = [255, 0, 0, 255,   0, 0, 128, 128,   0, 0, 0, 0]
        let gray = pixels.withUnsafeBufferPointer { ColorChannels.gray(premultipliedRGBA: $0, width: 3, height: 1, bytesPerRow: 12, channel: 0) }
        #expect(gray == [255, 127, 255], "full red, a half-clear blue pixel's empty red, and clear")
        let blue = pixels.withUnsafeBufferPointer { ColorChannels.gray(premultipliedRGBA: $0, width: 3, height: 1, bytesPerRow: 12, channel: 2) }
        #expect(blue == [0, 255, 255])
    }

    @Test func channelImagesComeFromTheComposite() throws {
        let session = EditorSession()
        session.createNewProject(width: 20, height: 10, background: PaletteColor(red: 1, green: 0, blue: 0))
        let red = try #require(session.channelImage(.red, maxSide: 20))
        let green = try #require(session.channelImage(.green, maxSide: 20))
        func center(_ image: CGImage) throws -> UInt8 {
            let data = try #require(image.dataProvider?.data) as Data
            return data[image.bytesPerRow * 5 + 10]
        }
        #expect(try center(red) == 255 && (try center(green)) == 0)
        #expect(session.channelImage(.composite, maxSide: 20)?.width == 20)
    }

    /// Through the canvas itself: P picks the Pen, clicks make anchors, Return ends the path, Shift-A picks Path
    /// Selection and a drag moves the path.
    @Test func penAndPathSelectionThroughTheCanvas() throws {
        let session = session(width: 400, height: 300)
        let view = CanvasView(session: session)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        session.viewport.resize(to: view.bounds.size, backingScale: 1, documentSize: try #require(session.document?.size))
        view.synchronizeDisplay()
        let size = try #require(session.document?.size)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            let spot = session.viewport.viewPoint(from: point, documentSize: size)
            return try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: spot.x, y: view.bounds.height - spot.y),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                                          context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
        view.keyDown(with: try key("p", code: 35))
        #expect(session.tool == .pen)
        for point in [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100)] {
            view.mouseDown(with: try mouse(.leftMouseDown, point))
            view.mouseUp(with: try mouse(.leftMouseUp, point))
        }
        view.keyDown(with: try key("\r", code: 36))
        #expect(session.penDraft == nil && session.activePath?.contours[0].anchors.count == 2)
        view.keyDown(with: try key("A", code: 0, flags: .shift))
        #expect(session.tool == .pathSelection && session.pathSelectionKind == .path)
        view.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 150, y: 100)))
        view.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 150, y: 140)))
        view.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 150, y: 140)))
        let points = try #require(session.activePath?.contours[0].anchors.map(\.point))
        #expect(points.count == 2 && abs(points[0].y - 140) < 1 && abs(points[1].y - 140) < 1, "\(points)")
        view.keyDown(with: try key("A", code: 0, flags: .shift))
        #expect(session.pathSelectionKind == .direct, "Shift-A again switches to Direct Selection")
    }
}
