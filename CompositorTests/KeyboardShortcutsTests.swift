import AppKit
import Testing
@testable import Compositor

/// `shortcutCharacters` reads the ASCII-capable layout by key code rather than whatever the active input source's
/// `charactersIgnoringModifiers` would say — the fix for tool shortcuts (V, B, T, …) going dead under Korean and other
/// non-Latin keyboards, where the physical key positions the app still expects a Latin letter from produce something
/// else entirely.
@MainActor
struct KeyboardShortcutsTests {
    private func key(_ keyCode: UInt16, shift: Bool = false, command: Bool = false) throws -> NSEvent {
        // The characters fields carry a value the real layout would never agree with when shift doesn't match, so a
        // pass here shows shortcutCharacters really recomputed from the key code instead of trusting them.
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : command ? [.command] : [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1}", charactersIgnoringModifiers: "\u{1}",
            isARepeat: false, keyCode: keyCode))
    }

    /// Every tool letter this app assigns a shortcut to, by its ANSI-US key code, independent of whatever input
    /// source (Hangul 2-set, Pinyin, …) is actually active while the test runs.
    @Test func toolLetterKeyCodesReadAsTheirASCIILetter() throws {
        let letters: [(UInt16, String)] = [
            (0, "a"), (11, "b"), (8, "c"), (2, "d"), (14, "e"), (5, "g"), (4, "h"), (34, "i"),
            (38, "j"), (1, "s"), (17, "t"), (32, "u"), (9, "v"), (13, "w"), (7, "x"), (6, "z"),
        ]
        for (code, letter) in letters {
            #expect(try key(code).shortcutCharacters == letter, "key code \(code)")
        }
    }

    /// Shift still reaches the layout (so bracket shortcuts turn into their brace form), while Command is left out of
    /// the translation — held only for its own shortcuts, never fed back in as if it had been typed.
    @Test func shiftAppliesAndCommandDoesNot() throws {
        #expect(try key(33).shortcutCharacters == "[")
        #expect(try key(33, shift: true).shortcutCharacters == "{")
        #expect(try key(9, shift: true).shortcutCharacters == "V")
        #expect(try key(9, command: true).shortcutCharacters == "v")
    }

    /// A tool shortcut dispatches correctly even when the synthetic event's own `charactersIgnoringModifiers` — what
    /// an active Hangul input source would actually put there — has nothing to do with a Latin letter.
    @Test func toolShortcutDispatchesUnderAForeignInputSource() throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        let canvas = CanvasView(session: session)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "ㅍ", charactersIgnoringModifiers: "ㅍ", isARepeat: false, keyCode: 9))
        canvas.keyDown(with: event)
        #expect(session.tool == .move, "key code 9 is Move (v) whatever charactersIgnoringModifiers says")
    }
}
