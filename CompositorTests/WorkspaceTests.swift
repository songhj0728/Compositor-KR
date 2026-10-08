import AppKit
import Testing
@testable import Compositor

/// Window ▸ Workspace: the stored layouts, the floating panel windows, and Command switching the path selection tools.
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

    /// Floating the tools and the side panel puts them in windows of their own; turning it off (or closing them)
    /// docks them again. Uses the shared workspace, put back afterwards.
    @Test func floatingPanelsOpenAndDockAgain() throws {
        let manager = WorkspaceManager.shared
        let before = manager.layout
        defer {
            manager.layout = before
            WorkspaceWindows.shared.closeAll()
        }
        let session = EditorSession()
        session.createNewProject(width: 100, height: 100)
        func window(_ name: String) -> NSWindow? { NSApp.windows.first { $0.identifier?.rawValue == "workspace.\(name)" } }
        manager.layout.floatsTools = true
        manager.layout.floatsSidePanel = true
        WorkspaceWindows.shared.update(session: session, canvasOnly: false)
        #expect(window("tools")?.isVisible == true && window("sidePanel")?.isVisible == true)
        // Canvas Only hides them; closing one docks it.
        WorkspaceWindows.shared.update(session: session, canvasOnly: true)
        #expect(window("tools")?.isVisible != true)
        WorkspaceWindows.shared.update(session: session, canvasOnly: false)
        let tools = try #require(window("tools"))
        tools.performClose(nil)
        #expect(!manager.layout.floatsTools && !tools.isVisible)
        #expect(manager.layout.floatsSidePanel)
    }
}
