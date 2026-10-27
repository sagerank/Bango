import AppKit
import CoreGraphics
import TapCore

/// Types into whatever app is in front, one character at a time, like a keyboard. The clipboard is never used.
///
/// One character per key event matters: web-based and Electron apps read only the first character of an event, so
/// sending words in one piece makes text vanish there.
enum KeyTyper {
    private static let queue = DispatchQueue(label: "app.tapdeck.keytyper")
    private static let backspaceKey: CGKeyCode = 51

    /// Queues an edit. Edits run in order on their own queue, so typing never freezes the interface.
    static func enqueue(_ edit: LiveTypist.Edit) {
        guard !edit.isEmpty else { return }
        queue.async { send(edit) }
    }

    /// Waits until everything queued so far has been typed.
    static func flush() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { continuation.resume() }
        }
    }

    private static func send(_ edit: LiveTypist.Edit) {
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<edit.backspaces {
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: backspaceKey, keyDown: keyDown)
                event?.flags = []
                event?.post(tap: .cghidEventTap)
            }
            usleep(3_000)
        }
        for character in edit.insert {
            let units = Array(String(character).utf16)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                event?.flags = []
                units.withUnsafeBufferPointer { buffer in
                    event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress)
                }
                event?.post(tap: .cghidEventTap)
            }
            usleep(3_000)
        }
    }
}

/// When words cannot be typed (no Accessibility permission, or the app in front changed), they are kept on the
/// clipboard so they are never lost. This is the only place dictation touches the clipboard.
enum TextFallback {
    @MainActor
    static func copy(_ text: String, reason: String) -> String {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let words = DictationText.wordCount(text)
        return "\(reason). \(words) \(words == 1 ? "word is" : "words are") on the clipboard, press Command V"
    }
}
