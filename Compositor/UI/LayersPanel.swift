import SwiftUI

struct LayersPanel: View {
    @Bindable var session: EditorSession
    /// Dragging the panel's left edge sets it, within `widths`.
    var width: CGFloat = 252
    static let widths: ClosedRange<Double> = 202...352

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compositor-KR: Layers, Paths and Channels share the panel as tabs, as in Photoshop.
            HStack(spacing: 8) {
                SidePanelTabs(session: session)
                if session.sidePanelTab == .layers {
                    Text("\(session.document?.layers.count ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                        .accessibilityIdentifier("layerCount")
                }
            }.padding(.horizontal, 12).padding(.vertical, 12)
            Divider()
            switch session.sidePanelTab {
            case .layers: layersContent
            case .paths: PathsPanelContent(session: session)
            case .channels: ChannelsPanelContent(session: session)
            }
        }
        .frame(width: width)
        .task(id: session.adjustmentEditingID) {
            if let id = session.adjustmentEditingID { await session.beginAdjustmentEditing(id) }
        }
    }

    /// The Layers tab: blending, lock, the layer list and its buttons.
    @ViewBuilder private var layersContent: some View {
        LayerAppearanceControls(session: session, layerID: session.activeLayerID).id(session.activeLayerID)
        HStack {
            Text("Lock").font(.caption)
            Button { session.toggleSelectedLayerLock() } label: {
                Image(systemName: session.selectionContainsLockedLayers ? "lock.fill" : "lock.open")
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Lock or unlock selected layers")
            .accessibilityLabel("Lock or unlock selected layers")
            .disabled(!session.canToggleSelectedLayerLock)
            Spacer()
        }.padding(.horizontal, 12).padding(.bottom, 8)
        Divider()
        if let layers = session.document?.layers, !layers.isEmpty {
            NativeLayerList(session: session)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "square.3.layers.3d").font(.system(size: 25, weight: .light))
                Text("No layers yet").font(.callout.weight(.medium))
                Text(session.document == nil ? "Create a canvas or import an image." : "Import an image or add a blank layer.")
                    .font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary).padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        Divider()
        // No spacing: each button's hit area supplies it (8 pt either side makes the 16 pt gap).
        HStack(spacing: 0) {
            Button { session.addBlankLayer() } label: { Image(systemName: "plus.square").footerHitArea() }
                .help("New blank layer (⇧⌘N)").accessibilityLabel("New blank layer")
                .accessibilityIdentifier("addBlankLayer").disabled(!session.canSelectLayers)
            Button { session.groupSelectedLayers() } label: { Image(systemName: "folder.badge.plus").footerHitArea() }
                .help("Group selected layers (⌘G)").accessibilityLabel("New folder").disabled(!session.canEditLayers)
            LayerMaskMenu(session: session)
            // The icon opens the Layer Style dialog; its arrow lists the styles to add one straight away.
            Menu {
                Button("Blending Options…") { session.openLayerStyle(page: .blending) }
                Divider()
                ForEach(LayerEffectKind.allCases, id: \.self) { kind in
                    Button { session.addEffect(kind) } label: { Text("\(Text(kind.displayName))…") }
                }
            } label: { Image(systemName: "sparkles").footerHitArea() } primaryAction: {
                session.openLayerStyle(page: .blending)
            }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Layer Style: click for the dialog, or pick a style from the arrow").accessibilityLabel("Layer effects")
                .accessibilityIdentifier("layerEffects").disabled(!session.canEditEffects)
            Menu {
                ForEach(AdjustmentKind.allCases, id: \.self) { kind in
                    Button { session.addAdjustment(kind) } label: { Text(kind.displayName) }
                }
            } label: { Image(systemName: "circle.lefthalf.filled").footerHitArea() }
                .menuStyle(.borderlessButton).fixedSize().help("New adjustment layer").disabled(!session.canSelectLayers)
            Spacer()
            Button { session.deleteLayerOrMask() } label: { Image(systemName: "trash").footerHitArea() }
                .help(session.selectedEffect != nil ? "Delete selected effect" : session.isMaskSelected ? "Delete layer mask" : session.selectedLayerIDs.count > 1 ? "Delete selected layers" : "Delete selected layer")
                .accessibilityLabel(session.selectedEffect != nil ? "Delete selected effect" : session.isMaskSelected ? "Delete layer mask" : session.selectedLayerIDs.count > 1 ? "Delete selected layers" : "Delete selected layer")
                .accessibilityIdentifier("deleteLayer")
                .disabled(!session.canEditLayers || session.activeLayer == nil)
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.vertical, 4) // Plus the hit areas' 8 and 12: the original 16.
    }
}

extension View {
    /// Makes a small footer icon easier to click. The padding is the clickable area, so the
    /// footer's own spacing is reduced to match and every icon keeps its old position.
    /// (Negative padding to hand the space back does not work: the button then only answers
    /// clicks inside its shrunken frame.)
    func footerHitArea() -> some View {
        padding(.horizontal, 8).padding(.vertical, 12)
            .contentShape(Rectangle())
    }
}
