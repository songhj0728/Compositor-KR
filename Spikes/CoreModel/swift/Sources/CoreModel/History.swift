/// Undo and redo by keeping whole `Document` values. Documents are values, so each step costs only what changed
/// (copy-on-write) — the approach the macOS app's DocumentHistory takes with its snapshots.
public struct History: Sendable {
    public private(set) var document: Document
    private var undoStack: [(name: String, document: Document)] = []
    private var redoStack: [(name: String, document: Document)] = []
    /// How many steps back undo can go.
    public let limit: Int

    public init(_ document: Document, limit: Int = 100) {
        self.document = document
        self.limit = max(1, limit)
    }

    /// Makes one undoable change. When `change` throws, the document is left as it was and nothing is recorded.
    @discardableResult
    public mutating func perform<Result>(_ name: String, _ change: (inout Document) throws -> Result) rethrows -> Result {
        var edited = document
        let result = try change(&edited)
        guard edited != document else { return result }
        undoStack.append((name, document))
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
        document = edited
        return result
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// What Undo would take back, for its menu item.
    public var undoName: String? { undoStack.last?.name }
    public var redoName: String? { redoStack.last?.name }

    /// Returns the name of the step taken back, or nil when there was none.
    @discardableResult
    public mutating func undo() -> String? {
        guard let step = undoStack.popLast() else { return nil }
        redoStack.append((step.name, document))
        document = step.document
        return step.name
    }

    @discardableResult
    public mutating func redo() -> String? {
        guard let step = redoStack.popLast() else { return nil }
        undoStack.append((step.name, document))
        document = step.document
        return step.name
    }
}
