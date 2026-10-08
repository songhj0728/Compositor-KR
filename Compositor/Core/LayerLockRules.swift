/// Document semantics shared by platform sessions. Identity and hierarchy storage belong to the caller.
nonisolated enum LayerLockRules {
    static func isLocked<ID: Hashable>(_ id: ID, lookup: (ID) -> (locked: Bool, parent: ID?)?) -> Bool {
        var current: ID? = id
        var visited: Set<ID> = []
        while let key = current {
            // Invalid cyclic hierarchy must never make a locked descendant editable.
            guard visited.insert(key).inserted else { return true }
            guard let layer = lookup(key) else { return false }
            if layer.locked { return true }
            current = layer.parent
        }
        return false
    }

    static func toggledValue(_ selectedLocks: [Bool]) -> Bool {
        !selectedLocks.allSatisfy { $0 }
    }
}
