import AppKit
import CoreServices
import Foundation

enum AutomationPermission {
    enum Status: Equatable {
        case granted
        case notDetermined
        case denied
        case unavailable
    }

    static let systemEvents = "com.apple.systemevents"
    static let finder = "com.apple.finder"
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )!

    static func currentStatus(for target: String = systemEvents) async -> Status {
        await determineStatus(target: target, askUserIfNeeded: false)
    }

    /// Asks macOS without starting the target app and without prompting. Nil when the target is not running,
    /// because macOS cannot answer for an app that is not there.
    static func quietStatus(for target: String) async -> Status? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: target).isEmpty else { return nil }
        return await determineStatus(target: target, askUserIfNeeded: false)
    }

    static func requestIfNeeded(for target: String = systemEvents) async -> Status {
        await determineStatus(target: target, askUserIfNeeded: true)
    }

    static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    private static func determineStatus(target targetBundleIdentifier: String, askUserIfNeeded: Bool) async -> Status {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: determineStatusOnWorker(target: targetBundleIdentifier, askUserIfNeeded: askUserIfNeeded))
            }
        }
    }

    private static func determineStatusOnWorker(target targetBundleIdentifier: String, askUserIfNeeded: Bool) -> Status {
        guard ensureIsRunning(targetBundleIdentifier) else { return .unavailable }

        var target = AEAddressDesc()
        let bundleIDData = Data(targetBundleIdentifier.utf8)
        let createStatus = bundleIDData.withUnsafeBytes { bytes in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                bytes.baseAddress,
                bundleIDData.count,
                &target
            )
        }

        guard createStatus == noErr else { return .unavailable }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )

        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unavailable
        }
    }

    private static func ensureIsRunning(_ targetBundleIdentifier: String) -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleIdentifier).isEmpty {
            return true
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleIdentifier) else {
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = false

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5)
        return !NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleIdentifier).isEmpty
    }
}
