import AppKit
import SwiftUI

// The Apple layer of the workspace (Core/WorkspaceLayout.swift): it keeps the layout in UserDefaults, lets the tool
// rail and the side panel be dragged out over the canvas and docked again, and offers the Window ▸ Workspace menu and
// the Settings section.

/// The workspace in use and the saved ones, kept across launches.
@MainActor @Observable
final class WorkspaceManager {
    static let shared = MainActor.assumeIsolated { WorkspaceManager(defaults: .standard) }
    private(set) var library: WorkspaceLibrary
    @ObservationIgnored private let defaults: UserDefaults
    static let key = "workspace.library"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        var library = WorkspaceLibrary.decoded(defaults.data(forKey: Self.key))
        // Before workspaces, only the side panel's width was remembered.
        if defaults.data(forKey: Self.key) == nil, defaults.object(forKey: "layersPanelWidth") != nil {
            library.current.sidePanelWidth = defaults.double(forKey: "layersPanelWidth")
            library.current = library.current.normalized()
        }
        self.library = library
    }

    var layout: WorkspaceLayout {
        get { library.current }
        set {
            let value = newValue.normalized()
            guard value != library.current else { return }
            library.current = value
            persist()
        }
    }

    /// Reset Workspace: everything back where it started, dialogs' remembered places included.
    func reset() {
        library.reset()
        persist()
        FloatingPanelController.forgetPositions()
    }

    @discardableResult
    func save(as name: String) -> Bool {
        let saved = library.save(as: name)
        if saved { persist() }
        return saved
    }

    func choose(_ name: String) {
        if library.choose(name) { persist() }
    }

    func delete(_ name: String) {
        library.delete(name)
        persist()
    }

    /// Asks for a name and saves the current layout under it.
    func promptToSave() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Save Workspace")
        alert.informativeText = String(localized: "The panels' places, the tab order and the tool icon size are saved under this name.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = library.activeName ?? String(localized: "My Workspace")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if !save(as: field.stringValue) { NSSound.beep() }
    }

    private func persist() {
        if let data = library.encoded() { defaults.set(data, forKey: Self.key) }
    }
}

// MARK: - Panels that move around the editor

/// The editor's middle: the tool rail, the canvas and the side panel, docked along the edges or floating over the
/// canvas. Each panel has a grab bar on top; dragging it lifts the panel out, and letting go near its edge docks it
/// again, the edge lighting up while it would.
struct WorkspaceEditorArea<Canvas: View>: View {
    @Bindable var session: EditorSession
    /// Canvas Only: just the canvas.
    var hidesPanels: Bool
    @ViewBuilder var canvas: Canvas
    private var manager: WorkspaceManager { .shared }
    @State private var size: CGSize = .zero
    @State private var drag: PanelDrag?
    static var space: String { "workspaceEditorArea" }

    typealias Panel = WorkspacePanel
    private struct PanelDrag {
        var panel: Panel
        /// Where the pointer took hold, from the panel's top-left corner.
        var grab: CGSize
        var origin: CGPoint
    }

    var body: some View {
        let layout = manager.layout
        HStack(spacing: 0) {
            if !hidesPanels, !layout.floatsTools, drag?.panel != .tools {
                ToolRail(session: session, grip: grip(.tools))
                Divider()
            }
            canvas
            if !hidesPanels, !layout.floatsSidePanel, drag?.panel != .sidePanel {
                PanelResizeEdge(width: Binding(get: { manager.layout.sidePanelWidth }, set: { manager.layout.sidePanelWidth = $0 }),
                                range: LayersPanel.widths)
                LayersPanel(session: session, width: layout.sidePanelWidth, grip: grip(.sidePanel))
            }
        }
        .coordinateSpace(name: Self.space)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .overlay(alignment: .topLeading) {
            if !hidesPanels { floatingPanels }
        }
    }

    @ViewBuilder private var floatingPanels: some View {
        let layout = manager.layout
        ZStack(alignment: .topLeading) {
            // While a drag would dock, the edge it docks to lights up.
            if let drag, wouldDock(drag) {
                Rectangle().fill(Color.accentColor.opacity(0.35))
                    .frame(width: 6, height: size.height)
                    .offset(x: drag.panel == .tools ? 0 : size.width - 6)
                    .allowsHitTesting(false)
            }
            if layout.floatsTools || drag?.panel == .tools {
                let origin = self.origin(.tools)
                ToolRail(session: session, scrolls: false, grip: grip(.tools))
                    .floatingPanelChrome()
                    .offset(x: origin.x, y: origin.y)
            }
            if layout.floatsSidePanel || drag?.panel == .sidePanel {
                let origin = self.origin(.sidePanel)
                LayersPanel(session: session, width: layout.sidePanelWidth, grip: grip(.sidePanel))
                    .frame(height: floatingSidePanelHeight)
                    .floatingPanelChrome()
                    .offset(x: origin.x, y: origin.y)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var floatingSidePanelHeight: CGFloat {
        let stored = manager.layout.sidePanelFrame?.height ?? 520
        return max(260, min(CGFloat(stored), size.height - 16))
    }

    private func panelSize(_ panel: Panel) -> CGSize {
        switch panel {
        case .tools: CGSize(width: manager.layout.toolIconSize.railWidth, height: min(size.height, 640))
        case .sidePanel: CGSize(width: manager.layout.sidePanelWidth, height: floatingSidePanelHeight)
        }
    }

    /// Where a panel's top-left corner is now: following the pointer while dragged, where it was left while floating,
    /// or its docked place.
    private func origin(_ panel: Panel) -> CGPoint {
        if let drag, drag.panel == panel { return drag.origin }
        let layout = manager.layout
        let floats = panel == .tools ? layout.floatsTools : layout.floatsSidePanel
        let stored = panel == .tools ? layout.toolsFrame : layout.sidePanelFrame
        let docked = panel == .tools ? CGPoint.zero : CGPoint(x: size.width - layout.sidePanelWidth, y: 0)
        guard floats, let stored else { return floats ? CGPoint(x: docked.x + (panel == .tools ? 24 : -24), y: 24) : docked }
        let kept = WorkspaceDocking.clamped(stored, editorWidth: size.width, height: size.height)
        return CGPoint(x: kept.x, y: kept.y)
    }

    private func wouldDock(_ drag: PanelDrag) -> Bool {
        manager.layout.wouldDock(drag.panel, x: drag.origin.x, editorWidth: size.width)
    }

    private func grip(_ panel: Panel) -> PanelGrip {
        PanelGrip(space: Self.space, onChanged: { value in
            if drag == nil {
                let origin = self.origin(panel)
                drag = PanelDrag(panel: panel, grab: CGSize(width: value.startLocation.x - origin.x, height: value.startLocation.y - origin.y),
                                 origin: origin)
            }
            guard let current = drag else { return }
            drag?.origin = CGPoint(x: value.location.x - current.grab.width, y: value.location.y - current.grab.height)
        }, onEnded: {
            guard let drag else { return }
            let size = panelSize(panel)
            manager.layout.drop(panel, x: drag.origin.x, y: drag.origin.y, width: size.width, height: size.height,
                                editorWidth: self.size.width, editorHeight: self.size.height)
            self.drag = nil
        })
    }
}

/// The small bar along the top of a movable panel: drag it to move the panel.
struct PanelGrip: View {
    var space: String
    var onChanged: (DragGesture.Value) -> Void
    var onEnded: () -> Void

    var body: some View {
        Capsule().fill(Color.secondary.opacity(0.55))
            .frame(width: 22, height: 4)
            .frame(maxWidth: .infinity, minHeight: 12)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
                .onChanged(onChanged)
                .onEnded { _ in onEnded() })
            .help("Drag to move this panel; let go by its edge to dock it again")
            .accessibilityLabel("Move panel")
    }
}

extension View {
    /// A panel floating over the canvas: its own background, a rounded edge and a shadow.
    func floatingPanelChrome() -> some View {
        background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12)) }
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
    }
}

extension PanelFrame {
    init(_ rect: CGRect) { self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }
}

// MARK: - Tool rail

/// The tools down the editor's left edge, or floating over the canvas. Their size follows the workspace.
struct ToolRail: View {
    @Bindable var session: EditorSession
    /// Docked, the rail scrolls when the window is too short for every tool; floating, it shows them all.
    var scrolls = true
    var grip: PanelGrip? = nil
    private var size: ToolIconSize { WorkspaceManager.shared.layout.toolIconSize }

    var body: some View {
        VStack(spacing: 0) {
            if let grip { grip.padding(.top, 2) }
            if scrolls {
                IndicatorlessScrollView { tools }
            } else {
                tools
            }
        }
        .frame(width: CGFloat(size.railWidth))
    }

    private var tools: some View {
        let side = CGFloat(size.button), glyph = CGFloat(size.glyph)
        let custom = side / 2
        return VStack(spacing: CGFloat(size.spacing)) {
            ForEach(NavigationTool.allCases.filter { $0 != .idle }, id: \.self) { tool in
                Button { session.selectTool(tool) } label: {
                    Group {
                        if tool == .gradient { GradientToolIcon().frame(width: custom, height: custom) }
                        else if tool == .cloneStamp { CloneStampToolIcon().frame(width: custom, height: custom) }
                        else if tool == .lasso, session.lassoKind == .polygonal { PolygonalLassoToolIcon().frame(width: custom, height: custom) }
                        else if tool == .wand, session.wandMode == .object { ObjectSelectionToolIcon().frame(width: custom, height: custom) }
                        else if tool == .pathSelection {
                            PathSelectionToolIcon(direct: session.effectivePathSelectionKind == .direct).frame(width: custom, height: custom)
                        }
                        // The Marquee's icon follows its shape: a dashed circle in Ellipse mode.
                        else {
                            Image(systemName: tool == .marquee && session.marqueeKind == .ellipse ? "circle.dashed" : session.symbol(for: tool))
                                .font(.system(size: glyph))
                        }
                    }
                    .frame(width: side, height: side)
                    .background(session.tool == tool ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: side / 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: side / 5)
                            .strokeBorder(session.tool == tool ? Color.white.opacity(0.14) : .clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(tool.label).accessibilityLabel(tool.label)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(session.tool == tool ? .isSelected : [])
            }
            ColorPaletteControls(session: session).padding(.top, 6)
        }
        .padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Menu and Settings

/// Window ▸ Workspace.
struct WorkspaceMenu: View {
    var manager = WorkspaceManager.shared

    var body: some View {
        Menu("Workspace") {
            ForEach(manager.library.saved, id: \.name) { workspace in
                Toggle(workspace.name, isOn: Binding(get: { manager.library.activeName == workspace.name },
                                                     set: { _ in manager.choose(workspace.name) }))
            }
            if !manager.library.saved.isEmpty { Divider() }
            Button("Reset Workspace") { manager.reset() }
            Button("Save Workspace…") { manager.promptToSave() }
            if !manager.library.saved.isEmpty {
                Menu("Delete Workspace") {
                    ForEach(manager.library.saved, id: \.name) { workspace in
                        Button(workspace.name) { manager.delete(workspace.name) }
                    }
                }
            }
        }
    }
}

/// Settings ▸ Workspace: how the panels sit and how big the tools are.
struct WorkspaceSettingsSection: View {
    var manager = WorkspaceManager.shared

    var body: some View {
        GroupBox("Workspace") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Tool Icons", selection: Binding(get: { manager.layout.toolIconSize }, set: { manager.layout.toolIconSize = $0 })) {
                    ForEach(ToolIconSize.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Tab order").foregroundStyle(.secondary)
                    Text(manager.layout.tabOrder.map { String(localized: $0.title) }.joined(separator: " · "))
                }
                .font(.callout)
                Text("Drag the bar on top of the tools or the Layers panel to move it over the canvas; let go by its edge to dock it again. Drag a tab to change the order.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Picker("Saved", selection: Binding(get: { manager.library.activeName ?? "" },
                                                       set: { if !$0.isEmpty { manager.choose($0) } })) {
                        Text("—").tag("")
                        ForEach(manager.library.saved, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    .frame(maxWidth: 220)
                    Button("Save…") { manager.promptToSave() }
                    Button("Delete") { if let name = manager.library.activeName { manager.delete(name) } }
                        .disabled(manager.library.activeName == nil)
                    Spacer()
                    Button("Reset") { manager.reset() }
                        .help("Put every panel, tab and size back as it was when the app was new")
                }
            }.padding(6)
        }
    }
}

extension ToolIconSize {
    var label: LocalizedStringKey {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

extension SidePanelTab {
    var title: String.LocalizationValue {
        switch self {
        case .layers: "Layers"
        case .channels: "Channels"
        case .paths: "Paths"
        }
    }
}
