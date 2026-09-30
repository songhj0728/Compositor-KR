import Foundation
import CoreGraphics
import Testing
@testable import Compositor

@MainActor
struct CoreSnapshotTests {
    @Test func realDocumentProjectsBulkValuesAndRetainsThem() {
        var bottom = ImageLayer(name: "아래", blankSize: CGSize(width: 8, height: 8))
        bottom.opacity = 0.25
        var top = ImageLayer(name: "위", blankSize: CGSize(width: 8, height: 8))
        top.isVisible = false
        var document = CanvasDocument(width: 8, height: 8, layers: [bottom, top])
        let instance = DocumentInstanceID(rawValue: UUID())
        let state = DocumentStateID(rawValue: UUID())
        let generation = DocumentGeneration(rawValue: 7)
        let snapshot = document.coreSnapshot(instanceID: instance, stateID: state, generation: generation)
        #expect(snapshot.instanceID == instance && snapshot.stateID == state && snapshot.generation == generation)
        #expect(snapshot.layers.map(\.id) == document.layers.map(\.id))
        for (row, layer) in zip(snapshot.layers, document.layers) {
            #expect(row.name == layer.name && row.isVisible == layer.isVisible && row.opacity == layer.opacity)
        }
        document.layers[0].name = "changed"
        document.layers[0].isVisible = false
        document.layers[0].opacity = 0.9
        document.layers.reverse()
        document.layers.removeLast()
        #expect(snapshot.layers.map(\.id) == [bottom.id, top.id])
        #expect(snapshot.layers[0].name == "아래")
        #expect(snapshot.layers[0].isVisible && snapshot.layers[0].opacity == 0.25)
        #expect(snapshot.layers[1].name == "위" && !snapshot.layers[1].isVisible)
    }

    @Test func emptyDocumentHasEmptyBulkCollection() {
        let snapshot = CanvasDocument(width: 1, height: 1).coreSnapshot(
            instanceID: DocumentInstanceID(rawValue: UUID()),
            stateID: DocumentStateID(rawValue: UUID()), generation: DocumentGeneration(rawValue: 0))
        #expect(snapshot.layers.isEmpty)
    }

    @Test func stateRestorationDoesNotRestorePublicationGeneration() throws {
        let a = DocumentStateID(rawValue: UUID())
        let b = DocumentStateID(rawValue: UUID())
        let first = DocumentGeneration(rawValue: 0)
        let second = try #require(first.advanced())
        let third = try #require(second.advanced())
        let states = [a, b, a] // Fixture trace, not a new history implementation.
        #expect(states[0] == states[2] && states[0] != states[1])
        #expect([first.rawValue, second.rawValue, third.rawValue] == [0, 1, 2])
        #expect(first != third)
        #expect(DocumentGeneration(rawValue: UInt64.max).advanced() == nil)
    }

    @Test func errorsKeepPayloadAndSeparateFatalInvariants() {
        let id = UUID()
        let old = DocumentGeneration(rawValue: 2)
        let new = DocumentGeneration(rawValue: 3)
        let errors: [CoreError] = [.duplicateID(id), .missingID(id),
            .invalidOperation(operation: "reorder"), .invalidValue(field: "opacity"),
            .staleGeneration(expected: old, actual: new)]
        #expect(errors.allSatisfy { $0.category == .recoverableDomain })
        #expect(CoreError.duplicateID(id) != .missingID(id))
        #expect(CoreError.staleGeneration(expected: old, actual: new) != .staleGeneration(expected: new, actual: old))
        #expect(CoreError.internalInvariantViolation(diagnostic: "broken state").category == .fatalInternalInvariant)
    }
}
