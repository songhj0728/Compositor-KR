public enum DocumentError: Error, Equatable {
    case noSuchLayer(LayerID)
    case notAGroup(LayerID)
    /// Grouping needs layers side by side under one parent.
    case notSiblings
    /// A group can't be moved inside itself.
    case wouldContainItself
    case emptySelection
}

/// A canvas and its layer tree. A value: copying one is cheap, and the copies are independent, which is what
/// `History` relies on.
public struct Document: Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// Bottom to top.
    public private(set) var layers: [LayerNode] = []
    private var nextID: UInt64 = 1

    public init(width: Int, height: Int) {
        self.width = width; self.height = height
    }

    // MARK: Adding and removing

    /// Adds a layer on top of `parent` (the document when nil), or at `index` within it.
    @discardableResult
    public mutating func addLayer(named name: String, width: Int? = nil, height: Int? = nil,
                                  in parent: LayerID? = nil, at index: Int? = nil) throws -> LayerID {
        let id = makeID()
        try insert(.layer(Layer(id: id, name: name, width: width ?? self.width, height: height ?? self.height)),
                   in: parent, at: index)
        return id
    }

    @discardableResult
    public mutating func addGroup(named name: String, in parent: LayerID? = nil, at index: Int? = nil) throws -> LayerID {
        let id = makeID()
        try insert(.group(LayerGroup(id: id, name: name)), in: parent, at: index)
        return id
    }

    /// Removes a layer, or a group with everything in it.
    @discardableResult
    public mutating func remove(_ id: LayerID) throws -> LayerNode {
        guard let (parent, index) = location(of: id) else { throw DocumentError.noSuchLayer(id) }
        var removed: LayerNode!
        try editChildren(of: parent) { removed = $0.remove(at: index) }
        return removed
    }

    // MARK: Arranging

    /// Moves `id` into `parent` (the document when nil) at `index`, counted after it has been taken out.
    public mutating func move(_ id: LayerID, to parent: LayerID?, at index: Int) throws {
        if let parent {
            if parent == id { throw DocumentError.wouldContainItself }
            if case .group(let group)? = node(id), Document.contains(group.children, parent) {
                throw DocumentError.wouldContainItself
            }
            guard case .group? = node(parent) else { throw DocumentError.notAGroup(parent) }
        }
        let node = try remove(id)
        try insert(node, in: parent, at: index)
    }

    /// Puts sibling layers into a new group where the topmost of them was. Returns the group.
    @discardableResult
    public mutating func group(_ ids: [LayerID], named name: String) throws -> LayerID {
        guard !ids.isEmpty else { throw DocumentError.emptySelection }
        let locations = try ids.map { id -> (parent: LayerID?, index: Int) in
            guard let spot = location(of: id) else { throw DocumentError.noSuchLayer(id) }
            return spot
        }
        let parent = locations[0].parent
        guard locations.allSatisfy({ $0.parent == parent }) else { throw DocumentError.notSiblings }
        let indices = locations.map(\.index).sorted()
        let groupID = makeID()
        try editChildren(of: parent) { children in
            let members = indices.map { children[$0] }
            for index in indices.reversed() { children.remove(at: index) }
            // Where the topmost member was, less the members that were below it.
            children.insert(.group(LayerGroup(id: groupID, name: name, children: members)),
                            at: indices.last! - (indices.count - 1))
        }
        return groupID
    }

    /// Replaces a group with its contents, in place.
    public mutating func ungroup(_ id: LayerID) throws {
        guard case .group(let group)? = node(id), let (parent, index) = location(of: id) else {
            throw node(id) == nil ? DocumentError.noSuchLayer(id) : DocumentError.notAGroup(id)
        }
        try editChildren(of: parent) { $0.replaceSubrange(index...index, with: group.children) }
    }

    // MARK: Changing

    public mutating func updateLayer(_ id: LayerID, _ change: (inout Layer) -> Void) throws {
        try updateNode(id) { node in
            guard case .layer(var layer) = node else { throw DocumentError.noSuchLayer(id) }
            change(&layer)
            node = .layer(layer)
        }
    }

    public mutating func updateGroup(_ id: LayerID, _ change: (inout LayerGroup) -> Void) throws {
        try updateNode(id) { node in
            guard case .group(var group) = node else { throw DocumentError.notAGroup(id) }
            change(&group)
            node = .group(group)
        }
    }

    // MARK: Reading

    public func node(_ id: LayerID) -> LayerNode? { Document.find(id, in: layers) }

    /// The group `id` is in, nil at the top level; and its index there. Nil when there's no such layer.
    public func location(of id: LayerID) -> (parent: LayerID?, index: Int)? {
        Document.locate(id, in: layers, parent: nil)
    }

    /// The layers that show, bottom to top, each with the opacity it ends up with through its groups.
    public var visibleLayers: [(layer: Layer, opacity: Double)] {
        var result: [(Layer, Double)] = []
        func walk(_ nodes: [LayerNode], _ opacity: Double) {
            for node in nodes where node.isVisible {
                switch node {
                case .layer(let layer): result.append((layer, opacity * layer.opacity))
                case .group(let group): walk(group.children, opacity * group.opacity)
                }
            }
        }
        walk(layers, 1)
        return result
    }

    /// Every node, depth first, top to bottom as a layers panel lists them, with its depth.
    public var outline: [(node: LayerNode, depth: Int)] {
        var result: [(LayerNode, Int)] = []
        func walk(_ nodes: [LayerNode], _ depth: Int) {
            for node in nodes.reversed() {
                result.append((node, depth))
                if case .group(let group) = node { walk(group.children, depth + 1) }
            }
        }
        walk(layers, 0)
        return result
    }

    // MARK: Tree plumbing

    private mutating func makeID() -> LayerID {
        defer { nextID += 1 }
        return LayerID(nextID)
    }

    private mutating func insert(_ node: LayerNode, in parent: LayerID?, at index: Int?) throws {
        try editChildren(of: parent) { children in
            children.insert(node, at: min(max(index ?? children.count, 0), children.count))
        }
    }

    private mutating func editChildren(of parent: LayerID?, _ edit: (inout [LayerNode]) throws -> Void) throws {
        guard let parent else { return try edit(&layers) }
        try updateNode(parent) { node in
            guard case .group(var group) = node else { throw DocumentError.notAGroup(parent) }
            try edit(&group.children)
            node = .group(group)
        }
    }

    private mutating func updateNode(_ id: LayerID, _ change: (inout LayerNode) throws -> Void) throws {
        guard try Document.update(id, in: &layers, change) else { throw DocumentError.noSuchLayer(id) }
    }

    private static func update(_ id: LayerID, in nodes: inout [LayerNode],
                               _ change: (inout LayerNode) throws -> Void) throws -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id {
                try change(&nodes[index])
                return true
            }
            if case .group(var group) = nodes[index], try update(id, in: &group.children, change) {
                nodes[index] = .group(group)
                return true
            }
        }
        return false
    }

    private static func find(_ id: LayerID, in nodes: [LayerNode]) -> LayerNode? {
        for node in nodes {
            if node.id == id { return node }
            if case .group(let group) = node, let found = find(id, in: group.children) { return found }
        }
        return nil
    }

    private static func contains(_ nodes: [LayerNode], _ id: LayerID) -> Bool { find(id, in: nodes) != nil }

    private static func locate(_ id: LayerID, in nodes: [LayerNode], parent: LayerID?) -> (parent: LayerID?, index: Int)? {
        for (index, node) in nodes.enumerated() {
            if node.id == id { return (parent, index) }
            if case .group(let group) = node, let found = locate(id, in: group.children, parent: group.id) {
                return found
            }
        }
        return nil
    }
}
