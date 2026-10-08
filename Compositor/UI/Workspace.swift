import AppKit
import SwiftUI

// The Apple layer of the workspace (Core/WorkspaceLayout.swift): it keeps the layout in UserDefaults, floats the tool
// rail and the side panel in movable windows of their own, and offers the Window ▸ Workspace menu and the Settings
// section.

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

// MARK: - Floating panel windows

/// The tool rail and the side panel in windows of their own, as Photoshop lets its panels float: moved by their title
/// bars, remembered where they're left, and docked back when closed.
@MainActor
final class WorkspaceWindows: NSObject, NSWindowDelegate {
    static let shared = WorkspaceWindows()
    private enum Kind: String { case tools, sidePanel }
    private var windows: [Kind: NSPanel] = [:]
    /// Which session each window shows, so a project tab switch refills it.
    private var shownSession: [Kind: ObjectIdentifier] = [:]
    private var settingFrame = false

    /// Puts the floating windows in line with the layout, showing `session`.
    func update(session: EditorSession, canvasOnly: Bool) {
        let layout = WorkspaceManager.shared.layout
        sync(.tools, floating: layout.floatsTools && !canvasOnly, session: session, frame: layout.toolsFrame) {
            ToolRail(session: session, scrolls: false)
        }
        sync(.sidePanel, floating: layout.floatsSidePanel && !canvasOnly, session: session, frame: layout.sidePanelFrame) {
            LayersPanel(session: session, width: nil)
        }
    }

    func closeAll() {
        for kind in [Kind.tools, .sidePanel] { hide(kind) }
    }

    private func sync(_ kind: Kind, floating: Bool, session: EditorSession, frame: PanelFrame?, content: () -> some View) {
        guard floating else { hide(kind); return }
        let panel = windows[kind] ?? make(kind)
        if shownSession[kind] != ObjectIdentifier(session) || panel.contentView == nil {
            let host = NSHostingView(rootView: AnyView(content()
                .roundedControls()
                .preferredColorScheme(AppSettings.shared.colorScheme.colorScheme)
                .tint(AppSettings.shared.accentColor.color)))
            host.autoresizingMask = [.width, .height]
            if kind == .tools { host.sizingOptions = [.intrinsicContentSize] } else { host.sizingOptions = [] }
            panel.contentView = host
            shownSession[kind] = ObjectIdentifier(session)
        }
        if !panel.isVisible {
            settingFrame = true
            // Where it was left, unless that's off every screen now (a display unplugged).
            if let frame, frame.isUsable, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame.rect) }) {
                panel.setFrame(frame.rect, display: false)
            } else {
                place(kind, panel: panel)
            }
            settingFrame = false
            panel.orderFront(nil)
        }
    }

    private func hide(_ kind: Kind) {
        guard let panel = windows[kind], panel.isVisible else { return }
        settingFrame = true
        panel.orderOut(nil)
        settingFrame = false
    }

    private func make(_ kind: Kind) -> NSPanel {
        var style: NSWindow.StyleMask = [.titled, .closable, .utilityWindow, .nonactivatingPanel]
        if kind == .sidePanel { style.insert(.resizable) }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: kind == .tools ? 60 : 252, height: kind == .tools ? 520 : 560),
                            styleMask: style, backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("workspace.\(kind.rawValue)")
        panel.title = kind == .tools ? String(localized: "Tools") : String(localized: "Layers")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        if kind == .sidePanel {
            panel.minSize = NSSize(width: WorkspaceLayout.sidePanelWidths.lowerBound, height: 260)
            panel.maxSize = NSSize(width: WorkspaceLayout.sidePanelWidths.upperBound, height: 10_000)
        }
        panel.delegate = self
        windows[kind] = panel
        return panel
    }

    /// Where a panel floats the first time: inside the editor window, near the edge it docks to.
    private func place(_ kind: Kind, panel: NSPanel) {
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible }) else { panel.center(); return }
        let frame = window.frame
        let size = kind == .tools ? panel.frame.size : NSSize(width: WorkspaceLayout.shared.sidePanelWidth, height: min(620, frame.height - 120))
        let origin = kind == .tools
            ? NSPoint(x: frame.minX + 24, y: frame.maxY - 110 - size.height)
            : NSPoint(x: frame.maxX - size.width - 24, y: frame.maxY - 110 - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func kind(of notification: Notification) -> Kind? {
        guard let panel = notification.object as? NSPanel else { return nil }
        return windows.first { $0.value === panel }?.key
    }

    private func remember(_ notification: Notification) {
        guard !settingFrame, let kind = kind(of: notification), let panel = windows[kind], panel.isVisible else { return }
        let frame = PanelFrame(panel.frame)
        var layout = WorkspaceManager.shared.layout
        switch kind {
        case .tools: layout.toolsFrame = frame
        case .sidePanel:
            layout.sidePanelFrame = frame
            layout.sidePanelWidth = frame.width
        }
        WorkspaceManager.shared.layout = layout
    }

    func windowDidMove(_ notification: Notification) { remember(notification) }
    func windowDidEndLiveResize(_ notification: Notification) { remember(notification) }

    /// The close button docks the panel back into the editor window.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let kind = windows.first(where: { $0.value === sender })?.key else { return true }
        var layout = WorkspaceManager.shared.layout
        if kind == .tools { layout.floatsTools = false } else { layout.floatsSidePanel = false }
        WorkspaceManager.shared.layout = layout
        hide(kind)
        return false
    }
}

extension WorkspaceLayout {
    /// The layout in use, for code that only reads it.
    @MainActor static var shared: WorkspaceLayout { WorkspaceManager.shared.layout }
}

extension PanelFrame {
    init(_ rect: NSRect) { self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }
    var rect: NSRect { NSRect(x: x, y: y, width: width, height: height) }
}

// MARK: - Tool rail

/// The tools down the editor's left edge, or in their own floating window. Their size follows the workspace.
struct ToolRail: View {
    @Bindable var session: EditorSession
    /// Docked, the rail scrolls when the window is too short for every tool; floating, its window fits them.
    var scrolls = true
    private var size: ToolIconSize { WorkspaceManager.shared.layout.toolIconSize }

    var body: some View {
        if scrolls {
            IndicatorlessScrollView { tools }.frame(width: size.railWidth)
        } else {
            tools
        }
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
        .padding(.top, 12).padding(.bottom, 10)
        .frame(width: CGFloat(size.railWidth))
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
        Toggle("Float Tools", isOn: Binding(get: { manager.layout.floatsTools }, set: { manager.layout.floatsTools = $0 }))
        Toggle("Float Layers Panel", isOn: Binding(get: { manager.layout.floatsSidePanel }, set: { manager.layout.floatsSidePanel = $0 }))
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
                Toggle("Float the tools in their own window", isOn: Binding(get: { manager.layout.floatsTools },
                                                                            set: { manager.layout.floatsTools = $0 }))
                Toggle("Float the Layers panel in its own window", isOn: Binding(get: { manager.layout.floatsSidePanel },
                                                                                 set: { manager.layout.floatsSidePanel = $0 }))
                HStack {
                    Text("Tab order").foregroundStyle(.secondary)
                    Text(manager.layout.tabOrder.map { String(localized: $0.title) }.joined(separator: " · "))
                }
                .font(.callout)
                Text("Drag a tab in the panel to move it. Floating panels move by their title bars and dock again when closed.")
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
