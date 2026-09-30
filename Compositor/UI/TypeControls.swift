import SwiftUI
import AppKit

struct TypeControls: View {
    @Bindable var session: EditorSession
    private func value<T>(_ key: WritableKeyPath<LayerTextStyle, T>) -> Binding<T> {
        Binding(get: { session.currentTextStyle[keyPath: key] }, set: { value in
            session.changeTextStyle { $0[keyPath: key] = value }
        })
    }
    private func number(_ key: WritableKeyPath<LayerTextStyle, CGFloat>) -> Binding<Double> {
        Binding(get: { Double(session.currentTextStyle[keyPath: key]) }, set: { value in
            session.changeTextStyle { $0[keyPath: key] = CGFloat(value) }
        })
    }
    var body: some View {
        HStack(spacing: 12) {
            Text("Type").font(ToolHeaderStyle.titleFont)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    TypeFontPicker(fontFamily: Binding(get: {
                        guard let draft = session.textDraft else {
                            let name = session.currentTextStyle.fontName
                            return NSFont(name: name, size: NSFont.systemFontSize)?.familyName ?? name
                        }
                        let selection = draft.selection
                        if selection.length == 0 {
                            let name = draft.style.fontName(at: max(0, selection.location - 1))
                            return NSFont(name: name, size: NSFont.systemFontSize)?.familyName ?? name
                        }
                        // A family stays selected while its weight or style varies within the selection, even where
                        // the face picker beside it sees more than one and shows neither.
                        return draft.style.uniformFontFamily(in: selection) ?? ""
                    }, set: { _ in }), fontName: Binding(get: {
                        guard let draft = session.textDraft else { return session.currentTextStyle.fontName }
                        let selection = draft.selection
                        if selection.length == 0 {
                            return draft.style.fontName(at: max(0, selection.location - 1))
                        }
                        // No single face: an empty title, so choosing the first letter's face still applies to the rest.
                        return draft.style.uniformFontName(in: selection) ?? ""
                    }, set: { name in
                        let selection = session.textDraft?.selection ?? NSRange()
                        session.changeTextStyle { $0.setFont(name, in: selection) }
                    }), preview: { step in
                        switch step {
                        case .show(let name): session.previewFont(name)
                        case .revert: session.endFontPreview()
                        case .keep: session.keepFontPreview()
                        }
                    })
                        .frame(width: 230).help("Font family, and its weight and style (bold, italic, …)")
                    TextField("Size", value: number(\.fontSize), format: ArithmeticFloatFormatStyle()).frame(width: 52)
                        .unitSuffix("px", scrubValue: value(\.fontSize), sensitivity: 1, range: 1...2000, step: 1)
                        .arrowSteps(value: { Double(session.currentTextStyle.fontSize) },
                                    change: { stepped in session.changeTextStyle { $0.fontSize = CGFloat(min(2000, max(1, stepped))) } })
                    Button { session.openTextColorPicker() } label: {
                        let color = session.typeColor
                        let swatch = RoundedRectangle(cornerRadius: 3, style: .continuous)
                        swatch.fill(Color(red: color.red, green: color.green, blue: color.blue))
                            .overlay { swatch.strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                            .frame(width: 36, height: 18)
                    }
                    .buttonStyle(.plain).help("Text color").accessibilityLabel("Text color")
                    HStack(spacing: 2) {
                        ForEach(TextAlignment.allCases, id: \.self) { alignment in
                            let selected = session.currentTextStyle.alignment == alignment
                            Button {
                                session.changeTextStyle { $0.alignment = alignment }
                            } label: {
                                Image(systemName: alignment == .left ? "text.alignleft" : alignment == .center ? "text.aligncenter" : "text.alignright")
                                    .frame(width: 30, height: 26)
                                    .background(selected ? Color.white.opacity(0.14) : .clear,
                                                in: RoundedRectangle(cornerRadius: 4))
                                    // Without this the glyph's own strokes are the only thing a click lands on.
                                    .contentShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .help(Text("Align \(Text(alignment.displayName))"))
                            .accessibilityLabel(Text("Align \(Text(alignment.displayName))"))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    Text("Tracking").scrubbable(sensitivity: 1, value: value(\.tracking), range: -100...1000, step: 1)
                    TextField("Tracking", value: number(\.tracking), format: ArithmeticFloatFormatStyle()).frame(width: 45)
                        .arrowSteps(value: { Double(session.currentTextStyle.tracking) },
                                    change: { stepped in session.changeTextStyle { $0.tracking = CGFloat(stepped) } })
                    Text("Leading").scrubbable(sensitivity: 1, value: value(\.leading), range: 0...5000, step: 1)
                    // 0 means Auto: the field is left empty so its "Auto" placeholder shows through.
                    TextField("Leading", text: Binding(get: {
                        let leading = session.currentTextStyle.leading
                        return leading > 0 ? String(Int(leading.rounded())) : ""
                    }, set: { typed in
                        let value = ArithmeticExpression.evaluate(typed) ?? 0
                        session.changeTextStyle { $0.leading = CGFloat(max(0, min(5000, value))) }
                    }), prompt: Text("Auto"))
                        .frame(width: 52)
                        .arrowSteps(value: { Double(session.currentTextStyle.lineHeight) },
                                    change: { stepped in session.changeTextStyle { $0.leading = CGFloat(max(0, stepped)) } })
                        .help("Line height, baseline to baseline. Empty or 0 is Auto: 120% of the font size.")
                }
            }.scrollIndicators(.hidden)
            if session.textDraft != nil {
                Button("Cancel") { session.cancelText() }
                Button("Done") { _ = session.finishText() }
            } else {
                Button("Edit Text") { session.editActiveText() }.disabled(session.activeLayer?.liveText == nil)
            }
        }
        .textFieldStyle(.roundedBorder).padding(.horizontal, 18).toolHeaderBar()
        .disabled(session.document == nil || session.showsBusy)
        .onChange(of: session.colorPicker?.color) { _, _ in session.previewTextColor() }
    }
}

/// Reads AppKit's installed-font catalog by family, so a font's dozen weights show as one family with its own short
/// list of faces instead of a dozen entries in one flat list. Kept apart from `TypeFontPicker`'s AppKit glue below so
/// it's plain, testable logic.
enum FontCatalog {
    /// Every installed family, minus the system's own hidden internal ones (their name starts with a dot, as
    /// Font Book leaves them out too), sorted for a menu.
    static func families() -> [String] { NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted() }
    /// `family`'s faces, lightest to heaviest; upright before italic falls out of their names ("Bold" sorts before
    /// "Bold Italic") without reading traits at all.
    static func faces(ofFamily family: String) -> [(postscript: String, face: String)] {
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        return members.compactMap { member -> (postscript: String, face: String, weight: Int)? in
            guard member.count >= 3, let postscript = member[0] as? String, let face = member[1] as? String,
                  let weight = member[2] as? Int else { return nil }
            return (postscript, face, weight)
        }
        .sorted { $0.weight != $1.weight ? $0.weight < $1.weight : $0.face < $1.face }
        .map { ($0.postscript, $0.face) }
    }
    /// `postscript`'s family and its own face name within it — nil when that font isn't installed.
    static func familyAndFace(of postscript: String) -> (family: String, face: String)? {
        guard !postscript.isEmpty, let font = NSFont(name: postscript, size: NSFont.systemFontSize) else { return nil }
        let family = font.familyName ?? postscript
        return (family, faces(ofFamily: family).first { $0.postscript == postscript }?.face ?? postscript)
    }
    /// `base`'s weight and style, carried into `family` as its closest matching face there — the same fallback
    /// Photoshop and every other font-family menu uses, so switching family doesn't silently reset to Regular.
    static func convert(_ base: String, toFamily family: String) -> String {
        let current = NSFont(name: base, size: NSFont.systemFontSize) ?? .systemFont(ofSize: NSFont.systemFontSize)
        return NSFontManager.shared.convert(current, toFamily: family).fontName
    }
}

/// Keep the installed-font catalog out of SwiftUI's per-keystroke view updates. Two pop-ups side by side — the
/// family, then its weight and style — rather than one flat list of every face of every font: a family with a dozen
/// weights used to mean scrolling past its eleven other faces (and everyone else's) to find the one after it.
/// The closed controls need only the current names; each menu populates on demand.
private struct TypeFontPicker: NSViewRepresentable {
    /// The face's family, shown in the left control; setting it only informs the coordinator's next `choose(_:)` —
    /// the actual change always goes through `fontName`, converted into the new family, so there is one source of
    /// truth for what the text actually uses.
    @Binding var fontFamily: String
    @Binding var fontName: String
    /// The open menu trying faces on the text: the one under the pointer, putting the text back, or keeping it.
    enum PreviewStep { case show(String), revert, keep }
    var preview: (PreviewStep) -> Void = { _ in }
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(fontFamily: $fontFamily, fontName: $fontName, preview: preview) }

    func makeNSView(context: Context) -> Container {
        let view = Container()
        let initialFace = FontCatalog.familyAndFace(of: fontName)?.face ?? fontName
        for (button, initial, label) in [(view.family, fontFamily, "Font family"), (view.face, initialFace, "Font weight and style")] {
            if !initial.isEmpty { button.addItem(withTitle: initial) }
            button.borderShape = .capsule
            // A long name is cut off at its end rather than widening the control or scrolling its start away.
            button.cell?.lineBreakMode = .byTruncatingTail
            button.cell?.usesSingleLineMode = true
            button.cell?.alignment = .left
            button.setAccessibilityLabel(label)
            button.target = context.coordinator
            button.action = #selector(Coordinator.choose(_:))
            button.menu?.delegate = context.coordinator
        }
        Coordinator.prepareFamilyLabels()
        context.coordinator.familyButton = view.family
        context.coordinator.faceButton = view.face
        return view
    }

    func updateNSView(_ view: Container, context: Context) {
        context.coordinator.fontFamily = $fontFamily
        context.coordinator.fontName = $fontName
        context.coordinator.preview = preview
        view.family.isEnabled = isEnabled
        view.face.isEnabled = isEnabled
        guard !context.coordinator.tracking else { return }
        if fontFamily.isEmpty { Self.showMultiple(in: view.family) }
        else {
            Self.hideMultiple(in: view.family)
            if view.family.titleOfSelectedItem != fontFamily {
                if view.family.item(withTitle: fontFamily) == nil { view.family.addItem(withTitle: fontFamily) }
                view.family.selectItem(withTitle: fontFamily)
            }
        }
        let face = fontFamily.isEmpty ? "" : (FontCatalog.familyAndFace(of: fontName)?.face ?? fontName)
        if face.isEmpty { Self.showMultiple(in: view.face) }
        else {
            Self.hideMultiple(in: view.face)
            if view.face.titleOfSelectedItem != face {
                if view.face.item(withTitle: face) == nil { view.face.addItem(withTitle: face) }
                view.face.selectItem(withTitle: face)
            }
        }
    }

    /// Selected letters in more than one face (or family): the menu says so with an item of its own at the top,
    /// which isn't a font.
    private static let multiple = "(Multiple)"
    private static func isMultiple(_ item: NSMenuItem?) -> Bool { item?.representedObject as? String == multiple }
    static func showMultiple(in button: NSPopUpButton) {
        if !isMultiple(button.item(at: 0)) {
            let item = NSMenuItem(title: multiple, action: nil, keyEquivalent: "")
            item.representedObject = multiple
            button.menu?.insertItem(item, at: 0)
        }
        if button.indexOfSelectedItem != 0 { button.selectItem(at: 0) }
    }
    static func hideMultiple(in button: NSPopUpButton) {
        if isMultiple(button.item(at: 0)) { button.removeItem(at: 0) }
    }

    static func dismantleNSView(_ view: Container, coordinator: Coordinator) {
        for button in [view.family, view.face] { button.menu?.delegate = nil; button.target = nil }
    }

    /// The font list holds names of every length; the control keeps whatever width it is given, so choosing a long
    /// name can't stretch it — or leave it stretched once a short one is chosen again.
    final class FixedWidthPopUpButton: NSPopUpButton {
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
        }
    }

    /// The family control fills whatever room is left; the face control (its labels are short — "Bold Italic" is
    /// about the longest common one) keeps a fixed width instead of shrinking the family control to fit it.
    final class Container: NSView {
        let family = FixedWidthPopUpButton(frame: .zero, pullsDown: false)
        let face = FixedWidthPopUpButton(frame: .zero, pullsDown: false)
        override init(frame: NSRect) {
            super.init(frame: frame)
            for button in [family, face] {
                button.translatesAutoresizingMaskIntoConstraints = false
                addSubview(button)
            }
            NSLayoutConstraint.activate([
                family.leadingAnchor.constraint(equalTo: leadingAnchor),
                family.topAnchor.constraint(equalTo: topAnchor),
                family.bottomAnchor.constraint(equalTo: bottomAnchor),
                face.leadingAnchor.constraint(equalTo: family.trailingAnchor, constant: 6),
                face.trailingAnchor.constraint(equalTo: trailingAnchor),
                face.topAnchor.constraint(equalTo: topAnchor),
                face.bottomAnchor.constraint(equalTo: bottomAnchor),
                face.widthAnchor.constraint(equalToConstant: 92),
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: family.intrinsicContentSize.height) }
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var fontFamily: Binding<String>
        var fontName: Binding<String>
        var preview: (PreviewStep) -> Void
        weak var familyButton: NSPopUpButton?
        weak var faceButton: NSPopUpButton?
        var tracking = false
        private var familyLoaded = false
        /// The family the face menu was last built for; rebuilt only when that changes, so reopening it after
        /// picking one of its own faces doesn't reset or re-style anything.
        private var faceMenuFamily: String?
        /// A face was chosen in the menu just closing, so its preview stays rather than being put back.
        private var chose = false

        init(fontFamily: Binding<String>, fontName: Binding<String>, preview: @escaping (PreviewStep) -> Void) {
            self.fontFamily = fontFamily; self.fontName = fontName; self.preview = preview
        }

        /// Each family's own name set in a representative face of it, made once for the app in the background,
        /// ahead of the menu opening. A family that can't draw its own name (an all-symbol font) keeps the menu's
        /// font instead, so the name stays readable; that's stored as an empty string.
        @MainActor private static var styledFamilyLabels: [String: NSAttributedString] = [:]
        @MainActor private static var preparingFamilies = false
        @MainActor static func styledFamilyLabel(_ family: String) -> NSAttributedString? {
            if styledFamilyLabels[family] == nil {
                let sample = NSFontManager.shared.availableMembers(ofFontFamily: family)?.first?[0] as? String
                styledFamilyLabels[family] = sample.map { makeStyledLabel(family, using: $0) } ?? NSAttributedString()
            }
            let styled = styledFamilyLabels[family]!
            return styled.length == 0 ? nil : styled
        }
        @MainActor static func prepareFamilyLabels() {
            guard !preparingFamilies, styledFamilyLabels.isEmpty else { return }
            preparingFamilies = true
            let families = FontCatalog.families()
            Task.detached(priority: .utility) {
                let made = Made(labels: Dictionary(uniqueKeysWithValues: families.compactMap { family -> (String, NSAttributedString)? in
                    guard let sample = NSFontManager.shared.availableMembers(ofFontFamily: family)?.first?[0] as? String else { return nil }
                    return (family, makeStyledLabel(family, using: sample))
                }))
                await MainActor.run { styledFamilyLabels.merge(made.labels) { current, _ in current } }
            }
        }
        /// Finished strings, never changed after they're made, handed over to the main thread.
        private struct Made: @unchecked Sendable { let labels: [String: NSAttributedString] }
        /// A family has only a handful of faces, so unlike the family list, styling them is cheap enough to do the
        /// first time each is shown rather than warming the whole catalog ahead of time.
        @MainActor private static var styledFaceLabels: [String: NSAttributedString] = [:]
        @MainActor static func styledFaceLabel(_ postscript: String, face: String) -> NSAttributedString? {
            if styledFaceLabels[postscript] == nil { styledFaceLabels[postscript] = makeStyledLabel(face, using: postscript) }
            let styled = styledFaceLabels[postscript]!
            return styled.length == 0 ? nil : styled
        }
        nonisolated private static func makeStyledLabel(_ text: String, using postscriptName: String) -> NSAttributedString {
            guard let font = NSFont(name: postscriptName, size: NSFont.systemFontSize),
                  text.unicodeScalars.filter({ $0.properties.isAlphabetic }).allSatisfy({ font.coveredCharacterSet.contains($0) })
            else { return NSAttributedString() }
            return NSAttributedString(string: text, attributes: [.font: font])
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            if menu === familyButton?.menu { updateFamilyMenu() }
            else if menu === faceButton?.menu { updateFaceMenu() }
        }
        private func updateFamilyMenu() {
            guard !familyLoaded, let button = familyButton else { return }
            let selected = fontFamily.wrappedValue
            var names = FontCatalog.families()
            if !selected.isEmpty, !names.contains(selected) { names.append(selected); names.sort() }
            button.removeAllItems()
            button.addItems(withTitles: names)
            for item in button.itemArray { item.attributedTitle = Self.styledFamilyLabel(item.title) }
            if selected.isEmpty { TypeFontPicker.showMultiple(in: button) } else { button.selectItem(withTitle: selected) }
            familyLoaded = true
        }
        private func updateFaceMenu() {
            guard let button = faceButton else { return }
            let family = fontFamily.wrappedValue
            guard !family.isEmpty else {
                button.removeAllItems()
                TypeFontPicker.showMultiple(in: button)
                faceMenuFamily = nil
                return
            }
            let selected = fontName.wrappedValue
            if faceMenuFamily != family {
                var faces = FontCatalog.faces(ofFamily: family)
                if !selected.isEmpty, !faces.contains(where: { $0.postscript == selected }) {
                    faces.append((selected, FontCatalog.familyAndFace(of: selected)?.face ?? selected))
                }
                button.removeAllItems()
                for face in faces {
                    let item = NSMenuItem(title: face.face, action: nil, keyEquivalent: "")
                    item.representedObject = face.postscript
                    item.attributedTitle = Self.styledFaceLabel(face.postscript, face: face.face)
                    button.menu?.addItem(item)
                }
                faceMenuFamily = family
            }
            TypeFontPicker.hideMultiple(in: button)
            if let face = FontCatalog.familyAndFace(of: selected)?.face, button.item(withTitle: face) != nil { button.selectItem(withTitle: face) }
            else if selected.isEmpty { TypeFontPicker.showMultiple(in: button) }
        }

        func menuWillOpen(_ menu: NSMenu) { tracking = true }
        func menuDidClose(_ menu: NSMenu) {
            tracking = false
            // A choice may be reported just after the menu closes: put the text back only if none came.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.chose { self.preview(.revert) }
                self.chose = false
            }
        }
        /// Only a face previews. Nothing highlighted (the pointer off the list, or the menu closing on a click) leaves
        /// the last face showing: reverting there flashed the old face just before the chosen one landed.
        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            guard let item, !TypeFontPicker.isMultiple(item) else { return }
            if menu === familyButton?.menu { preview(.show(FontCatalog.convert(fontName.wrappedValue, toFamily: item.title))) }
            else if let postscript = item.representedObject as? String { preview(.show(postscript)) }
        }

        @objc func choose(_ sender: NSPopUpButton) {
            // The text already shows the face under the pointer: keep it as it is, so it doesn't flash back.
            chose = true
            preview(.keep)
            guard !TypeFontPicker.isMultiple(sender.selectedItem) else { return }
            if sender === familyButton {
                guard let family = sender.titleOfSelectedItem, family != fontFamily.wrappedValue else { return }
                let converted = FontCatalog.convert(fontName.wrappedValue, toFamily: family)
                guard converted != fontName.wrappedValue else { return }
                fontName.wrappedValue = converted
            } else if sender === faceButton {
                guard let postscript = sender.selectedItem?.representedObject as? String, postscript != fontName.wrappedValue else { return }
                fontName.wrappedValue = postscript
            }
        }
    }
}
