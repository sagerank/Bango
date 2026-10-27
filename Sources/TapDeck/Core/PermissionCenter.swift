import AppKit
import Foundation
import TapCore

/// Asks macOS for everything TapDeck can use, one item after another, and keeps the answers current.
///
/// macOS does not allow an app to grant itself anything. What this does is ask in a sensible order,
/// open the right System Settings page, notice the moment the switch is flipped, and move on.
@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    enum Status: Equatable {
        case granted
        case missing
        /// Allowed in System Settings, but macOS only applies it after TapDeck restarts.
        case needsRestart
        /// Login item registered, waiting for the switch in System Settings.
        case needsApproval
        case unavailable
        /// Not asked yet. Checking Automation starts System Events and Finder, so it only happens when the person asks.
        case unknown
    }

    @Published private(set) var status: [SetupItem: Status] = [:]
    @Published private(set) var isRunning = false
    @Published private(set) var current: SetupItem?
    @Published private(set) var note: String?

    private var skipRequested = false
    private let defaults = UserDefaults.standard
    private let screenRequestedKey = "setup.screenRecordingRequested"
    private let folderGrantedKey = "setup.screenshotFolderGrantedForBuild"

    private let setupBuildKey = "setup.lastSetupBuild"

    /// True when the setup screen must open by itself at launch.
    func needsSetupAtLaunch(onboardingDone: Bool) -> Bool {
        refreshQuick()
        return SetupPolicy.shouldShowSetup(
            onboardingDone: onboardingDone,
            lastSetupBuild: defaults.string(forKey: setupBuildKey),
            currentBuild: buildID,
            accessibilityGranted: state(.accessibility) == .granted,
            screenRecordingGranted: state(.screenRecording) == .granted || state(.screenRecording) == .needsRestart
        )
    }

    /// Remember that this build went through setup, so it does not come up again on every launch.
    func markSetupSeen() {
        defaults.set(buildID, forKey: setupBuildKey)
    }

    /// Something the main actions need is still off. Cheap, for badges.
    var needsAttention: Bool {
        [SetupItem.accessibility, .screenRecording].contains { state($0) == .missing }
    }

    private var buildID: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return version + "-" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    }

    func state(_ item: SetupItem) -> Status {
        status[item] ?? ((item == .systemEvents || item == .finder) ? .unknown : .missing)
    }

    var allDone: Bool {
        SetupItem.allCases.allSatisfy { [.granted, .unavailable, .unknown].contains(state($0)) }
    }

    var needsRestart: Bool {
        SetupItem.allCases.contains { state($0) == .needsRestart }
    }

    // MARK: - Reading the current state

    /// Cheap checks only. Safe to call every second.
    func refreshQuick() {
        var next = status
        next[.accessibility] = AccessibilityPermission.isTrusted(promptIfNeeded: false) ? .granted : .missing
        if ScreenCapture.hasPermission {
            next[.screenRecording] = .granted
        } else {
            next[.screenRecording] = defaults.bool(forKey: screenRequestedKey) ? .needsRestart : .missing
        }
        next[.screenshotFolder] = folderNeedsPermission ? (defaults.string(forKey: folderGrantedKey) == buildID ? .granted : .missing) : .granted
        if !LaunchAtLogin.isAvailable {
            next[.loginItem] = .unavailable
        } else if LaunchAtLogin.isEnabled {
            next[.loginItem] = .granted
        } else {
            next[.loginItem] = LaunchAtLogin.needsApproval ? .needsApproval : .missing
        }
        if next != status { status = next }
    }

    /// Also asks System Events and Finder whether they would allow TapDeck. Starts them if they are not running.
    func refreshAll() async {
        refreshQuick()
        var next = status
        next[.systemEvents] = Self.map(await AutomationPermission.currentStatus(for: AutomationPermission.systemEvents))
        next[.finder] = Self.map(await AutomationPermission.currentStatus(for: AutomationPermission.finder))
        if next != status { status = next }
    }

    private static func map(_ automation: AutomationPermission.Status) -> Status {
        switch automation {
        case .granted: return .granted
        case .notDetermined, .denied: return .missing
        case .unavailable: return .unavailable
        }
    }

    /// Desktop, Documents and Downloads are protected folders. Others need no permission.
    private var folderNeedsPermission: Bool {
        let path = ScreenCapture.saveFolder().path
        let home = NSHomeDirectory()
        return ["Desktop", "Documents", "Downloads"].contains { path.hasPrefix("\(home)/\($0)") }
            || path.contains("Mobile Documents")
    }

    // MARK: - Asking

    /// Asks for each item in the order that bothers the person least. Items already granted are skipped.
    func setUp(_ items: [SetupItem] = PermissionPlan.order) async {
        guard !isRunning else { return }
        isRunning = true
        note = nil
        refreshQuick()
        for item in PermissionPlan.order where items.contains(item) {
            skipRequested = false
            guard state(item) != .granted, state(item) != .unavailable else { continue }
            current = item
            await ask(item)
            refreshQuick()
        }
        current = nil
        refreshQuick()
        isRunning = false
        NSApp.activate(ignoringOtherApps: true)
        if needsRestart {
            note = "Screen Recording is allowed. Restart TapDeck once so macOS applies it."
        }
    }

    func skipCurrent() { skipRequested = true }

    private func ask(_ item: SetupItem) async {
        switch item {
        case .systemEvents:
            let result = await AutomationPermission.requestIfNeeded(for: AutomationPermission.systemEvents)
            status[.systemEvents] = Self.map(result)
            if result == .denied {
                note = "Automation was refused earlier. Switch System Events on under Privacy & Security, Automation."
                AutomationPermission.openSystemSettings()
            }
        case .finder:
            let result = await AutomationPermission.requestIfNeeded(for: AutomationPermission.finder)
            status[.finder] = Self.map(result)
            if result == .denied {
                note = "Automation was refused earlier. Switch Finder on under Privacy & Security, Automation."
                AutomationPermission.openSystemSettings()
            }
        case .screenshotFolder:
            let folder = ScreenCapture.saveFolder()
            let readable = await Task.detached(priority: .userInitiated) {
                (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
            }.value
            if readable { defaults.set(buildID, forKey: folderGrantedKey) }
        case .accessibility:
            _ = AccessibilityPermission.requestIfNeeded()
            _ = await waitFor(timeout: 120) { AccessibilityPermission.isTrusted(promptIfNeeded: false) }
        case .screenRecording:
            defaults.set(true, forKey: screenRequestedKey)
            ScreenCapture.requestPermission()
            // macOS usually only reports this after a restart, so a short wait is enough.
            _ = await waitFor(timeout: 45) { ScreenCapture.hasPermission }
        case .loginItem:
            do {
                try LaunchAtLogin.setEnabled(true)
                if LaunchAtLogin.needsApproval {
                    LaunchAtLogin.openLoginItemsSettings()
                    _ = await waitFor(timeout: 60) { LaunchAtLogin.isEnabled }
                }
            } catch {
                note = "Could not turn on open at login: \(error.localizedDescription)"
            }
        }
    }

    /// Polls until the condition holds, the person skips, or the time runs out.
    private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            if skipRequested { return false }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return condition()
    }

    // MARK: - Recovery

    /// Forgets everything macOS stored for TapDeck. Useful after installing a new build, because macOS ties
    /// each permission to the exact app that received it and an updated unsigned build counts as a different app.
    func resetAll() async {
        let id = Bundle.main.bundleIdentifier ?? "app.tapdeck.TapDeck"
        for service in ["Accessibility", "ScreenCapture", "AppleEvents", "SystemPolicyDesktopFolder", "SystemPolicyDocumentsFolder", "SystemPolicyDownloadsFolder"] {
            _ = try? await ProcessRunner.run("/usr/bin/tccutil", ["reset", service, id], timeout: 10)
        }
        defaults.removeObject(forKey: screenRequestedKey)
        defaults.removeObject(forKey: folderGrantedKey)
        note = "Permissions cleared. Press Set up everything to allow them again."
        await refreshAll()
    }

    /// Quits this copy and starts a fresh one once it has really gone. The helper waits for this process to
    /// exit, then opens the app without `-n`, so a restart can never leave two copies running. If this copy
    /// does not quit within ten seconds, nothing is launched.
    func restartApp() {
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "i=0; while kill -0 \"$1\" 2>/dev/null; do i=$((i+1)); [ $i -gt 50 ] && exit 0; sleep 0.2; done; /usr/bin/open \"$2\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(pid), path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
