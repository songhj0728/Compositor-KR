/// Capture on the existing Mac model's owner context. The caller must supply
/// tokens for this exact state; this adapter does not manage publication/history.
@MainActor
extension CanvasDocument {
    func coreSnapshot(instanceID: DocumentInstanceID, stateID: DocumentStateID,
                      generation: DocumentGeneration) -> CoreDocumentSnapshot {
        CoreDocumentSnapshot(instanceID: instanceID, stateID: stateID, generation: generation,
            layers: layers.map {
                CoreLayerSnapshot(id: $0.id, name: $0.name, isVisible: $0.isVisible, opacity: $0.opacity)
            })
    }
}
