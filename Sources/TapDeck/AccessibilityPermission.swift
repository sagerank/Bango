import AppKit
import ApplicationServices
import Foundation

/// The Accessibility permission, which lets Bango press keys on the person's behalf.
enum AccessibilityPermission {
    private static let settingsPage = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// True when the person has already allowed Bango. With `promptIfNeeded`, macOS also shows its own
    /// dialog when the answer is no.
    static func isTrusted(promptIfNeeded: Bool) -> Bool {
        guard promptIfNeeded else { return AXIsProcessTrusted() }
        // The documented key for "show the system dialog". The imported constant is a mutable global,
        // which Swift 6 checking dislikes, so the same string is written out.
        let options: [String: Any] = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Asks, and when the answer is still no, opens the settings page so the switch can be flipped.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        if isTrusted(promptIfNeeded: true) { return true }
        if let page = URL(string: settingsPage) { NSWorkspace.shared.open(page) }
        return false
    }
}
