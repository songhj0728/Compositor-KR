/// Identifies a layer or group for the life of a document. Plain integers rather than Foundation's UUID, so the Core
/// needs nothing beyond the Swift standard library.
public struct LayerID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64
    public init(_ rawValue: UInt64) { self.rawValue = rawValue }
    public static func < (lhs: LayerID, rhs: LayerID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { "#\(rawValue)" }
}

public enum BlendMode: String, CaseIterable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten
}

/// A layer with pixels. The pixels themselves aren't modeled in this spike; `width` × `height` stands in for them.
public struct Layer: Equatable, Sendable {
    public let id: LayerID
    public var name: String
    public var isVisible = true
    public var opacity = 1.0
    public var blendMode = BlendMode.normal
    public var transform = Transform.identity
    public var width: Int
    public var height: Int

    public init(id: LayerID, name: String, width: Int, height: Int) {
        self.id = id; self.name = name; self.width = width; self.height = height
    }
}

/// Layers and groups inside a group, bottom to top.
public struct LayerGroup: Equatable, Sendable {
    public let id: LayerID
    public var name: String
    public var isVisible = true
    public var opacity = 1.0
    public var isExpanded = true
    public var children: [LayerNode]

    public init(id: LayerID, name: String, children: [LayerNode] = []) {
        self.id = id; self.name = name; self.children = children
    }
}

/// One entry in the layer tree.
public enum LayerNode: Equatable, Sendable {
    case layer(Layer)
    case group(LayerGroup)

    public var id: LayerID {
        switch self {
        case .layer(let layer): layer.id
        case .group(let group): group.id
        }
    }

    public var name: String {
        switch self {
        case .layer(let layer): layer.name
        case .group(let group): group.name
        }
    }

    public var isVisible: Bool {
        switch self {
        case .layer(let layer): layer.isVisible
        case .group(let group): group.isVisible
        }
    }
}
