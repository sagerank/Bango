import Foundation

/// One thing the app asks macOS for during setup.
public enum SetupItem: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case systemEvents
    case finder
    case screenRecording
    case screenshotFolder
    case loginItem

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
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
            return "Lets TapDeck press keys for you: copy, paste, volume, media, brightness, lock screen, screenshots."
        case .systemEvents:
            return "Lets TapDeck switch dark mode."
        case .finder:
            return "Lets TapDeck eject drives."
        case .screenRecording:
            return "Lets TapDeck take screenshots straight to a file or the clipboard. macOS needs TapDeck restarted once after you allow it."
        case .screenshotFolder:
            return "Lets TapDeck save screenshots to your screenshot folder (Desktop by default) without asking each time."
        case .loginItem:
            return "Starts TapDeck when you log in, so taps work after a restart."
        }
    }
}

/// Works out which setup items a set of actions needs, so setup can ask for everything in one go.
public enum PermissionPlan {
    /// The order to ask in: dialogs that answer themselves first, items that send the user to
    /// System Settings last, so the person is not bounced back and forth.
    public static let order: [SetupItem] = [
        .systemEvents, .finder, .screenshotFolder, .accessibility, .screenRecording, .loginItem,
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
            steps += profile.bindings.flatMap { $0.steps }
            steps += profile.appOverrides.flatMap { $0.bindings.flatMap { $0.steps } }
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
