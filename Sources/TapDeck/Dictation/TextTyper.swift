import AppKit
import CoreGraphics
import TapCore

/// A copy of everything on the clipboard, so it can be put back after dictation borrows it.
private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        PasteboardSnapshot(items: (pasteboard.pasteboardItems ?? []).map { item in
            var entries: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entries[type] = data }
            }
            return entries
        })
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

/// Puts dictated text into the app that is in front.
///
/// It pastes: the text goes on the clipboard, Command V is pressed, and the person's own clipboard comes back.
/// Typing the characters as key events works in native apps but is ignored by many web-based and Electron apps,
/// and pasting works everywhere text can be pasted.
@MainActor
enum TextTyper {
    /// Returns the sentence for the activity log. Without the Accessibility permission nothing can press keys, so the
    /// text is left on the clipboard and the sentence says so, which means the words are never lost.
    static func insert(_ text: String) async -> String {
        let words = DictationText.wordCount(text)
        let noun = words == 1 ? "word" : "words"
        let pasteboard = NSPasteboard.general

        guard AccessibilityPermission.isTrusted(promptIfNeeded: false) else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return "Copied \(words) \(noun). Allow Accessibility to have them pasted for you, or press Command V"
        }

        let saved = PasteboardSnapshot.capture(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Tells clipboard managers this is temporary, so the dictated words do not pile up in their history.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ours = pasteboard.changeCount

        try? await Task.sleep(nanoseconds: 80_000_000)
        KeyPoster.press(KeyPoster.Code.v, flags: .maskCommand)
        // Give the app time to read the clipboard before it is put back.
        try? await Task.sleep(nanoseconds: 800_000_000)

        // Only put the old clipboard back if nothing else changed it in the meantime.
        if pasteboard.changeCount == ours { saved.restore(to: pasteboard) }
        return "Pasted \(words) \(noun)"
    }
}
