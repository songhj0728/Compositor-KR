import Foundation

// MARK: - Core state (platform-neutral)
//
// Everything down to "Apple UI presentation layer" below uses only Foundation: no AppKit, no
// SwiftUI. That's deliberate. `AppSettings` is the single source of truth for what the user's
// preferences *are* and how they're persisted; a future non-Apple UI (e.g. a Windows build) would
// reuse this section unchanged and supply its own presentation layer instead of the SwiftUI one
// further down, the same way `AppKitSettingsPresenter` and the `Apple UI presentation layer`
// extensions below are this platform's presentation layer.

/// Overall light/dark appearance for the app's own windows, independent of the system setting.
enum AppColorScheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case system, light, dark
    var id: String { rawValue }
}

/// An app-wide tint, overriding the system accent color when not `.system`.
enum AppAccentColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite
    var id: String { rawValue }
}

/// How the brush/eraser cursor is drawn over the canvas.
enum BrushCursorStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    /// A small fixed-size crosshair, regardless of the brush's actual diameter.
    case standard
    /// An outline the size the brush will actually paint, in canvas pixels.
    case actualSize
    var id: String { rawValue }
}

/// The interface language, overriding the system language when not `.system`.
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system, english, korean
    var id: String { rawValue }
    /// The locale identifiers a `LanguageOverrideStore` should apply for this choice, or `nil` to
    /// remove any override and fall back to the platform's own language setting.
    var localeIdentifiers: [String]? {
        switch self {
        case .system: return nil
        case .english: return ["en"]
        case .korean: return ["ko"]
        }
    }
}

/// Persists a language override that takes effect on the next launch. `AppSettings` talks to this
/// protocol rather than to any platform API directly, so a future non-Apple platform can supply its
/// own mechanism (e.g. a culture override written to a Windows settings file) by implementing it,
/// without any change to `AppSettings` itself.
protocol LanguageOverrideStore {
    func apply(_ identifiers: [String]?)
}

/// The Apple-platform mechanism: writes the `AppleLanguages` `UserDefaults` key, which macOS (and
/// iOS) read once at process startup to pick the app's language, overriding the system language.
struct AppleLanguagesOverrideStore: LanguageOverrideStore {
    func apply(_ identifiers: [String]?) {
        if let identifiers {
            UserDefaults.standard.set(identifiers, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}

/// Presents and dismisses the Settings UI. `AppSettings` talks to this protocol rather than to any
/// windowing framework directly, so a future non-Apple UI (e.g. a Windows build) can supply its own
/// presenter — see `AppKitSettingsPresenter` below for this platform's implementation — without any
/// change to `AppSettings` itself.
@MainActor
protocol SettingsPresenting {
    func showSettings(for settings: AppSettings)
    func closeSettings()
}

/// App-wide preferences, shown in the Settings panel (⌘,). Appearance, accent color, history depth
/// and cursor style apply immediately; the language override needs a relaunch, since the platform
/// reads its language override once at process startup, before this object exists.
@MainActor @Observable
final class AppSettings {
    // Lazy static initialization normally runs outside any actor's isolation; `shared` is only ever
    // touched from the main thread in practice (app launch, menu actions, SwiftUI view bodies), so
    // this asserts what's already true rather than hopping actors.
    static let shared = MainActor.assumeIsolated { AppSettings() }

    var colorScheme: AppColorScheme { didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: Keys.colorScheme) } }
    var accentColor: AppAccentColor { didSet { UserDefaults.standard.set(accentColor.rawValue, forKey: Keys.accentColor) } }
    var maxUndoSteps: Int { didSet { UserDefaults.standard.set(maxUndoSteps, forKey: Keys.maxUndoSteps) } }
    var brushCursorStyle: BrushCursorStyle { didSet { UserDefaults.standard.set(brushCursorStyle.rawValue, forKey: Keys.brushCursorStyle) } }
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
            languageOverrideStore.apply(language.localeIdentifiers)
        }
    }
    /// The language the app actually launched with, so the panel knows whether a restart is still needed.
    private let languageAtLaunch: AppLanguage
    var needsRestartForLanguage: Bool { language != languageAtLaunch }

    @ObservationIgnored private let languageOverrideStore: LanguageOverrideStore
    @ObservationIgnored private let presenter: SettingsPresenting

    private enum Keys {
        static let colorScheme = "settings.colorScheme"
        static let accentColor = "settings.accentColor"
        static let maxUndoSteps = "settings.maxUndoSteps"
        static let brushCursorStyle = "settings.brushCursorStyle"
        static let language = "settings.language"
    }

    /// This platform's implementations of `languageOverrideStore` and `presenter`; a future port
    /// (or a test) can call `init(languageOverrideStore:presenter:)` with its own instead.
    convenience init() {
        self.init(languageOverrideStore: AppleLanguagesOverrideStore(), presenter: AppKitSettingsPresenter())
    }

    /// The designated initializer takes no default arguments: default-argument expressions are
    /// compiled as separate generator functions that don't reliably inherit this initializer's
    /// `@MainActor` isolation, which previously produced a spurious isolation warning here even
    /// though every call site is already on the main actor.
    init(languageOverrideStore: LanguageOverrideStore, presenter: SettingsPresenting) {
        self.languageOverrideStore = languageOverrideStore
        self.presenter = presenter
        let defaults = UserDefaults.standard
        colorScheme = AppColorScheme(rawValue: defaults.string(forKey: Keys.colorScheme) ?? "") ?? .system
        accentColor = AppAccentColor(rawValue: defaults.string(forKey: Keys.accentColor) ?? "") ?? .system
        let storedUndoSteps = defaults.integer(forKey: Keys.maxUndoSteps)
        maxUndoSteps = storedUndoSteps > 0 ? storedUndoSteps : 100
        brushCursorStyle = BrushCursorStyle(rawValue: defaults.string(forKey: Keys.brushCursorStyle) ?? "") ?? .actualSize
        let startingLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        language = startingLanguage
        languageAtLaunch = startingLanguage
    }

    func show() { presenter.showSettings(for: self) }
    func close() { presenter.closeSettings() }
}

// MARK: - Apple UI presentation layer
//
// Everything below maps the platform-neutral state above onto AppKit/SwiftUI. A future non-Apple
// port replaces only this section — a `SettingsPresenting` conformance instead of
// `AppKitSettingsPresenter`, and a display-mapping for each enum instead of the extensions below —
// while `AppSettings` and the enums above are reused as they are.

import AppKit
import SwiftUI

/// The Apple-platform settings presenter: a floating `NSPanel` hosting the SwiftUI settings form.
@MainActor
final class AppKitSettingsPresenter: SettingsPresenting {
    private let panel = FloatingPanelController(name: "appSettings")
    func showSettings(for settings: AppSettings) {
        panel.show(title: String(localized: "Settings"), content: AppSettingsSheet(settings: settings))
    }
    func closeSettings() { panel.close() }
}

extension AppColorScheme {
    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension AppAccentColor {
    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .graphite: return "Graphite"
        }
    }
    var color: Color? {
        switch self {
        case .system: return nil
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .graphite: return Color(nsColor: .systemGray)
        }
    }
}

extension BrushCursorStyle {
    var label: LocalizedStringKey {
        switch self {
        case .standard: return "Standard"
        case .actualSize: return "Actual Size"
        }
    }
}

extension AppLanguage {
    var label: LocalizedStringKey {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .korean: return "한국어"
        }
    }
}

private struct AppSettingsSheet: View {
    @Bindable var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Appearance") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Theme", selection: $settings.colorScheme) {
                        ForEach(AppColorScheme.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Accent Color", selection: $settings.accentColor) {
                        ForEach(AppAccentColor.allCases) { Text($0.label).tag($0) }
                    }
                }.padding(6)
            }
            GroupBox("Performance") {
                Stepper("History States: \(settings.maxUndoSteps)", value: $settings.maxUndoSteps, in: 10...500, step: 10)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Cursors") {
                Picker("Brush Cursor", selection: $settings.brushCursorStyle) {
                    ForEach(BrushCursorStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .padding(6)
            }
            GroupBox("Language") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("App Language", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                    if settings.needsRestartForLanguage {
                        Text("Quit and reopen Compositor to use \(Text(settings.language.label)).")
                            .foregroundStyle(.orange).font(.callout)
                    }
                }.padding(6)
            }
            HStack {
                Spacer()
                Button("Close") { settings.close() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize()
    }
}
