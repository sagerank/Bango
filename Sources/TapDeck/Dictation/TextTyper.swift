import AppKit
import CoreGraphics
import TapCore

/// Puts dictated text into the app that is in front, as if it were typed.
enum TextTyper {
    /// Returns the sentence for the activity log. Without the Accessibility permission the text is copied to the
    /// clipboard instead, and the sentence says so, so the words are never lost.
    static func insert(_ text: String) -> String {
        let words = DictationText.wordCount(text)
        guard AccessibilityPermission.isTrusted(promptIfNeeded: false) else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return "Copied \(words) \(words == 1 ? "word" : "words"). Allow Accessibility to have them typed, or press Command V"
        }

        let source = CGEventSource(stateID: .hidSystemState)
        for piece in DictationText.chunks(text) {
            let units = Array(piece.utf16)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                units.withUnsafeBufferPointer { buffer in
                    event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress)
                }
                event?.post(tap: .cghidEventTap)
            }
            usleep(8_000)
        }
        return "Typed \(words) \(words == 1 ? "word" : "words")"
    }
}
