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

/// A panel drag under way. Only the small views that place panels read it, so moving the pointer redraws a panel's
/// position and nothing else: not the canvas, not the panel's contents.
@MainActor @Observable
final class PanelDragModel {
    /// The panel being dragged, if any.
    private(set) var panel: WorkspacePanel?
    /// Dragged out of its docked place: a light outline follows the pointer and the panel stays put until let go.
    private(set) var fromDock = false
    /// The dragged panel's top-left corner, following the pointer.
    private(set) var origin: CGPoint = .zero
    private(set) var size: CGSize = .zero
    @ObservationIgnored private var grab: CGSize = .zero
    /// The editor area's size, kept up to date by the layout. Read by the floating panels' placement, so they follow a
    /// window resize; the editor itself only writes it.
    var editorSize: CGSize = .zero

    private var manager: WorkspaceManager { .shared }

    /// Where a panel's top-left corner rests when nothing is dragging it.
    func restingOrigin(_ panel: WorkspacePanel) -> CGPoint {
        let layout = manager.layout
        let floats = panel == .tools ? layout.floatsTools : layout.floatsSidePanel
        let docked = panel == .tools ? CGPoint.zero : CGPoint(x: editorSize.width - layout.sidePanelWidth, y: 0)
        guard floats else { return docked }
        guard let stored = panel == .tools ? layout.toolsFrame : layout.sidePanelFrame else {
            return CGPoint(x: panel == .tools ? 24 : editorSize.width - layout.sidePanelWidth - 24, y: 24)
        }
        let kept = WorkspaceDocking.clamped(stored, editorWidth: editorSize.width, height: editorSize.height)
        return CGPoint(x: kept.x, y: kept.y)
    }

    func panelSize(_ panel: WorkspacePanel) -> CGSize {
        let layout = manager.layout
        switch panel {
        case .tools: return CGSize(width: layout.toolIconSize.railWidth, height: min(editorSize.height, 640))
        case .sidePanel:
            let stored = layout.sidePanelFrame?.height ?? 520
            return CGSize(width: layout.sidePanelWidth, height: max(260, min(CGFloat(stored), editorSize.height - 16)))
        }
    }

    /// Whether letting go now would dock the panel: exactly what `end` decides, so the edge lights up only when it will.
    var wouldDock: Bool {
        guard let panel else { return false }
        return manager.layout.wouldDock(panel, x: origin.x, editorWidth: editorSize.width)
    }

    func moved(_ panel: WorkspacePanel, start: CGPoint, location: CGPoint) {
        if self.panel != panel {
            let layout = manager.layout
            let resting = restingOrigin(panel)
            self.panel = panel
            fromDock = !(panel == .tools ? layout.floatsTools : layout.floatsSidePanel)
            size = panelSize(panel)
            grab = CGSize(width: start.x - resting.x, height: start.y - resting.y)
        }
        origin = CGPoint(x: location.x - grab.width, y: location.y - grab.height)
    }

    func ended() {
        guard let panel else { return }
        let size = panelSize(panel)
        manager.layout.drop(panel, x: origin.x, y: origin.y, width: size.width, height: size.height,
                            editorWidth: editorSize.width, editorHeight: editorSize.height)
        self.panel = nil
        fromDock = false
    }
}

/// The editor's middle: the tool rail, the canvas and the side panel, docked along the edges or floating over the
/// canvas. Each panel has a grab bar on top; dragging it moves the panel, and letting go right against its edge docks
/// it again, the edge lighting up when it would.
struct WorkspaceEditorArea<Canvas: View>: View {
    @Bindable var session: EditorSession
    /// Canvas Only: just the canvas.
    var hidesPanels: Bool
    @ViewBuilder var canvas: Canvas
    private var manager: WorkspaceManager { .shared }
    @State private var drag = PanelDragModel()
    static var space: String { "workspaceEditorArea" }

    var body: some View {
        let layout = manager.layout
        // One coordinate space around the docked row and the floating layer alike, so a grab bar reports the same
        // positions wherever its panel is.
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if !hidesPanels, !layout.floatsTools {
                    ToolRail(session: session, grip: PanelGrip(drag: drag, panel: .tools))
                    Divider()
                }
                canvas
                if !hidesPanels, !layout.floatsSidePanel {
                    PanelResizeEdge(width: Binding(get: { manager.layout.sidePanelWidth }, set: { manager.layout.sidePanelWidth = $0 }),
                                    range: LayersPanel.widths)
                    LayersPanel(session: session, width: layout.sidePanelWidth, grip: PanelGrip(drag: drag, panel: .sidePanel))
                }
            }
            if !hidesPanels {
                if layout.floatsTools {
                    PanelPlacement(drag: drag, panel: .tools) {
                        ToolRail(session: session, scrolls: false, grip: PanelGrip(drag: drag, panel: .tools))
                    }
                }
                if layout.floatsSidePanel {
                    PanelPlacement(drag: drag, panel: .sidePanel) {
                        LayersPanel(session: session, width: layout.sidePanelWidth, grip: PanelGrip(drag: drag, panel: .sidePanel))
                    }
                }
                PanelDragFeedback(drag: drag)
            }
        }
        .coordinateSpace(name: Self.space)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { drag.editorSize = $0 }
    }
}

/// A floating panel, placed where it rests or where it's being dragged. Only this reads the drag, so the panel's own
/// contents aren't redrawn as it moves.
private struct PanelPlacement<Content: View>: View {
    var drag: PanelDragModel
    var panel: WorkspacePanel
    @ViewBuilder var content: Content

    var body: some View {
        let moving = drag.panel == panel && !drag.fromDock
        let origin = moving ? drag.origin : drag.restingOrigin(panel)
        let height = drag.panelSize(panel).height
        content
            .frame(height: panel == .sidePanel ? height : nil)
            .floatingPanelChrome()
            .offset(x: origin.x, y: origin.y)
    }
}

/// While a docked panel is dragged out, a light outline of it follows the pointer; while any drag would dock, the edge
/// it docks to lights up.
private struct PanelDragFeedback: View {
    var drag: PanelDragModel

    var body: some View {
        if let panel = drag.panel {
            ZStack(alignment: .topLeading) {
                if drag.wouldDock {
                    Rectangle().fill(Color.accentColor.opacity(0.45))
                        .frame(width: 4, height: drag.editorSize.height)
                        .offset(x: panel == .tools ? 0 : drag.editorSize.width - 4)
                }
                if drag.fromDock {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.5) }
                        .frame(width: drag.size.width, height: drag.size.height)
                        .offset(x: drag.origin.x, y: drag.origin.y)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// The small bar along the top of a movable panel: drag it to move the panel.
struct PanelGrip: View {
    var drag: PanelDragModel
    var panel: WorkspacePanel

    var body: some View {
        Capsule().fill(Color.secondary.opacity(0.55))
            .frame(width: 22, height: 4)
            .frame(maxWidth: .infinity, minHeight: 12)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(WorkspaceEditorArea<EmptyView>.space))
                .onChanged { value in drag.moved(panel, start: value.startLocation, location: value.location) }
                .onEnded { _ in drag.ended() })
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
