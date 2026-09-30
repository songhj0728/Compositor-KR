import SwiftUI

/// Photoshop's Layer Style dialog: the styles down the left, each with its checkbox, and the one picked set up on the
/// right. What it changes shows on the canvas straight away; OK keeps it as one undo step, Cancel puts it all back.
struct LayerStyleSheet: View {
    @Bindable var session: EditorSession

    private var page: LayerStylePage { session.layerStyle?.page ?? .blending }
    private var effects: LayerEffects { session.editingEffects }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            styleList
                .frame(width: 190)
                .padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { pageContent }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 430)
            Divider()
            VStack(spacing: 10) {
                Button { session.finishLayerStyle(commit: true) } label: { Text("OK").frame(maxWidth: .infinity) }
                    .configuredNativeShortcut(.return).buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("layerStyleOK")
                Button { session.finishLayerStyle(commit: false) } label: { Text("Cancel").frame(maxWidth: .infinity) }
                    .configuredNativeShortcut(.escape)
                Spacer()
            }
            .frame(width: 96).padding(14)
        }
        .frame(height: 540)
        // The picker previews its working color on the layer while it is open.
        .onChange(of: session.colorPicker?.color) { _, _ in session.previewEffectColor() }
    }

    // MARK: The list of styles

    private var styleList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Styles").font(.headline).padding(.horizontal, 12).padding(.bottom, 6)
            listRow(title: "Blending Options", selected: page == .blending, checkbox: nil) { select(.blending) }
            Divider().padding(.vertical, 4)
            ForEach(LayerEffectKind.allCases, id: \.self) { kind in
                listRow(title: kind.displayName, selected: page == .effect(kind),
                        checkbox: Binding(get: { effects.isEnabled(kind) },
                                          set: { session.setLayerStyleEffect(kind, on: $0) })) {
                    // Clicking a style's name turns it on and shows it, as in Photoshop.
                    if !effects.isEnabled(kind) { session.setLayerStyleEffect(kind, on: true) }
                    select(.effect(kind))
                }
                if kind == .bevel {
                    listRow(title: "Contour", selected: page == .bevelContour, indent: 22,
                            checkbox: Binding(get: { effects.bevel?.hasContour == true && effects.isEnabled(.bevel) },
                                              set: { on in setBevelPart { $0.usesContour = on } })) {
                        setBevelPart { $0.usesContour = true }
                        select(.bevelContour)
                    }
                    listRow(title: "Texture", selected: page == .bevelTexture, indent: 22,
                            checkbox: Binding(get: { effects.bevel?.hasTexture == true && effects.isEnabled(.bevel) },
                                              set: { on in setBevelPart { $0.usesTexture = on } })) {
                        setBevelPart { $0.usesTexture = true }
                        select(.bevelTexture)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Turning on the bevel's Contour or Texture turns the bevel on with it.
    private func setBevelPart(_ change: @escaping (inout BevelEffect) -> Void) {
        if !effects.isEnabled(.bevel) { session.setLayerStyleEffect(.bevel, on: true) }
        session.changeLayerStyle { effects in
            guard var bevel = effects.bevel else { return }
            change(&bevel)
            effects.bevel = bevel
        }
    }

    private func select(_ page: LayerStylePage) {
        session.layerStyle?.page = page
    }

    private func listRow(title: LocalizedStringKey, selected: Bool, indent: CGFloat = 0, checkbox: Binding<Bool>?,
                         action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            if let checkbox {
                Toggle("", isOn: checkbox).toggleStyle(.checkbox).labelsHidden()
            }
            Button(action: action) {
                Text(title).fontWeight(selected ? .semibold : .regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12 + indent).padding(.trailing, 8).padding(.vertical, 4)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 6)
    }

    // MARK: Pages

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .blending: blendingPage
        case .effect(let kind):
            switch kind {
            case .bevel: bevelPage
            case .stroke: strokePage
            case .innerShadow: innerShadowPage
            case .innerGlow: innerGlowPage
            case .satin: satinPage
            case .colorOverlay: colorOverlayPage
            case .patternOverlay: patternOverlayPage
            case .outerGlow: outerGlowPage
            case .shadow: dropShadowPage
            }
        case .bevelContour: bevelContourPage
        case .bevelTexture: bevelTexturePage
        }
    }

    @ViewBuilder private var blendingPage: some View {
        let layer = session.layerStyleLayer
        section("Blending Options")
        subheading("General Blending")
        blendRow(Binding(get: { layer?.blendMode ?? .normal }, set: { session.setLayerStyleBlendMode($0) }))
        percent("Opacity", Binding(get: { layer?.opacity ?? 1 }, set: { session.setLayerStyleOpacity($0) }))
        subheading("Advanced Blending")
        percent("Fill Opacity", Binding(get: { effects.fill }, set: { value in
            session.changeLayerStyle { $0.fillOpacity = value >= 1 ? nil : value }
        }))
        .help("Fades the layer's own pixels while its effects keep their strength")
    }

    @ViewBuilder private var dropShadowPage: some View {
        if let shadow = effects.shadow {
            Group {
                section("Drop Shadow")
                subheading("Structure")
                modeAndColor(.shadow)
            }
            percent("Opacity", Binding(get: { shadow.opacity }, set: { value in session.changeLayerStyle { $0.shadow?.opacity = value } }))
            slider("Angle", Binding(get: { shadow.angle }, set: { value in session.changeLayerStyle { $0.shadow?.angle = value } }), range: -180...180, unit: "°")
            slider("Distance", Binding(get: { shadow.distance }, set: { value in session.changeLayerStyle { $0.shadow?.distance = value } }), range: 0...100, input: 0...5000, unit: "px")
            slider("Spread", Binding(get: { shadow.spread ?? 0 }, set: { value in session.changeLayerStyle { $0.shadow?.spread = value > 0 ? value : nil } }), range: 0...100, unit: "%")
            slider("Size", Binding(get: { shadow.blur }, set: { value in session.changeLayerStyle { $0.shadow?.blur = value } }), range: 0...100, input: 0...500, unit: "px")
            subheading("Quality")
            contourRow("Contour", Binding(get: { shadow.contour ?? .linear }, set: { value in session.changeLayerStyle { $0.shadow?.contour = value == .linear ? nil : value } }))
        }
    }

    @ViewBuilder private var innerShadowPage: some View {
        if let inner = effects.innerShadow {
            Group {
                section("Inner Shadow")
                subheading("Structure")
                modeAndColor(.innerShadow)
            }
            percent("Opacity", Binding(get: { inner.opacity }, set: { value in session.changeLayerStyle { $0.innerShadow?.opacity = value } }))
            slider("Angle", Binding(get: { inner.angle }, set: { value in session.changeLayerStyle { $0.innerShadow?.angle = value } }), range: -180...180, unit: "°")
            slider("Distance", Binding(get: { inner.distance }, set: { value in session.changeLayerStyle { $0.innerShadow?.distance = value } }), range: 0...100, input: 0...5000, unit: "px")
            slider("Choke", Binding(get: { inner.choke ?? 0 }, set: { value in session.changeLayerStyle { $0.innerShadow?.choke = value > 0 ? value : nil } }), range: 0...100, unit: "%")
            slider("Size", Binding(get: { inner.blur }, set: { value in session.changeLayerStyle { $0.innerShadow?.blur = value } }), range: 0...100, input: 0...500, unit: "px")
            subheading("Quality")
            contourRow("Contour", Binding(get: { inner.contour ?? .linear }, set: { value in session.changeLayerStyle { $0.innerShadow?.contour = value == .linear ? nil : value } }))
        }
    }

    @ViewBuilder private var outerGlowPage: some View {
        if let glow = effects.outerGlow {
            section("Outer Glow")
            subheading("Structure")
            modeAndColor(.outerGlow)
            percent("Opacity", Binding(get: { glow.opacity }, set: { value in session.changeLayerStyle { $0.outerGlow?.opacity = value } }))
            subheading("Elements")
            slider("Spread", Binding(get: { glow.spread ?? 0 }, set: { value in session.changeLayerStyle { $0.outerGlow?.spread = value > 0 ? value : nil } }), range: 0...100, unit: "%")
            slider("Size", Binding(get: { glow.size }, set: { value in session.changeLayerStyle { $0.outerGlow?.size = value } }), range: 0...100, input: 0...500, unit: "px")
            subheading("Quality")
            contourRow("Contour", Binding(get: { glow.contour ?? .linear }, set: { value in session.changeLayerStyle { $0.outerGlow?.contour = value == .linear ? nil : value } }))
        }
    }

    @ViewBuilder private var innerGlowPage: some View {
        if let glow = effects.innerGlow {
            section("Inner Glow")
            subheading("Structure")
            modeAndColor(.innerGlow)
            percent("Opacity", Binding(get: { glow.opacity }, set: { value in session.changeLayerStyle { $0.innerGlow?.opacity = value } }))
            subheading("Elements")
            labeled("Source") {
                Picker("Source", selection: Binding(get: { glow.fromCenter == true }, set: { value in
                    session.changeLayerStyle { $0.innerGlow?.fromCenter = value ? true : nil }
                })) {
                    Text("Center").tag(true)
                    Text("Edge").tag(false)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            slider("Choke", Binding(get: { glow.choke ?? 0 }, set: { value in session.changeLayerStyle { $0.innerGlow?.choke = value > 0 ? value : nil } }), range: 0...100, unit: "%")
            slider("Size", Binding(get: { glow.size }, set: { value in session.changeLayerStyle { $0.innerGlow?.size = value } }), range: 0...100, input: 0...500, unit: "px")
            subheading("Quality")
            contourRow("Contour", Binding(get: { glow.contour ?? .linear }, set: { value in session.changeLayerStyle { $0.innerGlow?.contour = value == .linear ? nil : value } }))
        }
    }

    @ViewBuilder private var strokePage: some View {
        if let stroke = effects.stroke {
            section("Stroke")
            subheading("Structure")
            slider("Size", Binding(get: { stroke.size }, set: { value in session.changeLayerStyle { $0.stroke?.size = value } }), range: 0...50, input: 0...StrokeEffect.maxSize, unit: "px")
            labeled("Position") {
                Picker("Position", selection: Binding(get: { stroke.centered == true ? 2 : stroke.inside ? 1 : 0 }, set: { value in
                    session.changeLayerStyle { effects in
                        effects.stroke?.inside = value == 1
                        effects.stroke?.centered = value == 2 ? true : nil
                    }
                })) {
                    Text("Outside").tag(0)
                    Text("Inside").tag(1)
                    Text("Center").tag(2)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            modeAndColor(.stroke)
            percent("Opacity", Binding(get: { stroke.opacity }, set: { value in session.changeLayerStyle { $0.stroke?.opacity = value } }))
        }
    }

    @ViewBuilder private var satinPage: some View {
        if let satin = effects.satin {
            section("Satin")
            subheading("Structure")
            modeAndColor(.satin)
            percent("Opacity", Binding(get: { satin.opacity }, set: { value in session.changeLayerStyle { $0.satin?.opacity = value } }))
            slider("Angle", Binding(get: { satin.angle }, set: { value in session.changeLayerStyle { $0.satin?.angle = value } }), range: -180...180, unit: "°")
            slider("Distance", Binding(get: { satin.distance }, set: { value in session.changeLayerStyle { $0.satin?.distance = max(1, value) } }), range: 1...250, unit: "px")
            slider("Size", Binding(get: { satin.size }, set: { value in session.changeLayerStyle { $0.satin?.size = value } }), range: 0...250, unit: "px")
            HStack(spacing: 16) {
                contourRow("Contour", Binding(get: { satin.contour }, set: { value in session.changeLayerStyle { $0.satin?.contour = value } }))
                Toggle("Invert", isOn: Binding(get: { satin.invert }, set: { value in session.changeLayerStyle { $0.satin?.invert = value } }))
                    .toggleStyle(.checkbox)
            }
        }
    }

    @ViewBuilder private var colorOverlayPage: some View {
        if let overlay = effects.colorOverlay {
            section("Color Overlay")
            subheading("Color")
            modeAndColor(.colorOverlay)
            percent("Opacity", Binding(get: { overlay.opacity }, set: { value in session.changeLayerStyle { $0.colorOverlay?.opacity = value } }))
        }
    }

    @ViewBuilder private var patternOverlayPage: some View {
        if let pattern = effects.patternOverlay {
            section("Pattern Overlay")
            subheading("Pattern")
            blendRow(Binding(get: { pattern.blendMode ?? .normal }, set: { value in session.changeLayerStyle { $0.patternOverlay?.blendMode = value } }))
            percent("Opacity", Binding(get: { pattern.opacity }, set: { value in session.changeLayerStyle { $0.patternOverlay?.opacity = value } }))
            patternRow(Binding(get: { pattern.pattern }, set: { value in session.changeLayerStyle { $0.patternOverlay?.pattern = value } }),
                       ink: pattern.color, paper: pattern.paperColor)
            labeled("Colors") {
                HStack(spacing: 8) {
                    swatch(.patternOverlay, secondary: false).help("The pattern's own color")
                    swatch(.patternOverlay, secondary: true).help("The color between the pattern")
                }
            }
            slider("Scale", Binding(get: { pattern.scale }, set: { value in session.changeLayerStyle { $0.patternOverlay?.scale = value } }), range: 1...1000, unit: "%")
        }
    }

    @ViewBuilder private var bevelPage: some View {
        if let bevel = effects.bevel {
            Group {
            section("Bevel & Emboss")
            subheading("Structure")
            labeled("Style") {
                Picker("Style", selection: Binding(get: { bevel.style }, set: { value in session.changeLayerStyle { $0.bevel?.style = value } })) {
                    ForEach(BevelEffect.Style.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.labelsHidden().frame(width: 160)
            }
            labeled("Technique") {
                Picker("Technique", selection: Binding(get: { bevel.technique }, set: { value in session.changeLayerStyle { $0.bevel?.technique = value } })) {
                    ForEach(BevelEffect.Technique.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.labelsHidden().frame(width: 160)
            }
            slider("Depth", Binding(get: { bevel.depth }, set: { value in session.changeLayerStyle { $0.bevel?.depth = max(1, value) } }), range: 1...1000, unit: "%")
            labeled("Direction") {
                Picker("Direction", selection: Binding(get: { bevel.up }, set: { value in session.changeLayerStyle { $0.bevel?.up = value } })) {
                    Text("Up").tag(true)
                    Text("Down").tag(false)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            slider("Size", Binding(get: { bevel.size }, set: { value in session.changeLayerStyle { $0.bevel?.size = value } }), range: 0...250, unit: "px")
            slider("Soften", Binding(get: { bevel.soften }, set: { value in session.changeLayerStyle { $0.bevel?.soften = value } }), range: 0...16, unit: "px")
            }
            Group {
            subheading("Shading")
            slider("Angle", Binding(get: { bevel.angle }, set: { value in session.changeLayerStyle { $0.bevel?.angle = value } }), range: -180...180, unit: "°")
            slider("Altitude", Binding(get: { bevel.altitude }, set: { value in session.changeLayerStyle { $0.bevel?.altitude = value } }), range: 0...90, unit: "°")
            contourRow("Gloss Contour", Binding(get: { bevel.gloss }, set: { value in session.changeLayerStyle { $0.bevel?.gloss = value } }))
            labeled("Highlight Mode") {
                HStack(spacing: 8) {
                    blendPicker(Binding(get: { bevel.highlightMode }, set: { value in session.changeLayerStyle { $0.bevel?.highlightMode = value } }))
                    swatch(.bevel, secondary: false)
                }
            }
            percent("Opacity", Binding(get: { bevel.highlightOpacity }, set: { value in session.changeLayerStyle { $0.bevel?.highlightOpacity = value } }))
            labeled("Shadow Mode") {
                HStack(spacing: 8) {
                    blendPicker(Binding(get: { bevel.shadowMode }, set: { value in session.changeLayerStyle { $0.bevel?.shadowMode = value } }))
                    swatch(.bevel, secondary: true)
                }
            }
            percent("Opacity", Binding(get: { bevel.shadowOpacity }, set: { value in session.changeLayerStyle { $0.bevel?.shadowOpacity = value } }))
            }
        }
    }

    @ViewBuilder private var bevelContourPage: some View {
        if let bevel = effects.bevel {
            section("Contour")
            subheading("Elements")
            contourRow("Contour", Binding(get: { bevel.contour }, set: { value in session.changeLayerStyle { $0.bevel?.contour = value } }))
            slider("Range", Binding(get: { bevel.contourRange }, set: { value in session.changeLayerStyle { $0.bevel?.contourRange = max(1, value) } }), range: 1...100, unit: "%")
        }
    }

    @ViewBuilder private var bevelTexturePage: some View {
        if let bevel = effects.bevel {
            section("Texture")
            subheading("Elements")
            patternRow(Binding(get: { bevel.texture }, set: { value in session.changeLayerStyle { $0.bevel?.texture = value } }),
                       ink: .black, paper: .white)
            slider("Scale", Binding(get: { bevel.textureScale }, set: { value in session.changeLayerStyle { $0.bevel?.textureScale = max(1, value) } }), range: 1...1000, unit: "%")
            slider("Depth", Binding(get: { bevel.textureDepth }, set: { value in session.changeLayerStyle { $0.bevel?.textureDepth = value } }), range: -1000...1000, unit: "%")
            Toggle("Invert", isOn: Binding(get: { bevel.textureInvert }, set: { value in session.changeLayerStyle { $0.bevel?.textureInvert = value } }))
                .toggleStyle(.checkbox)
        }
    }

    // MARK: Controls

    private func section(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.title3.weight(.semibold)).padding(.bottom, 2)
    }

    private func subheading(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
    }

    private func labeled<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 110, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func blendPicker(_ mode: Binding<LayerBlendMode>) -> some View {
        Picker("Blend Mode", selection: mode) {
            ForEach(Array(LayerBlendMode.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
        }
        .labelsHidden().frame(width: 160)
    }

    private func blendRow(_ mode: Binding<LayerBlendMode>) -> some View {
        labeled("Blend Mode") { blendPicker(mode) }
    }

    /// An effect's blend mode and its color, on one row as Photoshop has them.
    private func modeAndColor(_ kind: LayerEffectKind) -> some View {
        labeled("Blend Mode") {
            HStack(spacing: 8) {
                blendPicker(Binding(get: { effects.blendMode(kind) }, set: { value in
                    session.changeLayerStyle { $0.setBlendMode(value, for: kind) }
                }))
                swatch(kind, secondary: false)
            }
        }
    }

    /// The effect's color, opened in the app's own picker.
    private func swatch(_ kind: LayerEffectKind, secondary: Bool) -> some View {
        let color = effects.color(kind, secondary: secondary) ?? .black
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return Button { session.openEffectColorPicker(kind, secondary: secondary) } label: {
            shape.fill(Color(nsColor: color.nsColor))
                .overlay { shape.inset(by: 1).strokeBorder(.white, lineWidth: 1) }
                .overlay { shape.strokeBorder(.black, lineWidth: 1) }
                .frame(width: 36, height: 18)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(Text("\(Text(kind.displayName)) color"))
        .accessibilityLabel(Text("\(Text(kind.displayName)) color"))
    }

    private func contourRow(_ title: LocalizedStringKey, _ contour: Binding<EffectContour>) -> some View {
        labeled(title) {
            HStack(spacing: 8) {
                ContourPreview(contour: contour.wrappedValue).frame(width: 30, height: 30)
                Picker(title, selection: contour) {
                    ForEach(EffectContour.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.labelsHidden().frame(width: 150)
            }
        }
    }

    private func patternRow(_ pattern: Binding<EffectPattern>, ink: PaletteColor, paper: PaletteColor) -> some View {
        labeled("Pattern") {
            HStack(spacing: 8) {
                PatternPreview(pattern: pattern.wrappedValue, ink: ink, paper: paper).frame(width: 30, height: 30)
                Picker("Pattern", selection: pattern) {
                    ForEach(EffectPattern.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.labelsHidden().frame(width: 150)
            }
        }
    }

    /// An opacity as a percentage.
    private func percent(_ title: LocalizedStringKey, _ value: Binding<Double>) -> some View {
        slider(title, Binding(get: { CGFloat(value.wrappedValue * 100) }, set: { value.wrappedValue = Double($0) / 100 }),
               range: 0...100, unit: "%")
    }

    private func slider(_ title: LocalizedStringKey, _ value: Binding<CGFloat>, range: ClosedRange<CGFloat>,
                        input: ClosedRange<CGFloat>? = nil, unit: String) -> some View {
        let limits = input ?? range
        let setAmount: (Double) -> Void = { amount in
            guard amount.isFinite else { return }
            value.wrappedValue = min(limits.upperBound, max(limits.lowerBound, CGFloat(amount)))
        }
        return HStack(spacing: 10) {
            Text(title).frame(width: 110, alignment: .leading)
                .scrubbable(sensitivity: 1, value: value, range: limits)
            // A typed value past the slider's end stays as typed; the thumb just rests at that end.
            Slider(value: Binding(get: { min(range.upperBound, max(range.lowerBound, value.wrappedValue)) },
                                  set: { value.wrappedValue = $0.rounded() }), in: range).frame(width: 170)
            TextField("", value: Binding(get: { Double(value.wrappedValue) }, set: setAmount),
                      format: ArithmeticFloatFormatStyle(fractionLength: 0...0))
                .frame(width: 52).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .arrowSteps(value: { Double(value.wrappedValue) }, change: setAmount)
                .unitSuffix(unit)
        }
    }
}

/// A contour's curve, drawn small beside its menu.
private struct ContourPreview: View {
    let contour: EffectContour
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let steps = 32
            for step in 0...steps {
                let x = CGFloat(step) / CGFloat(steps)
                let y = CGFloat(contour.value(Float(x)))
                let point = CGPoint(x: 2 + x * (size.width - 4), y: size.height - 2 - y * (size.height - 4))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.primary), lineWidth: 1.5)
        }
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.5)))
        .accessibilityHidden(true)
    }
}

/// A pattern's tile, drawn small beside its menu.
private struct PatternPreview: View {
    let pattern: EffectPattern
    let ink: PaletteColor
    let paper: PaletteColor
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 1
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let amount = CGFloat(pattern.value(x: Float(x), y: Float(y), scale: 0.5))
                    let color = Color(red: paper.red + (ink.red - paper.red) * amount,
                                      green: paper.green + (ink.green - paper.green) * amount,
                                      blue: paper.blue + (ink.blue - paper.blue) * amount)
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(color))
                    x += cell
                }
                y += cell
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.5)))
        .accessibilityHidden(true)
    }
}
