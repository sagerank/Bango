import AppKit
import Combine
import Foundation
import TapCore

struct Feedback: Equatable {
    /// Changes with every message, so the same message twice still replays its animation.
    let id = UUID()
    var symbol: String
    var title: String
    var detail: String
    var isError = false
    var kind: FeedbackKind = .generic
    /// File of the screenshot just saved, for the preview.
    var capturePath: String?
}

struct ActivityEntry: Identifiable, Equatable {
    enum Outcome: Equatable {
        case ran(String)
        case testMode(String)
        case practice
        case noBinding
        case blocked(String)
        case failed(String)
    }

    let id = UUID()
    let date: Date
    let gesture: String
    let outcome: Outcome
}

/// Turns finished gestures into actions.
///
/// Order of decisions: practice screens swallow everything, then the matching binding is found
/// (the frontmost app's overrides first), then the safety policy and test mode are applied,
/// and only then do the action steps run.
@MainActor
final class Engine: ObservableObject {
    @Published private(set) var activity: [ActivityEntry] = []
    /// Tap count of the latest gesture for about a second, used to flash the menu bar icon.
    @Published private(set) var recentTaps: Int?

    var onFeedback: ((Feedback) -> Void)?

    /// Screens that want to watch gestures without running them (practice, calibration) register here.
    /// While at least one is registered, no action runs.
    private var practiceHandlers: [UUID: (RecognizedGesture) -> Void] = [:]
    var practiceMode: Bool { !practiceHandlers.isEmpty }

    private let store: ConfigStore
    private let executor: ActionExecutor
    private var frontmostBundleID: String?
    private var chainRunning = false
    private var iconReset: DispatchWorkItem?
    /// Kept for the life of the app, which is the life of the engine.
    private var observer: NSObjectProtocol?

    private static let maxLogEntries = 100

    init(store: ConfigStore, monitor: MotionMonitor, executor: ActionExecutor) {
        self.store = store
        self.executor = executor
        frontmostBundleID = Self.bundleID(of: NSWorkspace.shared.frontmostApplication)

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.frontmostBundleID = Self.bundleID(of: app) ?? self?.frontmostBundleID }
        }

        monitor.onGesture = { [weak self] gesture in
            self?.handle(gesture)
        }
    }

    /// Bundle id of an app, ignoring TapDeck itself so its own window never hides the real target.
    private static func bundleID(of app: NSRunningApplication?) -> String? {
        guard let id = app?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
        return id
    }

    func beginPractice(_ token: UUID, handler: @escaping (RecognizedGesture) -> Void = { _ in }) {
        practiceHandlers[token] = handler
    }

    func endPractice(_ token: UUID) {
        practiceHandlers[token] = nil
    }

    func clearActivity() {
        activity.removeAll()
    }

    // MARK: - Handling

    private func handle(_ gesture: RecognizedGesture) {
        flashIcon(taps: gesture.taps)
        let baseLabel = Describe.gesture(gesture)

        if practiceMode {
            for handler in practiceHandlers.values { handler(gesture) }
            log(baseLabel, .practice)
            return
        }

        let config = store.config
        guard let resolved = config.activeProfile.resolution(for: gesture, frontmostBundleID: frontmostBundleID) else {
            let hint = config.activeProfile.missingSetupHint(
                for: gesture,
                strengthOn: config.detector.hardPeak > 0,
                zonesOn: config.zoneModel != nil
            )
            if let hint {
                log(baseLabel, .blocked(hint))
                onFeedback?(Feedback(symbol: "exclamationmark.triangle", title: baseLabel, detail: hint, isError: true))
            } else {
                log(baseLabel, .noBinding)
            }
            return
        }
        let binding = resolved.binding
        // Say which app's own gesture decided, so a per-app setup can be checked in Activity.
        let label = resolved.appName.map { "\(baseLabel) in \($0)" } ?? baseLabel
        let enabledSteps = binding.steps.filter { $0.enabled }
        guard !enabledSteps.isEmpty else {
            log(label, .noBinding)
            return
        }

        guard SafetyPolicy.isAllowed(binding) else {
            let reason = "Risky action on fewer than \(SafetyPolicy.minTapsForRisky) taps is switched off. Confirm it in Gestures."
            log(label, .blocked(reason))
            onFeedback?(Feedback(symbol: "exclamationmark.shield", title: label, detail: reason, isError: true))
            return
        }

        if config.isDryRun() {
            let summary = Describe.chain(enabledSteps)
            log(label, .testMode(summary))
            onFeedback?(Feedback(symbol: "testtube.2", title: label, detail: "Test mode: would run \(summary)"))
            return
        }

        guard !chainRunning else { return }
        chainRunning = true
        Task { await self.run(binding: binding, steps: enabledSteps, label: label) }
    }

    private func run(binding: GestureBinding, steps: [ActionStep], label: String) async {
        defer { chainRunning = false }
        var summaries: [String] = []
        for step in steps {
            do {
                summaries.append(try await executor.perform(step))
            } catch {
                let message = error.localizedDescription
                log(label, .failed(message))
                onFeedback?(Feedback(symbol: "exclamationmark.triangle", title: label, detail: message, isError: true))
                return
            }
            if step.delayAfter > 0 {
                try? await Task.sleep(nanoseconds: UInt64(min(step.delayAfter, 10) * 1_000_000_000))
            }
        }
        let summary = summaries.joined(separator: ", ")
        log(label, .ran(summary))
        var kind = FeedbackKind.generic
        if let last = steps.last, let lastSummary = summaries.last {
            kind = FeedbackKind.classify(actionId: last.actionId, parameter: last.parameter, summary: lastSummary)
        }
        var feedback = Feedback(symbol: Describe.symbol(for: binding), title: label, detail: summary, kind: kind)
        if case .screenshot = kind { feedback.capturePath = executor.lastCaptureURL?.path }
        onFeedback?(feedback)
    }

    // MARK: - Log and icon

    private func log(_ gesture: String, _ outcome: ActivityEntry.Outcome) {
        activity.insert(ActivityEntry(date: Date(), gesture: gesture, outcome: outcome), at: 0)
        if activity.count > Self.maxLogEntries {
            activity.removeLast(activity.count - Self.maxLogEntries)
        }
    }

    private func flashIcon(taps: Int) {
        recentTaps = taps
        iconReset?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.recentTaps = nil }
        }
        iconReset = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}
