import Foundation

// The workspace: how the editor's panels are arranged, and the arrangements saved by name (Window ▸ Workspace).
//
// Platform-neutral on purpose: Foundation only, frames as plain Doubles, persistence as JSON Data, so a Windows port
// keeps the same layouts, the same reset and the same saved workspaces, and only redraws them with its own windows.
// The Apple layer (floating NSPanels, the menu, the Settings section) is UI/Workspace.swift.

/// The side panel's pages, which the user can put in any order.
nonisolated enum SidePanelTab: String, CaseIterable, Codable, Sendable {
    case layers, channels, paths
}

/// How big the tool rail's buttons are.
nonisolated enum ToolIconSize: String, CaseIterable, Codable, Sendable {
    case small, medium, large
    /// The square each tool's button takes, in points.
    var button: Double {
        switch self {
        case .small: 28
        case .medium: 32
        case .large: 36
        }
    }
    /// The symbol's point size inside it.
    var glyph: Double {
        switch self {
        case .small: 14
        case .medium: 15.5
        case .large: 17
        }
    }
    /// The gap between buttons.
    var spacing: Double {
        switch self {
        case .small: 4
        case .medium: 7
        case .large: 10
        }
    }
    /// The rail's width around the buttons.
    var railWidth: Double { button + 16 }
}

/// A window frame in screen points, origin at the bottom left as both macOS and a Windows port can convert it.
nonisolated struct PanelFrame: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isUsable: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width >= 40 && height >= 40 && width <= 100_000 && height <= 100_000
    }
}

/// One arrangement of the editor: which panels float in their own windows and where, the side panel's tab order and
/// width, and the tool icons' size.
nonisolated struct WorkspaceLayout: Codable, Equatable, Sendable {
    var tabOrder: [SidePanelTab] = WorkspaceLayout.defaultTabOrder
    /// The tool rail in a window of its own, instead of along the editor's left edge.
    var floatsTools = false
    /// The Layers / Channels / Paths panel in a window of its own, instead of along the right edge.
    var floatsSidePanel = false
    var toolsFrame: PanelFrame?
    var sidePanelFrame: PanelFrame?
    var sidePanelWidth: Double = WorkspaceLayout.defaultSidePanelWidth
    var toolIconSize: ToolIconSize = .small

    static let defaultTabOrder: [SidePanelTab] = [.layers, .channels, .paths]
    static let defaultSidePanelWidth = 252.0
    static let sidePanelWidths = 202.0...352.0
    /// The arrangement Reset Workspace goes back to: everything docked, in the default order and sizes.
    static let standard = WorkspaceLayout()

    /// Moves `tab` to sit where `target` is, the others shifting to make room, as dragging a tab does.
    mutating func move(_ tab: SidePanelTab, to target: SidePanelTab) {
        guard tab != target, let from = tabOrder.firstIndex(of: tab), let to = tabOrder.firstIndex(of: target) else { return }
        tabOrder.remove(at: from)
        tabOrder.insert(tab, at: to)
    }

    /// Moves `tab` one place left (`by: -1`) or right (`by: 1`).
    mutating func move(_ tab: SidePanelTab, by step: Int) {
        guard let from = tabOrder.firstIndex(of: tab) else { return }
        let to = min(max(from + step, 0), tabOrder.count - 1)
        guard to != from else { return }
        tabOrder.swapAt(from, to)
    }

    /// The layout made safe to use after reading it from disk: every tab exactly once (a newer build's tabs dropped,
    /// missing ones added at the end), frames that make sense, and a width within range.
    func normalized() -> WorkspaceLayout {
        var copy = self
        var seen = Set<SidePanelTab>()
        copy.tabOrder = tabOrder.filter { seen.insert($0).inserted }
        copy.tabOrder += SidePanelTab.allCases.filter { !seen.contains($0) }
        if copy.toolsFrame?.isUsable == false { copy.toolsFrame = nil }
        if copy.sidePanelFrame?.isUsable == false { copy.sidePanelFrame = nil }
        if !sidePanelWidth.isFinite { copy.sidePanelWidth = Self.defaultSidePanelWidth }
        copy.sidePanelWidth = min(max(copy.sidePanelWidth, Self.sidePanelWidths.lowerBound), Self.sidePanelWidths.upperBound)
        return copy
    }

    /// Reads a layout tolerant of fields a newer or older build didn't write.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown tab names (from a newer build) are skipped rather than failing the whole layout.
        let names = (try? values.decode([String].self, forKey: .tabOrder)) ?? []
        tabOrder = names.compactMap(SidePanelTab.init(rawValue:))
        floatsTools = (try? values.decode(Bool.self, forKey: .floatsTools)) ?? false
        floatsSidePanel = (try? values.decode(Bool.self, forKey: .floatsSidePanel)) ?? false
        toolsFrame = try? values.decode(PanelFrame.self, forKey: .toolsFrame)
        sidePanelFrame = try? values.decode(PanelFrame.self, forKey: .sidePanelFrame)
        sidePanelWidth = (try? values.decode(Double.self, forKey: .sidePanelWidth)) ?? Self.defaultSidePanelWidth
        toolIconSize = (try? values.decode(ToolIconSize.self, forKey: .toolIconSize)) ?? .small
        self = normalized()
    }

    init() {}
}

/// A layout kept under a name in Window ▸ Workspace.
nonisolated struct NamedWorkspace: Codable, Equatable, Sendable {
    var name: String
    var layout: WorkspaceLayout
}

/// The layout in use and the saved ones, with the rules for saving, choosing, deleting and resetting them.
nonisolated struct WorkspaceLibrary: Codable, Equatable, Sendable {
    var current = WorkspaceLayout.standard
    var saved: [NamedWorkspace] = []
    /// The saved workspace last chosen or saved, shown checked in the menu; nil once the layout is reset.
    var activeName: String?

    static let maxNameLength = 64
    static let maxSaved = 50

    /// A name as it would be stored: trimmed, and not too long. Nil when nothing is left.
    static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }

    /// Saves the current layout as `name`, replacing a workspace of that name. False for an empty name or a full list.
    @discardableResult
    mutating func save(as name: String) -> Bool {
        guard let name = Self.cleanName(name) else { return false }
        if let index = saved.firstIndex(where: { $0.name == name }) {
            saved[index].layout = current
        } else {
            guard saved.count < Self.maxSaved else { return false }
            saved.append(NamedWorkspace(name: name, layout: current))
        }
        activeName = name
        return true
    }

    /// Switches to the saved workspace `name`.
    @discardableResult
    mutating func choose(_ name: String) -> Bool {
        guard let workspace = saved.first(where: { $0.name == name }) else { return false }
        current = workspace.layout.normalized()
        activeName = name
        return true
    }

    mutating func delete(_ name: String) {
        saved.removeAll { $0.name == name }
        if activeName == name { activeName = nil }
    }

    /// Reset Workspace: the standard layout. Saved workspaces stay, to be chosen again.
    mutating func reset() {
        current = .standard
        activeName = nil
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// The library stored in `data`, or a fresh one when there's none or it can't be read.
    static func decoded(_ data: Data?) -> WorkspaceLibrary {
        guard let data, var library = try? JSONDecoder().decode(WorkspaceLibrary.self, from: data) else { return WorkspaceLibrary() }
        library.current = library.current.normalized()
        library.saved = library.saved.compactMap { item in
            Self.cleanName(item.name).map { NamedWorkspace(name: $0, layout: item.layout.normalized()) }
        }
        if let name = library.activeName, !library.saved.contains(where: { $0.name == name }) { library.activeName = nil }
        return library
    }
}
