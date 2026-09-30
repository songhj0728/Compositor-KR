import SwiftUI

struct ShapeControls: View {
    @Bindable var session: EditorSession

    var body: some View {
        HStack(spacing: 12) {
            Text("Shape").font(ToolHeaderStyle.titleFont)
            Picker("Shape", selection: Binding(get: { session.shapeKind }, set: { kind in
                session.cancelShape()
                session.shapeKind = kind
            })) {
                ForEach(ShapeKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("Shift-U (or Tab) steps through Rectangle, Ellipse and Line")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    if lineShown {
                        HStack(spacing: 6) {
                            Text("Width")
                            TextField("Width", value: Binding(get: { session.shapeBarLineWidth },
                                                              set: { session.setShapeLineWidth($0) }),
                                      format: ArithmeticFloatFormatStyle(fractionLength: 0...0))
                                .frame(width: 48).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                                .arrowSteps(value: { session.shapeBarLineWidth },
                                            change: { session.setShapeLineWidth($0) })
                                .unitSuffix("px")
                        }
                        .help("The line's thickness")
                    }
                    if session.shapeKind == .rectangle, session.activeShape == nil || session.activeShape?.style.kind == .rectangle {
                        HStack(spacing: 6) {
                            Text("Radius").scrubbable(sensitivity: 1, value: $session.shapeCornerRadius, range: 0...5000)
                            Slider(value: Binding(get: { min(200, session.shapeCornerRadius) },
                                                  set: { session.shapeCornerRadius = $0.rounded() }), in: 0...200)
                                .frame(width: 80)
                            TextField("Radius", value: Binding(get: { session.shapeCornerRadius },
                                                               set: { session.shapeCornerRadius = $0.isFinite ? min(5000, max(0, $0)) : 0 }),
                                      format: ArithmeticFloatFormatStyle(fractionLength: 0...0))
                                .frame(width: 48).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                                .arrowSteps(value: { Double(session.shapeCornerRadius) },
                                            change: { session.shapeCornerRadius = min(5000, max(0, CGFloat($0))) })
                                .unitSuffix("px")
                        }
                        .help("Round the rectangle's corners by this many pixels; 0 keeps them square")
                    }
                    HStack(spacing: 6) {
                        if lineShown {
                            Text("Color")
                        } else {
                            Toggle("Fill", isOn: Binding(get: { session.shapeBarFills }, set: { session.setShapeFills($0) }))
                                .toggleStyle(.checkbox)
                                .help("Fill the inside of the shape")
                        }
                        swatch(session.shapeBarFill, stroke: false)
                            .help(lineShown ? "The line's color. With a line selected, it changes that line too."
                                            : "The shape's fill. With a shape selected, it changes that shape too.")
                            .accessibilityLabel(lineShown ? "Line color" : "Fill color")
                    }
                    if !lineShown {
                        HStack(spacing: 6) {
                            Text("Stroke")
                            swatch(session.shapeBarStroke, stroke: true)
                                .help("The outline's color. With a shape selected, it changes that shape too.")
                                .accessibilityLabel("Stroke color")
                            TextField("Stroke", value: Binding(get: { session.shapeBarStrokeWidth },
                                                               set: { session.setShapeStrokeWidth($0) }),
                                      format: ArithmeticFloatFormatStyle(fractionLength: 0...0))
                                .frame(width: 44).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                                .arrowSteps(value: { session.shapeBarStrokeWidth },
                                            change: { session.setShapeStrokeWidth($0) })
                                .unitSuffix("px")
                                .help("The outline's thickness, drawn just inside the edge; 0 draws none")
                        }
                    }
                    Divider().frame(height: 18)
                    // The selected layer's size, scale and angle: typed here, or dragged by its handles with Move (V).
                    TransformSizeFields(session: session)
                }
                .padding(.horizontal, 2)
            }.scrollIndicators(.hidden)
            TransformPendingButtons(session: session)
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy || session.document == nil)
    }

    /// Line settings show for the Line shape, or while a line is selected.
    private var lineShown: Bool {
        session.activeShape.map { $0.style.kind == .line } ?? (session.shapeKind == .line)
    }

    private func swatch(_ color: PaletteColor, stroke: Bool) -> some View {
        Button { session.openShapeColorPicker(stroke: stroke) } label: {
            let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
            shape.fill(Color(nsColor: color.nsColor))
                .overlay { shape.strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                .frame(width: 36, height: 18)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

/// Asked for by a click with the Shape tool: the shape's width and height in pixels, and whether it goes in the middle
/// of the canvas (From Center) or around the click.
struct ShapeSizeSheet: View {
    let session: EditorSession
    let request: ShapeSizeRequest
    @State private var width: String
    @State private var height: String
    @State private var fromCenter: Bool
    @FocusState private var focused: Bool

    init(session: EditorSession, request: ShapeSizeRequest) {
        self.session = session
        self.request = request
        _width = State(initialValue: String(session.shapeSizeWidth))
        _height = State(initialValue: String(session.shapeSizeHeight))
        _fromCenter = State(initialValue: session.shapeSizeFromCenter)
    }

    /// A line may be flat or upright (0 on one side); other shapes need at least a pixel each way.
    private var smallest: Int { request.kind == .line ? 0 : 1 }
    private func value(_ text: String) -> Int? {
        guard let number = ArithmeticExpression.evaluateWholeNumber(text), (smallest...DocumentLimits.maxSide).contains(number) else { return nil }
        return number
    }
    private var valid: Bool {
        guard let w = value(width), let h = value(height) else { return false }
        return request.kind != .line || w > 0 || h > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create \(Text(request.kind.displayName))").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Width")
                    TextField("Width", text: $width)
                        .frame(width: 90).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                        .focused($focused).unitSuffix("px")
                        .accessibilityIdentifier("shapeWidth")
                }
                GridRow {
                    Text("Height")
                    TextField("Height", text: $height)
                        .frame(width: 90).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                        .unitSuffix("px")
                        .accessibilityIdentifier("shapeHeight")
                }
            }
            Toggle("From Center", isOn: $fromCenter).toggleStyle(.checkbox)
                .help("Checked, the shape is centered on the canvas wherever you clicked; unchecked, it is centered on the click")
                .accessibilityIdentifier("shapeFromCenter")
            Divider()
            HStack {
                Button("Cancel") { session.cancelShapeSize() }
                    .configuredNativeShortcut(.escape)
                Spacer()
                Button("OK") {
                    guard valid, let w = value(width), let h = value(height) else { return }
                    session.finishShapeSize(width: w, height: h, fromCenter: fromCenter)
                }
                .configuredNativeShortcut(.return).buttonStyle(.borderedProminent)
                .disabled(!valid)
            }
        }
        .padding(24).frame(width: 300).fixedSize()
        .onAppear { focused = true }
    }
}
