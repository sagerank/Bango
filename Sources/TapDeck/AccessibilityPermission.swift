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
        // macOS shows its dialog on every call, so asking from several places stacked the same dialog up
        // four times. The dialog is shown once per launch. After that this only reports the answer.
        guard claimPrompt() else { return AXIsProcessTrusted() }
        // The documented key for "show the system dialog". The imported constant is a mutable global,
        // which Swift 6 checking dislikes, so the same string is written out.
        let options: [String: Any] = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private static let promptLock = NSLock()
    nonisolated(unsafe) private static var prompted = false

    /// True for the first caller in this launch, false for every later one.
    private static func claimPrompt() -> Bool {
        promptLock.lock()
        defer { promptLock.unlock() }
        if prompted { return false }
        prompted = true
        return true
    }

    /// Asks, and when the answer is still no, opens the settings page so the switch can be flipped.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        if isTrusted(promptIfNeeded: true) { return true }
        if let page = URL(string: settingsPage) { NSWorkspace.shared.open(page) }
        return false
    }
}
