import AVFoundation
import AppKit
import Foundation
import Speech
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
    /// Screen Recording was asked for in an earlier run and macOS still refuses it.
    @Published private(set) var screenRecordingStillRefused = false

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
        if let known = status[item] { return known }
        if let bundle = Self.automationTarget(item) {
            return rememberedGrant(bundle) ? .granted : .unknown
        }
        return .missing
    }

    private static func automationTarget(_ item: SetupItem) -> String? {
        switch item {
        case .systemEvents: return AutomationPermission.systemEvents
        case .finder: return AutomationPermission.finder
        default: return nil
        }
    }

    /// Automation answers are remembered for this build, so the list is right as soon as it opens.
    /// A new build is a different app to macOS, so the memory is per build.
    private func automationMemoryKey(_ bundle: String) -> String { "setup.automation.\(bundle).\(buildID)" }
    private func rememberedGrant(_ bundle: String) -> Bool { defaults.bool(forKey: automationMemoryKey(bundle)) }
    private func remember(_ bundle: String, granted: Bool) {
        if granted { defaults.set(true, forKey: automationMemoryKey(bundle)) } else { defaults.removeObject(forKey: automationMemoryKey(bundle)) }
    }

    private var launchedAt: Double {
        (NSRunningApplication.current.launchDate ?? Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)).timeIntervalSince1970
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
        next[.microphone] = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? .granted : .missing
        next[.speechRecognition] = SFSpeechRecognizer.authorizationStatus() == .authorized ? .granted : .missing
        let requested = defaults.double(forKey: screenRequestedKey)
        let screen = ScreenRecordingState.evaluate(
            granted: ScreenCapture.hasPermission, requestedAt: requested > 0 ? requested : nil, launchedAt: launchedAt
        )
        switch screen {
        case .granted: next[.screenRecording] = .granted
        case .needsRestart: next[.screenRecording] = .needsRestart
        case .missing, .stillRefused: next[.screenRecording] = .missing
        }
        let refused = screen == .stillRefused
        if refused != screenRecordingStillRefused { screenRecordingStillRefused = refused }
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

    /// Reads Automation without starting anything or prompting: Finder is always running, System Events only
    /// when something started it. When a target is not running the remembered answer for this build is used.
    func refreshAutomationQuietly() async {
        var next = status
        for item in [SetupItem.systemEvents, .finder] {
            guard let bundle = Self.automationTarget(item) else { continue }
            if let answer = await AutomationPermission.quietStatus(for: bundle) {
                let mapped = Self.map(answer)
                next[item] = mapped
                remember(bundle, granted: mapped == .granted)
            } else if rememberedGrant(bundle) {
                next[item] = .granted
            }
        }
        if next != status { status = next }
    }

    /// Also asks System Events and Finder whether they would allow TapDeck. Starts them if they are not running.
    func refreshAll() async {
        refreshQuick()
        var next = status
        let events = await AutomationPermission.currentStatus(for: AutomationPermission.systemEvents)
        let finder = await AutomationPermission.currentStatus(for: AutomationPermission.finder)
        next[.systemEvents] = Self.map(events)
        next[.finder] = Self.map(finder)
        remember(AutomationPermission.systemEvents, granted: events == .granted)
        remember(AutomationPermission.finder, granted: finder == .granted)
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
            note = "Screen Recording was asked for. In System Settings, switch TapDeck on, then restart TapDeck once. macOS only applies it after a restart."
        }
    }

    func skipCurrent() { skipRequested = true }

    private func ask(_ item: SetupItem) async {
        switch item {
        case .systemEvents:
            let result = await AutomationPermission.requestIfNeeded(for: AutomationPermission.systemEvents)
            status[.systemEvents] = Self.map(result)
            remember(AutomationPermission.systemEvents, granted: result == .granted)
            if result == .denied {
                note = "Automation was refused earlier. Switch System Events on under Privacy & Security, Automation."
                AutomationPermission.openSystemSettings()
            }
        case .finder:
            let result = await AutomationPermission.requestIfNeeded(for: AutomationPermission.finder)
            status[.finder] = Self.map(result)
            remember(AutomationPermission.finder, granted: result == .granted)
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
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                note = "Microphone was refused earlier. Switch TapDeck on under Privacy & Security, Microphone."
                Self.openSettings("Privacy_Microphone")
            }
        case .speechRecognition:
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
                }
            } else if SFSpeechRecognizer.authorizationStatus() != .authorized {
                note = "Speech Recognition was refused earlier. Switch TapDeck on under Privacy & Security, Speech Recognition."
                Self.openSettings("Privacy_SpeechRecognition")
            }
        case .accessibility:
            _ = AccessibilityPermission.requestIfNeeded()
            _ = await waitFor(timeout: 120) { AccessibilityPermission.isTrusted(promptIfNeeded: false) }
        case .screenRecording:
            // macOS shows its prompt only once per entry. If it already refused in an earlier run, asking again
            // does nothing, which is how this row used to loop. So clear the old entry first, then ask afresh.
            if screenRecordingStillRefused {
                let id = Bundle.main.bundleIdentifier ?? "app.tapdeck.TapDeck"
                _ = try? await ProcessRunner.run("/usr/bin/tccutil", ["reset", "ScreenCapture", id], timeout: 10)
                defaults.removeObject(forKey: screenRequestedKey)
            }
            defaults.set(Date().timeIntervalSince1970, forKey: screenRequestedKey)
            ScreenCapture.requestPermission()
            Self.openSettings("Privacy_ScreenCapture")
            // macOS usually only reports this after a restart, so a short wait is enough.
            _ = await waitFor(timeout: 30) { ScreenCapture.hasPermission }
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

    private static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
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
        for service in ["Accessibility", "ScreenCapture", "AppleEvents", "Microphone", "SpeechRecognition", "SystemPolicyDesktopFolder", "SystemPolicyDocumentsFolder", "SystemPolicyDownloadsFolder"] {
            _ = try? await ProcessRunner.run("/usr/bin/tccutil", ["reset", service, id], timeout: 10)
        }
        defaults.removeObject(forKey: screenRequestedKey)
        defaults.removeObject(forKey: folderGrantedKey)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("setup.automation.") { defaults.removeObject(forKey: key) }
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
