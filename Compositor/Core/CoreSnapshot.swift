import Foundation

/// Identity of an open instance, not the persistent CanvasDocument UUID.
nonisolated struct DocumentInstanceID: Hashable, Sendable {
    let rawValue: UUID
}

/// Committed state identity; undo may restore a previous value. Not a sequence.
nonisolated struct DocumentStateID: Hashable, Sendable {
    let rawValue: UUID
}

/// Instance-local publication sequence, never restored by undo or serialized.
/// The future publisher owns advancement; exhaustion must not wrap to zero.
nonisolated struct DocumentGeneration: Equatable, Sendable {
    let rawValue: UInt64

    func advanced() -> Self? {
        guard rawValue < UInt64.max else { return nil }
        return Self(rawValue: rawValue + 1)
    }
}

/// Own properties only, not effective ancestor/clipping visibility or opacity.
nonisolated struct CoreLayerSnapshot: Equatable, Sendable {
    let id: UUID
    let name: String
    let isVisible: Bool
    let opacity: Double
}

/// Minimal metadata projection, not a complete save or renderer description.
/// Arrays and strings have value semantics; no live model references escape.
nonisolated struct CoreDocumentSnapshot: Equatable, Sendable {
    let instanceID: DocumentInstanceID
    let stateID: DocumentStateID
    let generation: DocumentGeneration
    let layers: [CoreLayerSnapshot] // Existing bottom-to-top storage order.
}

/// Semantic errors only: no ABI codes, localization, or recovery implementation.
nonisolated enum CoreError: Error, Equatable, Sendable {
    case duplicateID(UUID)
    case missingID(UUID)
    case invalidOperation(operation: String)
    case invalidValue(field: String)
    case staleGeneration(expected: DocumentGeneration, actual: DocumentGeneration)
    case internalInvariantViolation(diagnostic: String)

    enum Category: Equatable, Sendable {
        case recoverableDomain
        case fatalInternalInvariant
    }

    var category: Category {
        switch self {
        case .duplicateID, .missingID, .invalidOperation, .invalidValue, .staleGeneration:
            return .recoverableDomain
        case .internalInvariantViolation:
            return .fatalInternalInvariant
        }
    }
}
