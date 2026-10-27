import AppKit
import CoreServices
import Foundation

/// The Automation permission: whether Bingo may send Apple events to another app such as System Events.
enum AutomationPermission {
    enum Status: Equatable {
        case granted
        case notDetermined
        case denied
        case unavailable
    }

    static let systemEvents = "com.apple.systemevents"
    static let finder = "com.apple.finder"
    private static let settingsPage = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

    /// The current answer, without showing a dialog. The target app is started if it is not running,
    /// because macOS only answers for a running app.
    static func currentStatus(for target: String = systemEvents) async -> Status {
        await ask(about: target, prompt: false, launchIfNeeded: true)
    }

    /// Like `currentStatus`, but never starts the app. Nil when it is not running.
    static func quietStatus(for target: String) async -> Status? {
        guard isRunning(target) else { return nil }
        return await ask(about: target, prompt: false, launchIfNeeded: false)
    }

    /// Shows macOS's own dialog when the person has not answered yet.
    static func requestIfNeeded(for target: String = systemEvents) async -> Status {
        await ask(about: target, prompt: true, launchIfNeeded: true)
    }

    static func openSystemSettings() {
        if let page = URL(string: settingsPage) { NSWorkspace.shared.open(page) }
    }

    // MARK: - Implementation

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func ask(about bundleID: String, prompt: Bool, launchIfNeeded: Bool) async -> Status {
        if launchIfNeeded, !(await startIfNeeded(bundleID)) { return .unavailable }
        // The system call can wait for the person to answer a dialog, so it must not run on the main thread.
        return await Task.detached(priority: .userInitiated) { () -> Status in
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            guard let address = target.aeDesc else { return .unavailable }
            let result = AEDeterminePermissionToAutomateTarget(
                address, AEEventClass(typeWildCard), AEEventID(typeWildCard), prompt
            )
            switch result {
            case noErr: return .granted
            case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
            case OSStatus(errAEEventNotPermitted): return .denied
            default: return .unavailable
            }
        }.value
    }

    /// Starts the app in the background and waits up to five seconds for it to show up.
    private static func startIfNeeded(_ bundleID: String) async -> Bool {
        if isRunning(bundleID) { return true }
        guard let location = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let settings = NSWorkspace.OpenConfiguration()
        settings.activates = false
        NSWorkspace.shared.openApplication(at: location, configuration: settings, completionHandler: nil)
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if isRunning(bundleID) { return true }
        }
        return false
    }
}
