import AppKit
import SwiftUI
import Testing
@testable import Compositor

/// Window ▸ Workspace: the stored layouts, panels dragged over the canvas and docked again, and Command switching the path
/// selection tools.
@MainActor
struct WorkspaceTests {
    /// A store of its own, so the tests never touch the person's real workspace.
    private func defaults() -> UserDefaults {
        let name = "WorkspaceTests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    @Test func layoutsAreSavedChosenResetAndRememberedAcrossLaunches() {
        let store = defaults()
        let manager = WorkspaceManager(defaults: store)
        #expect(manager.layout == .standard)
        manager.layout.move(.paths, to: .layers)
        manager.layout.toolIconSize = .large
        manager.layout.floatsSidePanel = true
        #expect(manager.save(as: "Retouch"))
        manager.reset()
        #expect(manager.layout == .standard, "Reset puts everything back as it was new")
        #expect(manager.library.saved.map(\.name) == ["Retouch"] && manager.library.activeName == nil)

        let relaunched = WorkspaceManager(defaults: store)
        #expect(relaunched.layout == .standard)
        relaunched.choose("Retouch")
        #expect(relaunched.layout.tabOrder == [.paths, .layers, .channels])
        #expect(relaunched.layout.toolIconSize == .large && relaunched.layout.floatsSidePanel)
        relaunched.delete("Retouch")
        #expect(WorkspaceManager(defaults: store).library.saved.isEmpty)
    }

    @Test func theOldPanelWidthCarriesOver() {
        let store = defaults()
        store.set(300.0, forKey: "layersPanelWidth")
        #expect(WorkspaceManager(defaults: store).layout.sidePanelWidth == 300)
    }

    @Test func smallToolIconsFitEveryToolWithoutScrolling() {
        let size = ToolIconSize.small
        let tools = NavigationTool.allCases.filter { $0 != .idle }.count
        let height = Double(tools) * (size.button + size.spacing)
        #expect(WorkspaceLayout.standard.toolIconSize == .small)
        #expect(height < 640, "\(tools) tools take \(height) points, short enough for a laptop window")
        #expect(size.railWidth < ToolIconSize.large.railWidth)
    }

    @Test func commandHeldSwitchesPathSelectionToDirectSelectionWhileItsDown() throws {
        let session = EditorSession()
        session.createNewProject(width: 200, height: 100)
        session.selectTool(.pen)
        for point in [CGPoint(x: 20, y: 20), CGPoint(x: 120, y: 20)] {
            session.penPress(at: point, tolerance: 4, option: false, shift: false)
            session.pathDragEnded()
        }
        session.selectTool(.pathSelection)
        #expect(session.pathSelectionKind == .path && session.effectivePathSelectionKind == .path)
        session.pathSelectionSwapHeld = true
        #expect(session.effectivePathSelectionKind == .direct)
        // Held: a drag on one anchor moves just that anchor.
        session.pathSelectionPress(at: CGPoint(x: 120, y: 20), tolerance: 4, shift: false, option: false)
        session.pathDragMoved(to: CGPoint(x: 120, y: 60), shift: false)
        session.pathDragEnded()
        #expect(session.activePath?.contours[0].anchors.map(\.point) == [PathVector(20, 20), PathVector(120, 60)])
        // Let go: Path Selection again, and a drag moves the whole path.
        session.pathSelectionSwapHeld = false
        #expect(session.effectivePathSelectionKind == .path && session.pathSelectionKind == .path)
        session.pathSelectionPress(at: CGPoint(x: 20, y: 20), tolerance: 4, shift: false, option: false)
        session.pathDragMoved(to: CGPoint(x: 30, y: 20), shift: false)
        session.pathDragEnded()
        #expect(session.activePath?.contours[0].anchors.map(\.point) == [PathVector(30, 20), PathVector(130, 60)])
        // And the other way round: Direct Selection chosen, Command gives Path Selection.
        session.togglePathSelectionKind()
        session.pathSelectionSwapHeld = true
        #expect(session.effectivePathSelectionKind == .path)
    }

    /// Letting a dragged panel go away from its edge floats it there, kept within reach; letting it go by its edge docks
    /// it again. Stored in the workspace, so it's where it was next launch.
    @Test func draggedPanelsFloatWhereTheyreLeftAndDockByTheirEdges() {
        let store = defaults()
        let manager = WorkspaceManager(defaults: store)
        manager.layout.drop(.tools, x: 300, y: 120, width: 44, height: 600, editorWidth: 1200, editorHeight: 700)
        #expect(manager.layout.floatsTools && manager.layout.toolsFrame == PanelFrame(x: 300, y: 120, width: 44, height: 600),
                "\(String(describing: manager.layout.toolsFrame))")
        manager.layout.drop(.tools, x: 3000, y: 900, width: 44, height: 600, editorWidth: 1200, editorHeight: 700)
        #expect(manager.layout.toolsFrame == PanelFrame(x: 1160, y: 660, width: 44, height: 600), "dragged off the editor, kept within reach")
        manager.layout.drop(.tools, x: 300, y: 120, width: 44, height: 600, editorWidth: 1200, editorHeight: 700)
        manager.layout.drop(.sidePanel, x: 400, y: 40, width: 252, height: 500, editorWidth: 1200, editorHeight: 700)
        #expect(manager.layout.floatsSidePanel && manager.layout.sidePanelFrame?.x == 400)
        #expect(WorkspaceManager(defaults: store).layout.floatsTools, "remembered across launches")
        manager.layout.drop(.tools, x: 20, y: 10, width: 44, height: 600, editorWidth: 1200, editorHeight: 700)
        #expect(!manager.layout.floatsTools, "let go by the left edge, the tools dock")
        manager.layout.drop(.sidePanel, x: 1200 - 252 - 30, y: 10, width: 252, height: 500, editorWidth: 1200, editorHeight: 700)
        #expect(!manager.layout.floatsSidePanel, "let go by the right edge, the panel docks")
        manager.layout.drop(.sidePanel, x: 400, y: 40, width: 252, height: 500, editorWidth: 1200, editorHeight: 700)
        manager.reset()
        #expect(!manager.layout.floatsSidePanel && !manager.layout.floatsTools, "Reset docks everything")
    }

    /// The editor with a floating tool rail: it draws over the canvas rather than beside it.
    @Test func aFloatingRailDrawsOverTheCanvas() throws {
        let manager = WorkspaceManager.shared
        let before = manager.layout
        defer { manager.layout = before }
        let session = EditorSession()
        session.createNewProject(width: 100, height: 100)
        func canvasWidth() throws -> CGFloat {
            var width: CGFloat = 0
            let host = NSHostingView(rootView: WorkspaceEditorArea(session: session, hidesPanels: false) {
                Color.clear.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            }.frame(width: 1000, height: 700))
            host.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
            host.layoutSubtreeIfNeeded()
            return width
        }
        manager.layout.floatsTools = false
        let docked = try canvasWidth()
        manager.layout.drop(.tools, x: 300, y: 50, width: 44, height: 600, editorWidth: 1000, editorHeight: 700)
        let floating = try canvasWidth()
        #expect(floating > docked, "floating, the rail no longer takes room from the canvas (\(docked) → \(floating))")
    }
}
