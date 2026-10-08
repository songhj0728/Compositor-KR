import SwiftUI

/// The side panel's tabs over Layers, Channels and Paths, as Photoshop groups them, in the workspace's order. Dragging
/// a tab shows, dimmed, where it would go; where it lands is decided by the other tabs' middles, so it needn't be
/// dropped onto a label, and anywhere past the last tab sends it to the end.
struct SidePanelTabs: View {
    @Bindable var session: EditorSession
    var manager = WorkspaceManager.shared
    /// The tabs' frames when the drag began, so the preview moving them doesn't move the targets.
    @State private var frames: [SidePanelTab: CGRect] = [:]
    @State private var drag: (tab: SidePanelTab, x: CGFloat, grab: CGFloat, start: [SidePanelTab: CGRect])?
    private static let space = "sidePanelTabs"

    private var order: [SidePanelTab] { manager.layout.tabOrder }
    /// Where the dragged tab would land, among the others.
    private var insertion: Int? {
        guard let drag else { return nil }
        let midpoints = order.filter { $0 != drag.tab }.compactMap { drag.start[$0]?.midX }.map(Double.init)
        return WorkspaceDocking.insertionIndex(forX: Double(drag.x), midpoints: midpoints)
    }
    /// The order as it would be after the drop, for the preview.
    private var shownOrder: [SidePanelTab] {
        guard let drag, let insertion else { return order }
        var preview = order.filter { $0 != drag.tab }
        preview.insert(drag.tab, at: min(insertion, preview.count))
        return preview
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(shownOrder, id: \.self) { tab in
                label(tab)
                    // The dragged tab's own slot shows dimmed where it would go.
                    .opacity(drag?.tab == tab ? 0.35 : 1)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                        if drag == nil { frames[tab] = frame }
                    }
                    .onTapGesture { session.sidePanelTab = tab }
                    .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                        .onChanged { value in
                            if drag == nil {
                                let frame = frames[tab] ?? .zero
                                drag = (tab, value.location.x, value.startLocation.x - frame.minX, frames)
                            } else { drag?.x = value.location.x }
                        }
                        .onEnded { _ in
                            if let drag, let insertion { manager.layout.move(drag.tab, toIndex: insertion) }
                            drag = nil
                        })
                    .contextMenu {
                        Button("Move Left") { manager.layout.move(tab, by: -1) }
                            .disabled(order.first == tab)
                        Button("Move Right") { manager.layout.move(tab, by: 1) }
                            .disabled(order.last == tab)
                    }
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.18), value: shownOrder)
        .coordinateSpace(name: Self.space)
        // The tab itself follows the pointer above the strip.
        .overlay(alignment: .leading) {
            if let drag {
                label(drag.tab)
                    .background(Color(white: 0.24), in: RoundedRectangle(cornerRadius: 5))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .offset(x: drag.x - drag.grab)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidePanelTabs")
    }

    private func label(_ tab: SidePanelTab) -> some View {
        let selected = session.sidePanelTab == tab
        return Text(String(localized: tab.title))
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(selected ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Paths

/// The Paths panel: every path in the project, the active one highlighted. Clicking picks the path the Pen and the path
/// selection tools work on; the buttons below make, load and fill paths.
struct PathsPanelContent: View {
    @Bindable var session: EditorSession
    @State private var renaming: UUID?
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if session.paths.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "point.topleft.down.curvedto.point.filled.bottomright.up").font(.system(size: 25, weight: .light))
                    Text("No paths yet").font(.callout.weight(.medium))
                    Text(session.document == nil ? "Create a canvas first." : "Draw one with the Pen (P), or make one from a selection.")
                        .font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary).padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Newest at the top, as the Layers panel lists layers.
                        ForEach(session.paths.reversed()) { path in row(path) }
                    }
                    .padding(6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack(spacing: 0) {
                Button { Task { await session.fillPath() } } label: { Image(systemName: "drop.fill").footerHitArea() }
                    .help("Fill path with the foreground color").accessibilityLabel("Fill path with the foreground color")
                    .disabled(session.activePath?.isEmpty != false || !session.canEditPixels)
                Button { session.loadPathAsSelection() } label: { Image(systemName: "rectangle.dashed").footerHitArea() }
                    .help("Load path as a selection").accessibilityLabel("Load path as a selection")
                    .disabled(session.activePath?.isEmpty != false)
                Button { session.makePathFromSelection() } label: { Image(systemName: "lasso.badge.sparkles").footerHitArea() }
                    .help("Make a path from the selection").accessibilityLabel("Make a path from the selection")
                    .disabled(!session.canMakePathFromSelection)
                Spacer()
                Button { session.newPath() } label: { Image(systemName: "plus.square").footerHitArea() }
                    .help("New path").accessibilityLabel("New path").disabled(!session.canEditPaths)
                    .accessibilityIdentifier("newPath")
                Button { if let id = session.activePathID { session.deletePath(id) } } label: { Image(systemName: "trash").footerHitArea() }
                    .help("Delete path").accessibilityLabel("Delete path").disabled(session.activePathID == nil || !session.canEditPaths)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
    }

    private func row(_ path: VectorPath) -> some View {
        let active = path.id == session.activePathID
        return HStack(spacing: 8) {
            PathThumbnail(path: path, canvas: session.document?.size ?? CGSize(width: 1, height: 1))
                .frame(width: 34, height: 26)
            if renaming == path.id {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.roundedBorder).focused($nameFocused)
                    .onSubmit { commitRename(path.id) }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitRename(path.id) } }
            } else {
                Text(path.name).font(.system(size: 12)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(active ? Color.accentColor.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { startRename(path) }
        .onTapGesture {
            // ⌘-click loads the path as a selection, as in Photoshop.
            if NSEvent.modifierFlags.contains(.command) { session.loadPathAsSelection(path.id) }
            else { session.selectPath(active ? nil : path.id) }
        }
        .contextMenu {
            Button("Rename…") { startRename(path) }
            Button("Duplicate Path") { session.duplicatePath(path.id) }
            Button("Load Path as Selection") { session.loadPathAsSelection(path.id) }
            Button("Fill Path") { session.selectPath(path.id); Task { await session.fillPath(path.id) } }
            Divider()
            Button("Delete Path", role: .destructive) { session.deletePath(path.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func startRename(_ path: VectorPath) {
        draftName = path.name
        renaming = path.id
        nameFocused = true
    }

    private func commitRename(_ id: UUID) {
        guard renaming == id else { return }
        session.renamePath(id, to: draftName)
        renaming = nil
    }
}

/// A path drawn small inside the canvas's shape, for the Paths panel.
struct PathThumbnail: View {
    let path: VectorPath
    let canvas: CGSize

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / max(canvas.width, 1), size.height / max(canvas.height, 1))
            let box = CGRect(x: (size.width - canvas.width * scale) / 2, y: (size.height - canvas.height * scale) / 2,
                             width: canvas.width * scale, height: canvas.height * scale)
            context.fill(Path(box), with: .color(Color(white: 0.85)))
            var transform = CGAffineTransform(translationX: box.minX, y: box.minY).scaledBy(x: scale, y: scale)
            if let shape = path.cgPath.copy(using: &transform) {
                context.fill(Path(shape), with: .color(Color(white: 0.25)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Channels

/// The Channels panel: the composite and each color channel with a thumbnail. Picking a channel shows it alone in gray
/// on the canvas; RGB brings the color back. It views the image and changes nothing in it.
struct ChannelsPanelContent: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            if session.document == nil {
                Text("Create a canvas first.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(ColorChannelView.allCases, id: \.self) { channel in row(channel) }
                    }
                    .padding(6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Viewing a channel changes nothing in the image.")
                    .font(.caption2).foregroundStyle(.tertiary).padding(8)
            }
        }
    }

    private func row(_ channel: ColorChannelView) -> some View {
        let active = session.channelView == channel
        // Read so the thumbnails follow the document.
        _ = session.document
        return HStack(spacing: 8) {
            Group {
                if let image = session.channelImage(channel, maxSide: 96) {
                    Image(decorative: image, scale: 1).resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
                } else { Color(white: 0.3) }
            }
            .frame(width: 40, height: 30)
            .background(Color(white: 0.3))
            Text(channel.title).font(.system(size: 12))
            Spacer()
            Text(channel.shortcut).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(active ? Color.accentColor.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { session.channelView = channel }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
    }
}

extension ColorChannelView {
    var title: LocalizedStringKey {
        switch self {
        case .composite: "RGB"
        case .red: "Red"
        case .green: "Green"
        case .blue: "Blue"
        }
    }
    /// Photoshop's keys for the channels, shown for reference: ⌘2 for the composite, ⌘3–⌘5 for each channel.
    var shortcut: String {
        switch self {
        case .composite: "⌘2"
        case .red: "⌘3"
        case .green: "⌘4"
        case .blue: "⌘5"
        }
    }
}

// MARK: - Tool rail and tool bar

/// Path Selection's icon: a solid arrow for Path Selection, an outlined one for Direct Selection.
struct PathSelectionToolIcon: View {
    var direct: Bool

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 18
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            var arrow = Path()
            arrow.addLines([point(4, 1.5), point(14.5, 11.5), point(9.6, 11.8), point(12.4, 17), point(10.2, 17.6),
                            point(7.6, 12.6), point(4, 16)])
            arrow.closeSubpath()
            if direct {
                context.stroke(arrow, with: .foreground, style: StrokeStyle(lineWidth: 1.4 * unit, lineJoin: .round))
            } else {
                context.fill(arrow, with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The tool bar for the Pen and the path selection tools.
struct PathToolControls: View {
    @Bindable var session: EditorSession

    var body: some View {
        HStack(spacing: 16) {
            if session.tool == .pen {
                Text("Pen").font(ToolHeaderStyle.titleFont)
            } else {
                Picker("Selection", selection: Binding(get: { session.pathSelectionKind }, set: { kind in
                    if kind != session.pathSelectionKind { session.togglePathSelectionKind() }
                })) {
                    Text("Path Selection").tag(PathSelectionKind.path)
                    Text("Direct Selection").tag(PathSelectionKind.direct)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("Path Selection moves whole paths; Direct Selection moves anchor points and handles. Tab or Shift-A switches.")
            }
            Text(session.activePath.map { $0.name } ?? String(localized: "New path on first click"))
                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Make Selection") { session.loadPathAsSelection() }
                .disabled(session.activePath?.isEmpty != false)
            Button("Fill") { Task { await session.fillPath() } }
                .disabled(session.activePath?.isEmpty != false || !session.canEditPixels)
            Button("New Path") { session.newPath() }.disabled(!session.canEditPaths)
        }
        .padding(.horizontal, 18).toolHeaderBar()
    }
}
