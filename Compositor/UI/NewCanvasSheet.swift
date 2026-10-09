import SwiftUI
import AppKit
import ImageIO

/// The units New Canvas sizes can be typed in. Print units turn into pixels at the chosen DPI.
nonisolated enum NewCanvasUnit: String, CaseIterable, Sendable {
    case pixels = "px", inches = "in", centimeters = "cm", millimeters = "mm"

    /// The unit written out, for the summary line's pill.
    var name: String {
        switch self {
        case .pixels: "Pixels"
        case .inches: "Inches"
        case .centimeters: "Centimeters"
        case .millimeters: "Millimeters"
        }
    }
    /// The next unit, for the pill: px → in → cm → mm → px.
    var next: NewCanvasUnit { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
    private var perInch: Double? {
        switch self {
        case .pixels: nil
        case .inches: 1
        case .centimeters: 2.54
        case .millimeters: 25.4
        }
    }
    /// Whole pixels for a typed size, or nil when it isn't a size a canvas can have.
    func pixels(_ text: String, resolution: Double) -> Int? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0 else { return nil }
        let pixels = perInch.map { (value / $0 * resolution).rounded() } ?? value
        guard pixels == pixels.rounded(), (1...Double(DocumentLimits.maxSide)).contains(pixels) else { return nil }
        return Int(pixels)
    }
    /// A pixel size written in this unit: whole pixels, or print sizes to two decimals at most.
    func text(_ pixels: Int, resolution: Double) -> String {
        guard let perInch else { return String(pixels) }
        return (Double(pixels) / resolution * perInch).formatted(.number.precision(.fractionLength(0...2)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }
}

/// What a new canvas starts as: see-through, or a Background layer of white or black.
nonisolated enum NewCanvasBackground: String, CaseIterable, Sendable {
    case transparent, white, black
    var title: String { "\(rawValue.capitalized) canvas" }
    var next: NewCanvasBackground { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
    var color: CGColor? {
        switch self {
        case .transparent: nil
        case .white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .black: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        }
    }
    /// The same color as the fork's project API takes it: components in the new project's working space.
    var palette: PaletteColor? {
        switch self {
        case .transparent: nil
        case .white: .white
        case .black: PaletteColor(red: 0, green: 0, blue: 0)
        }
    }
}

struct NewCanvasSheet: View {
    let session: EditorSession
    var onCreate: ((NewCanvasSpec) -> Void)? = nil
    var onOpen: (() -> Void)? = nil

    @State private var category: NewCanvasCategory = .digital
    @State private var orientation: CanvasOrientation = .landscape

    // Digital: pixel size, optionally locked to an aspect ratio.
    @State private var width = 1920
    @State private var height = 1080
    @State private var locksAspectRatio = false
    @State private var aspectRatio: Double = 16.0 / 9.0
    /// Guards the width/height `onChange` handlers against reacting to their own lock-driven edits.
    @State private var isAdjustingForLock = false
    /// Set when a preset turns the canvas around itself, so the orientation handler doesn't swap its size back.
    @State private var isApplyingPreset = false

    // Print: a physical paper size, converted to pixels through the shared resolution field.
    @State private var paperUnit: LengthUnit = .millimeters
    @State private var paperWidth: Double = 210
    @State private var paperHeight: Double = 297

    // Shared. Every field above and this one also accepts a `*`/`/` expression; see ArithmeticExpression.
    @State private var resolution: Double = 72
    @State private var background: CanvasBackground = .transparent
    @State private var backgroundColor = PaletteColor.white
    @State private var profile: DocumentColorProfile = .sRGB

    @State private var suggestedClipboardSize = false
    @FocusState private var focusedField: Field?
    private enum Field { case width, height }

    private var digitalPixelSize: (width: Int, height: Int)? {
        guard (1...DocumentLimits.maxSide).contains(width), (1...DocumentLimits.maxSide).contains(height) else { return nil }
        return (width, height)
    }
    private var printPixelSize: (width: Int, height: Int)? {
        guard paperWidth > 0, paperHeight > 0, resolution > 0, resolution.isFinite else { return nil }
        let w = Int((paperUnit.millimeters(from: paperWidth) / 25.4 * resolution).rounded())
        let h = Int((paperUnit.millimeters(from: paperHeight) / 25.4 * resolution).rounded())
        guard (1...DocumentLimits.maxSide).contains(w), (1...DocumentLimits.maxSide).contains(h) else { return nil }
        return (w, h)
    }
    /// Which way up the size being entered is: landscape when it's wider than tall; nil when it's square.
    private var sizeOrientation: CanvasOrientation? {
        let (w, h) = category == .digital ? (Double(width), Double(height)) : (paperWidth, paperHeight)
        guard w > 0, h > 0, w != h else { return nil }
        return w > h ? .landscape : .portrait
    }

    private func followSizeOrientation() {
        if let shape = sizeOrientation, shape != orientation { orientation = shape }
    }

    private var finalPixelSize: (width: Int, height: Int)? {
        switch category {
        case .digital: return digitalPixelSize
        case .print: return printPixelSize
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New canvas").font(.title2.weight(.semibold))
            Picker("Category", selection: $category) {
                ForEach(NewCanvasCategory.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            presetsRow

            if category == .digital { digitalControls } else { printControls }

            resolutionField

            backgroundAndProfile

            statusText

            HStack(spacing: 10) {
                Button("Open project") { onOpen?() }.buttonStyle(.bordered)
                Button("Import image") { session.showsImporter = true }.buttonStyle(.bordered)
                Spacer()
                Button("Create canvas") {
                    guard let size = finalPixelSize else { return }
                    DialogColorSwatch.closePicker(session)
                    let fill: PaletteColor? = switch background {
                    case .transparent: nil
                    case .white: .white
                    case .custom: backgroundColor
                    }
                    let spec = NewCanvasSpec(width: size.width, height: size.height, resolution: resolution, profile: profile, background: fill)
                    if let onCreate { onCreate(spec) }
                    else {
                        session.createDocument(width: spec.width, height: spec.height, resolution: spec.resolution, emptyLayer: true,
                                               profile: spec.profile, background: spec.background)
                    }
                }
                .configuredNativeShortcut(.return).buttonStyle(.borderedProminent)
                .disabled(finalPixelSize == nil).accessibilityIdentifier("createCanvas")
            }
        }
        .padding(28).frame(maxWidth: 560)
        .disabled(session.isImporting || session.showsBusy)
        .onAppear {
            if !suggestedClipboardSize {
                suggestedClipboardSize = true
                if session.skipsInitialClipboardCanvasSize {
                    session.skipsInitialClipboardCanvasSize = false
                } else if let size = Self.clipboardDimensions() {
                    width = size.width
                    height = size.height
                }
            }
            focusedField = .width
        }
        .onChange(of: orientation) { _, turned in
            if isApplyingPreset { isApplyingPreset = false; return }
            // Turn the size only when it isn't already that way up, so the picker following the size is a no-op.
            guard let shape = sizeOrientation, shape != turned else { return }
            switch category {
            case .digital:
                swap(&width, &height)
                aspectRatio = 1 / aspectRatio
            case .print:
                swap(&paperWidth, &paperHeight)
            }
        }
        // Digital and Print keep their own sizes, so the picker follows whichever is showing, and a typed paper size.
        .onChange(of: category) { _, _ in followSizeOrientation() }
        .onChange(of: paperWidth) { _, _ in if category == .print { followSizeOrientation() } }
        .onChange(of: paperHeight) { _, _ in if category == .print { followSizeOrientation() } }
        .onChange(of: locksAspectRatio) { _, isOn in
            guard isOn, height > 0 else { return }
            aspectRatio = Double(width) / Double(height)
        }
        .onChange(of: width) { _, newValue in
            guard category == .digital, locksAspectRatio, !isAdjustingForLock, newValue > 0 else { return }
            isAdjustingForLock = true
            height = max(1, Int((Double(newValue) / aspectRatio).rounded()))
            isAdjustingForLock = false
        }
        .onChange(of: height) { _, newValue in
            guard category == .digital, locksAspectRatio, !isAdjustingForLock, newValue > 0 else { return }
            isAdjustingForLock = true
            width = max(1, Int((Double(newValue) * aspectRatio).rounded()))
            isAdjustingForLock = false
        }
        .onChange(of: paperUnit) { old, new in
            paperWidth = new.value(fromMillimeters: old.millimeters(from: paperWidth))
            paperHeight = new.value(fromMillimeters: old.millimeters(from: paperHeight))
        }
    }

    private var digitalControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                // The ratio the size is already at shows as chosen, whichever way up.
                ForEach(DigitalAspectRatio.allCases) { ratio in
                    let button = Button { applyDigitalAspect(ratio) } label: { Text(ratio.label) }
                    if ratio == matchedAspect { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
                }
                Spacer()
                orientationPicker
            }
            HStack(spacing: 16) {
                dimension("Width", id: "width", value: $width, field: .width)
                Image(systemName: "multiply").foregroundStyle(.tertiary).padding(.top, 20)
                dimension("Height", id: "height", value: $height, field: .height)
            }
            HStack {
                Toggle("Lock aspect ratio", isOn: $locksAspectRatio)
                Spacer()
                // Any other ratio reads as plain numbers, not as a button.
                if matchedAspect == nil, digitalPixelSize != nil {
                    Text(aspectRatioText(width: width, height: height))
                        .monospacedDigit().foregroundStyle(.secondary)
                        .help("Custom aspect ratio")
                        .accessibilityLabel("Custom aspect ratio \(aspectRatioText(width: width, height: height))")
                }
            }
        }
    }

    private var printControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Paper sizes are in the presets row's Paper menu.
            HStack(spacing: 10) {
                Picker("Unit", selection: $paperUnit) {
                    ForEach(LengthUnit.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                Spacer()
                orientationPicker
            }
            HStack(spacing: 16) {
                physicalDimension("Width", id: "paperWidth", value: $paperWidth)
                Image(systemName: "multiply").foregroundStyle(.tertiary).padding(.top, 20)
                physicalDimension("Height", id: "paperHeight", value: $paperHeight)
            }
        }
    }

    private var orientationPicker: some View {
        Picker("Orientation", selection: $orientation) {
            ForEach(CanvasOrientation.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 180)
    }

    private var resolutionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resolution").font(.callout.weight(.medium))
            HStack {
                TextField("Resolution", value: $resolution, format: ArithmeticFloatFormatStyle())
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("resolutionInput")
                Text("ppi").foregroundStyle(.secondary)
            }
            .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    /// What the canvas starts with, and the color space it's made in.
    private var backgroundAndProfile: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Background").font(.callout.weight(.medium))
                HStack(spacing: 10) {
                    Picker("Background", selection: $background) {
                        ForEach(CanvasBackground.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("Start transparent, or with a Background layer filled in white or a color of your choice")
                    if background == .custom {
                        DialogColorSwatch(title: "Background Color", color: $backgroundColor, session: session)
                            .help("The Background layer's color")
                    }
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("Color Profile").font(.callout.weight(.medium))
                Picker("Color Profile", selection: $profile) {
                    ForEach(DocumentColorProfile.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().fixedSize()
                .help(profile.detail)
                .accessibilityIdentifier("colorProfile")
            }
        }
    }

    /// "Transparent canvas" or "White background", with the color profile.
    private var contentsSummary: LocalizedStringKey {
        switch background {
        case .transparent: return "Transparent canvas"
        case .white: return "White background"
        case .custom: return "Colored background"
        }
    }

    @ViewBuilder private var statusText: some View {
        switch category {
        case .digital:
            if digitalPixelSize != nil {
                Text("\(Text(contentsSummary)) · \(Text(profile.displayName))").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Enter whole numbers from 1 to \(DocumentLimits.maxSide.formatted()) pixels.")
                    .font(.callout).foregroundStyle(.orange)
            }
        case .print:
            if let size = printPixelSize {
                Text("\(size.width) × \(size.height) px · \(Text(contentsSummary)) · \(Text(profile.displayName))")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Enter a paper size greater than zero.").font(.callout).foregroundStyle(.orange)
            }
        }
    }

    private func applyDigitalAspect(_ preset: DigitalAspectRatio) {
        var size = preset.landscapeSize
        if orientation == .portrait { swap(&size.width, &size.height) }
        width = size.width
        height = size.height
        aspectRatio = orientation == .landscape ? preset.ratio : 1 / preset.ratio
        locksAspectRatio = true
    }

    private var matchedAspect: DigitalAspectRatio? { DigitalAspectRatio.matching(width: width, height: height) }
    /// The preset the Digital size is at, if any.
    private var matchedPreset: CanvasPreset? {
        guard category == .digital else { return nil }
        return CanvasPresetGroup.allCases.lazy.flatMap { CanvasPreset.all($0) }.first { $0.width == width && $0.height == height }
    }

    /// Social and device sizes, apart from Digital and Print: each group is a menu, with the size in use checked.
    private var presetsRow: some View {
        HStack(spacing: 10) {
            Text("Presets").font(.callout.weight(.medium))
            if category == .print { paperMenu } else { digitalMenus }
            Spacer()
        }
    }

    /// Paper sizes: the common ones first, then the rest in headed sections below a divider. The sheet in use is
    /// checked, and names the menu.
    private var paperMenu: some View {
        let chosen = matchedPaper
        return Menu {
            ForEach(PaperPreset.common) { paperItem($0, chosen: chosen) }
            Divider()
            ForEach(PaperPreset.more.indices, id: \.self) { index in
                Section(String(localized: PaperPreset.more[index].title)) {
                    ForEach(PaperPreset.more[index].sizes) { paperItem($0, chosen: chosen) }
                }
            }
        } label: {
            if let chosen { Text(chosen.title) } else { Text("Paper") }
        }
        .fixedSize()
        .help("Paper sizes, most used first")
    }

    private func paperItem(_ paper: PaperPreset, chosen: PaperPreset?) -> some View {
        Toggle(isOn: Binding(get: { paper.id == chosen?.id }, set: { _ in applyPaperSize(paper) })) {
            Text("\(Text(paper.title))  \(paperSizeText(paper))")
        }
    }

    /// A paper's size in the unit being entered and the orientation chosen, width first: "210 × 297 mm" upright,
    /// "29.7 × 21 cm" or "11 × 8.5 in" on its side.
    private func paperSizeText(_ paper: PaperPreset) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
        var w = paperUnit.value(fromMillimeters: paper.width), h = paperUnit.value(fromMillimeters: paper.height)
        if orientation == .landscape { swap(&w, &h) }
        return "\(w.formatted(style)) × \(h.formatted(style)) \(paperUnit.symbol)"
    }

    /// The paper the Print size is, if it's one of the presets.
    private var matchedPaper: PaperPreset? {
        let w = paperUnit.millimeters(from: paperWidth), h = paperUnit.millimeters(from: paperHeight)
        return PaperPreset.all.first { $0.matches(width: w, height: h) }
    }

    /// Device and social sizes, for Digital.
    private var digitalMenus: some View {
        HStack(spacing: 10) {
            ForEach(CanvasPresetGroup.allCases) { group in
                let chosen = matchedPreset.flatMap { preset in CanvasPreset.all(group).contains(preset) ? preset : nil }
                Menu {
                    ForEach(CanvasPreset.sections(group).indices, id: \.self) { section in
                        if section > 0 { Divider() }
                        ForEach(CanvasPreset.sections(group)[section]) { preset in
                            Toggle(isOn: Binding(get: { preset == chosen }, set: { _ in applyPreset(preset) })) {
                                Text("\(preset.title)  \(preset.width) × \(preset.height)")
                            }
                        }
                    }
                } label: {
                    if let chosen { Text(chosen.title) } else { Text(group.label) }
                }
                .fixedSize()
                .help(group == .social ? "Sizes for social posts" : "Sizes of common screens and resolutions")
            }
        }
    }

    /// Switches to Digital and fills the size in, turning the canvas to match and keeping a locked aspect ratio in
    /// step with it.
    private func applyPreset(_ chosen: CanvasPreset) {
        category = .digital
        let turned: CanvasOrientation = chosen.height > chosen.width ? .portrait : .landscape
        if turned != orientation { isApplyingPreset = true; orientation = turned }
        aspectRatio = Double(chosen.width) / Double(chosen.height)
        width = chosen.width
        height = chosen.height
    }

    private func applyPaperSize(_ size: PaperPreset) {
        var mm = (width: size.width, height: size.height)
        if orientation == .landscape { swap(&mm.width, &mm.height) }
        paperWidth = paperUnit.value(fromMillimeters: mm.width)
        paperHeight = paperUnit.value(fromMillimeters: mm.height)
    }

    static func clipboardDimensions(_ pasteboard: NSPasteboard = .general) -> (width: Int, height: Int)? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = pasteboard.data(forType: type),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  var width = properties[kCGImagePropertyPixelWidth] as? Int,
                  var height = properties[kCGImagePropertyPixelHeight] as? Int else { continue }
            if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
                swap(&width, &height)
            }
            guard CanvasDocument.validDimension(String(width)) != nil,
                  CanvasDocument.validDimension(String(height)) != nil else { continue }
            return (width, height)
        }
        return nil
    }

    private func dimension(_ title: LocalizedStringKey, id: String, value: Binding<Int>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.medium))
            HStack {
                TextField(title, value: value, format: ArithmeticIntFormatStyle()).textFieldStyle(.plain)
                    .focused($focusedField, equals: field)
                    .accessibilityIdentifier(id + "Input")
                Text("px").foregroundStyle(.secondary)
            }
            .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private func physicalDimension(_ title: LocalizedStringKey, id: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.medium))
            HStack {
                TextField(title, value: value, format: ArithmeticFloatFormatStyle(fractionLength: 0...2)).textFieldStyle(.plain)
                    .accessibilityIdentifier(id + "Input")
                Text(paperUnit.label).foregroundStyle(.secondary)
            }
            .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        }
    }
}
