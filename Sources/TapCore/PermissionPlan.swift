import Foundation

/// One thing the app asks macOS for during setup.
public enum SetupItem: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case microphone
    case speechRecognition
    case systemEvents
    case finder
    case screenRecording
    case screenshotFolder
    case loginItem

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .microphone: return "Microphone"
        case .speechRecognition: return "Speech Recognition"
        case .systemEvents: return "Automation: System Events"
        case .finder: return "Automation: Finder"
        case .screenRecording: return "Screen Recording"
        case .screenshotFolder: return "Screenshot folder"
        case .loginItem: return "Open at login"
        }
    }

    /// What it is for, in plain words.
    public var why: String {
        switch self {
        case .accessibility:
            return "Lets Bango press keys for you: copy, paste, volume, media, brightness, lock screen, screenshots."
        case .microphone:
            return "Lets dictation hear you. The microphone is only on between the two double taps, and macOS shows its orange dot."
        case .speechRecognition:
            return "Lets dictation turn what you say into text. Bango uses on-device recognition, so audio stays on this Mac."
        case .systemEvents:
            return "Lets Bango switch dark mode."
        case .finder:
            return "Lets Bango eject drives."
        case .screenRecording:
            return "Lets Bango take screenshots straight to a file or the clipboard. macOS needs Bango restarted once after you allow it."
        case .screenshotFolder:
            return "Lets Bango save screenshots to your screenshot folder (Desktop by default) without asking each time."
        case .loginItem:
            return "Starts Bango when you log in, so taps work after a restart."
        }
    }
}

/// Works out which setup items a set of actions needs, so setup can ask for everything in one go.
public enum PermissionPlan {
    /// The order to ask in: dialogs that answer themselves first, items that send the user to
    /// System Settings last, so the person is not bounced back and forth.
    public static let order: [SetupItem] = [
        .systemEvents, .finder, .screenshotFolder, .microphone, .speechRecognition, .accessibility, .screenRecording, .loginItem,
    ]

    private static let screenshotsToFile: Set<String> = [
        "capture-full-save", "capture-area-save", "capture-window-save", "capture-area-edit", "capture-full-edit",
    ]
    private static let markupInPreview: Set<String> = ["capture-area-edit", "capture-full-edit"]

    /// What one action needs.
    public static func items(forAction id: String) -> [SetupItem] {
        guard let definition = ActionCatalog.definition(for: id) else { return [] }
        var out: [SetupItem] = []
        switch definition.permission {
        case .none: break
        case .accessibility: out.append(.accessibility)
        case .screenRecording: out.append(.screenRecording)
        // Typing the text into the front app uses key events, so Accessibility is needed too.
        case .dictation: out.append(contentsOf: [.microphone, .speechRecognition, .accessibility])
        case .automation: out.append(id == "eject-all" ? .finder : .systemEvents)
        }
        if screenshotsToFile.contains(id) { out.append(.screenshotFolder) }
        // Preview's markup toolbar is switched on with a key press.
        if markupInPreview.contains(id) { out.append(.accessibility) }
        return out
    }

    /// Every setup item the saved profiles use, with the names of the actions that use it.
    public static func usage(in config: AppConfig) -> [SetupItem: [String]] {
        var steps: [ActionStep] = []
        for profile in config.profiles {
            steps += profile.bindings.flatMap { $0.allSteps }
            steps += profile.appOverrides.flatMap { $0.bindings.flatMap { $0.allSteps } }
        }
        var result: [SetupItem: [String]] = [:]
        for step in steps where step.enabled {
            guard let name = ActionCatalog.definition(for: step.actionId)?.name else { continue }
            for item in items(forAction: step.actionId) {
                var names = result[item] ?? []
                if !names.contains(name) { names.append(name) }
                result[item] = names
            }
        }
        return result
    }
}

/// Decides when the setup screen must come up by itself.
public enum SetupPolicy {
    /// Show setup when the tour was never finished, or when this build has not been through setup yet and a
    /// permission the main actions need is missing. A new unsigned build counts as a new app to macOS, so
    /// permissions are lost on every update and the person must be told, not left with a silent app.
    public static func shouldShowSetup(
        onboardingDone: Bool,
        lastSetupBuild: String?,
        currentBuild: String,
        accessibilityGranted: Bool,
        screenRecordingGranted: Bool
    ) -> Bool {
        if !onboardingDone { return true }
        if lastSetupBuild == currentBuild { return false }
        return !accessibilityGranted || !screenRecordingGranted
    }
}

/// What to show for Screen Recording. macOS only applies a new Screen Recording permission after the app restarts,
/// so "restart" is right until the app has been restarted. If it still says no after that, the honest message is
/// different: the entry in System Settings does not belong to this build, which is common when the app is not signed.
public enum ScreenRecordingState: Equatable, Sendable {
    case granted
    /// Never asked for.
    case missing
    /// Asked for during this run: macOS needs the app restarted before it counts.
    case needsRestart
    /// Asked for in an earlier run and macOS still refuses.
    case stillRefused

    public static func evaluate(granted: Bool, requestedAt: Double?, launchedAt: Double) -> ScreenRecordingState {
        if granted { return .granted }
        guard let requestedAt, requestedAt > 0 else { return .missing }
        return requestedAt >= launchedAt ? .needsRestart : .stillRefused
    }
}
