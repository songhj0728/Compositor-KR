import AppKit
import SwiftUI

/// Filter ▸ Liquify…: the active layer on the left, painted on directly with the chosen tool; the tool and its brush on
/// the right. Preview switches between the result and the layer as it was.
struct LiquifySheet: View {
    @Bindable var session: EditorSession
    @State private var viewport = LiquifyViewport()
    static let canvasSize = CGSize(width: 760, height: 560)

    var body: some View {
        if let edit = session.liquify {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    LiquifyCanvasRepresentable(edit: edit, viewport: viewport, preview: edit.preview, brushSize: edit.brush.size)
                        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .help("Hold Space and drag to move around · scroll or pinch to zoom")
                    // Under the image: the zoom, then at its right, before and after.
                    HStack(spacing: 8) {
                        Text("\(edit.layerName) · \(edit.original.width.formatted()) × \(edit.original.height.formatted()) px")
                            .foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button { viewport.command(.zoomOut) } label: { Image(systemName: "minus.magnifyingglass") }
                            .help("Zoom out (⌘−)")
                        Text("\(viewport.percent)%").monospacedDigit().frame(width: 52)
                        Button { viewport.command(.zoomIn) } label: { Image(systemName: "plus.magnifyingglass") }
                            .help("Zoom in (⌘+)")
                        Button("Fit") { viewport.command(.fit) }
                            .help("Show the whole layer (⌘0)")
                        Toggle("Preview", isOn: Binding(get: { edit.preview }, set: { edit.preview = $0 }))
                            .help("Off shows the layer as it was, to compare")
                            .padding(.leading, 8)
                    }
                    .frame(width: Self.canvasSize.width)
                }
                LiquifyOptions(session: session, edit: edit)
                    .frame(width: 250, height: Self.canvasSize.height + 30)
            }
            .padding(20)
            .fixedSize()
            .disabled(edit.committing)
            // View ▸ Zoom In, Zoom Out, Fit Canvas and Actual Pixels zoom the dialog's image while it is open.
            .onAppear { session.previewZoom = { [viewport] command in viewport.command(command) } }
            .onDisappear { session.previewZoom = nil }
        }
    }
}

/// The dialog's zoom, shared between the canvas and the buttons under it.
@Observable
final class LiquifyViewport {
    /// The zoom now, 100 being one layer pixel per screen pixel.
    var percent = 100
    @ObservationIgnored weak var view: LiquifyCanvasNSView?
    func command(_ command: EditorSession.PreviewZoomCommand) { view?.zoom(command) }
}

/// The tools, the brush, and the dialog's buttons.
private struct LiquifyOptions: View {
    let session: EditorSession
    @Bindable var edit: LiquifyEdit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tools").font(.headline)
            VStack(spacing: 2) {
                ForEach(LiquifyMode.allCases, id: \.self) { mode in
                    Button { edit.mode = mode } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.symbol).frame(width: 20)
                            Text(mode.displayName)
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(edit.mode == mode ? Color.accentColor.opacity(0.25) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            Text("Brush Tool Options").font(.headline)
            row("Size", value: $edit.brush.size, range: LiquifyBrush.sizeRange, unit: "px")
                .help("The brush's diameter in the layer's pixels")
            row("Density", value: $edit.brush.density, range: 0...100, unit: "%")
                .help("How firmly the brush's edge works: low fades out from the center, high is even to the rim")
            row("Pressure", value: $edit.brush.pressure, range: 1...100, unit: "%")
                .help("How far each dab moves the pixels")
            row("Rate", value: $edit.brush.rate, range: 0...100, unit: "%")
                .help("How fast Reconstruct, Twirl, Pucker and Bloat work while the brush is held still")
                .disabled(!edit.mode.worksInPlace)
            Divider()
            LiquifyHistoryButtons(edit: edit)
            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { session.cancelLiquify() }.configuredNativeShortcut(.escape)
                Button("Apply") { Task { await session.commitLiquify() } }
                    .configuredNativeShortcut(.return).buttonStyle(.borderedProminent)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: Binding(get: { value.wrappedValue },
                                                set: { value.wrappedValue = $0.isFinite ? min(range.upperBound, max(range.lowerBound, $0.rounded())) : range.lowerBound }),
                          format: ArithmeticFloatFormatStyle(fractionLength: 0...0))
                    .labelsHidden().frame(width: 56).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                    .unitSuffix(unit)
            }
            Slider(value: value, in: range)
        }
    }
}

/// Undo and Redo for the dialog's strokes, as the two halves of one pill (⌘Z and ⇧⌘Z do the same).
private struct LiquifyHistoryButtons: View {
    let edit: LiquifyEdit

    var body: some View {
        HStack(spacing: 0) {
            half("arrow.uturn.backward", enabled: edit.canUndo, help: "Undo (⌘Z)") { edit.undo() }
            Divider().frame(height: 16)
            half("arrow.uturn.forward", enabled: edit.canRedo, help: "Redo (⇧⌘Z)") { edit.redo() }
        }
        .background(Capsule().fill(.quaternary))
        .overlay(Capsule().strokeBorder(.separator))
    }

    private func half(_ symbol: String, enabled: Bool, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 40, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

private struct LiquifyCanvasRepresentable: NSViewRepresentable {
    let edit: LiquifyEdit
    let viewport: LiquifyViewport
    let preview: Bool
    let brushSize: Double

    func makeNSView(context: Context) -> LiquifyCanvasNSView { LiquifyCanvasNSView(edit: edit, viewport: viewport) }
    func updateNSView(_ view: LiquifyCanvasNSView, context: Context) {
        view.showsPreview = preview
        view.updateBrushOutline()
    }
    /// The panel outlives the dialog; its frame link, and the working copy it holds, shouldn't.
    static func dismantleNSView(_ view: LiquifyCanvasNSView, coordinator: ()) { view.stop() }
}

/// The layer over a transparency checkerboard, with the brush's outline under the pointer. Zooming and moving around
/// only move the image's layer; the pixels are handed over at most once a frame, whatever the number of dabs.
final class LiquifyCanvasNSView: NSView {
    private let edit: LiquifyEdit
    private let viewport: LiquifyViewport
    private let backdrop = CALayer()
    private let imageLayer = CALayer()
    private let brushLayer = CAShapeLayer()
    /// Screen points per layer pixel; nil fits the whole layer.
    private var zoom: CGFloat?
    /// The layer point (top row first) at the middle of the view, once zoomed.
    private var center = CGPoint.zero
    private var spaceHeld = false
    private var panning: (start: NSPoint, center: CGPoint)?
    private var painting = false
    private var pointer: NSPoint?
    private var frameLink: CADisplayLink?
    private var trackingArea: NSTrackingArea?
    private static let percentSteps: [CGFloat] = [5, 10, 25, 33, 50, 66, 100, 200, 300, 400, 800, 1600, 3200]
    var showsPreview = true {
        didSet { if showsPreview != oldValue { imageLayer.contents = showsPreview ? edit.current : edit.before } }
    }

    init(edit: LiquifyEdit, viewport: LiquifyViewport) {
        self.edit = edit
        self.viewport = viewport
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        backdrop.backgroundColor = NSColor(patternImage: Self.checkerboard).cgColor
        imageLayer.contents = edit.current
        imageLayer.contentsGravity = .resize
        brushLayer.fillColor = nil
        brushLayer.strokeColor = NSColor.white.cgColor
        brushLayer.lineWidth = 1
        brushLayer.shadowColor = NSColor.black.cgColor
        brushLayer.shadowOpacity = 1
        brushLayer.shadowRadius = 1
        brushLayer.shadowOffset = .zero
        for sublayer in [backdrop, imageLayer, brushLayer] {
            sublayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "path": NSNull()]
            layer?.addSublayer(sublayer)
        }
        viewport.view = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static let checkerboard = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor(white: 0.22, alpha: 1).setFill(); rect.fill()
        NSColor(white: 0.32, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        NSRect(x: 8, y: 8, width: 8, height: 8).fill()
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        frameLink?.invalidate()
        frameLink = nil
        guard let window else { return }
        let link = displayLink(target: self, selector: #selector(nextFrame))
        link.add(to: .main, forMode: .common)
        frameLink = link
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }

    func stop() {
        frameLink?.invalidate()
        frameLink = nil
        imageLayer.contents = nil
    }

    /// Hands the newest pixels to the image layer, once a frame.
    @objc private func nextFrame() {
        guard let image = edit.takeImage(), showsPreview else { return }
        imageLayer.contents = image
    }

    // MARK: Viewport

    private var layerSize: CGSize { CGSize(width: max(1, edit.original.width), height: max(1, edit.original.height)) }
    private var fitZoom: CGFloat {
        let inset = bounds.insetBy(dx: 8, dy: 8)
        return max(0.0001, min(inset.width / layerSize.width, inset.height / layerSize.height))
    }
    private var shownZoom: CGFloat { zoom ?? fitZoom }
    private var shownCenter: CGPoint { zoom == nil ? CGPoint(x: layerSize.width / 2, y: layerSize.height / 2) : center }
    private var backingScale: CGFloat { window?.backingScaleFactor ?? 2 }
    private var imageFrame: CGRect {
        let z = shownZoom, c = shownCenter
        let width = layerSize.width * z, height = layerSize.height * z
        let top = bounds.midY + c.y * z
        return CGRect(x: bounds.midX - c.x * z, y: top - height, width: width, height: height)
    }
    /// A point in the view as a point in the layer's pixels, top row first.
    private func layerPoint(_ point: NSPoint) -> CGPoint {
        let frame = imageFrame, z = shownZoom
        return CGPoint(x: (point.x - frame.minX) / z, y: (frame.maxY - point.y) / z)
    }

    override func layout() {
        super.layout()
        applyViewport()
    }

    private func applyViewport() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let frame = imageFrame
        backdrop.frame = frame
        imageLayer.frame = frame
        brushLayer.frame = bounds
        // Sharp pixels once each of the dialog's pixels covers two of the screen's.
        imageLayer.magnificationFilter = shownZoom / edit.scale * backingScale >= 2 ? .nearest : .linear
        CATransaction.commit()
        updateBrushOutline()
        let percent = Int((shownZoom * backingScale * 100).rounded())
        if viewport.percent != percent { viewport.percent = percent }
    }

    /// Zooms by `factor`, keeping the layer point under `anchor` (the view's middle by default) where it is.
    private func zoom(by factor: CGFloat, at anchor: NSPoint? = nil) {
        setZoom(shownZoom * factor, at: anchor)
    }
    private func setZoom(_ value: CGFloat, at anchor: NSPoint? = nil) {
        let anchor = anchor ?? NSPoint(x: bounds.midX, y: bounds.midY)
        let fixed = layerPoint(anchor)
        let lowest = min(fitZoom, 0.05 / backingScale), highest = 32 / backingScale
        let z = min(highest, max(lowest, value))
        zoom = z
        center = CGPoint(x: fixed.x - (anchor.x - bounds.midX) / z, y: fixed.y + (anchor.y - bounds.midY) / z)
        clampCenter()
        applyViewport()
    }
    /// Keeps some of the layer in view.
    private func clampCenter() {
        center = CGPoint(x: min(layerSize.width, max(0, center.x)), y: min(layerSize.height, max(0, center.y)))
    }

    func zoom(_ command: EditorSession.PreviewZoomCommand) {
        let percent = shownZoom * backingScale * 100
        switch command {
        case .fit: zoom = nil; applyViewport()
        case .actual: setZoom(1 / backingScale)
        case .zoomIn:
            if let next = Self.percentSteps.first(where: { $0 > percent * 1.001 }) { setZoom(next / 100 / backingScale) }
        case .zoomOut:
            if let next = Self.percentSteps.last(where: { $0 < percent * 0.999 }) { setZoom(next / 100 / backingScale) }
        }
    }

    // MARK: Brush and cursor

    func updateBrushOutline() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let pointer, !spaceHeld, panning == nil, bounds.contains(pointer) {
            let diameter = max(4, edit.brush.size * shownZoom)
            brushLayer.path = CGPath(ellipseIn: CGRect(x: pointer.x - diameter / 2, y: pointer.y - diameter / 2,
                                                        width: diameter, height: diameter), transform: nil)
        } else {
            brushLayer.path = nil
        }
        CATransaction.commit()
    }

    private func updateCursor() {
        guard let pointer, bounds.contains(pointer) else { return }
        (panning != nil ? NSCursor.closedHand : spaceHeld ? NSCursor.openHand : NSCursor.crosshair).set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }
    override func cursorUpdate(with event: NSEvent) { updateCursor() }
    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        updateBrushOutline()
        updateCursor()
    }
    override func mouseExited(with event: NSEvent) {
        guard panning == nil, !painting else { return }
        pointer = nil
        updateBrushOutline()
        NSCursor.arrow.set()
    }

    // MARK: Painting and moving around

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        pointer = point
        if spaceHeld {
            if zoom == nil { zoom = fitZoom; center = shownCenter }
            panning = (point, center)
            updateBrushOutline()
            updateCursor()
            return
        }
        painting = true
        edit.begin(at: layerPoint(point))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointer = point
        if let panning {
            let z = shownZoom
            center = CGPoint(x: panning.center.x - (point.x - panning.start.x) / z,
                             y: panning.center.y + (point.y - panning.start.y) / z)
            clampCenter()
            applyViewport()
            return
        }
        guard painting else { return }
        edit.drag(to: layerPoint(point))
        updateBrushOutline()
    }

    override func mouseUp(with event: NSEvent) {
        panning = nil
        if painting { edit.end(); painting = false }
        updateBrushOutline()
        updateCursor()
    }

    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " " else { super.keyDown(with: event); return }
        if !event.isARepeat {
            spaceHeld = true
            updateBrushOutline()
            updateCursor()
        }
    }

    override func keyUp(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " " else { super.keyUp(with: event); return }
        spaceHeld = false
        updateBrushOutline()
        updateCursor()
    }

    override func resignFirstResponder() -> Bool {
        spaceHeld = false
        updateBrushOutline()
        return super.resignFirstResponder()
    }

    /// Trackpad scrolling moves around; a mouse wheel, or scrolling with Option or Command, zooms at the pointer.
    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !event.hasPreciseScrollingDeltas || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
            zoom(by: exp(step), at: point)
            return
        }
        if zoom == nil { zoom = fitZoom; center = shownCenter }
        let z = shownZoom
        center = CGPoint(x: center.x - event.scrollingDeltaX / z, y: center.y - event.scrollingDeltaY / z)
        clampCenter()
        applyViewport()
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil))
    }
}
