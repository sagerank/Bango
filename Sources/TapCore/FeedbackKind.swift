import Foundation

/// Which on-screen animation fits a finished action.
public enum FeedbackKind: Equatable, Sendable {
    case generic
    /// A picture was taken. `toClipboard` is true when it went to the clipboard, not a file.
    case screenshot(toClipboard: Bool)
    case microphone(muted: Bool)
    /// Dictation started (`listening`) or finished and typed its text.
    case dictation(listening: Bool)
    /// An app was opened. `name` is what the person typed.
    case app(name: String)

    /// Looks at the last step that ran and the sentence it returned.
    public static func classify(actionId: String, parameter: String, summary: String) -> FeedbackKind {
        switch actionId {
        case "mic-mute":
            return .microphone(muted: summary.localizedCaseInsensitiveContains("muted"))
        case "dictation-toggle":
            return .dictation(listening: summary.localizedCaseInsensitiveContains("listening"))
        case "launch-app":
            let name = parameter.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? .generic : .app(name: name)
        case _ where actionId.hasPrefix("capture-"):
            // A cancelled pick (Esc) takes no picture, so there is nothing to celebrate.
            if summary.localizedCaseInsensitiveContains("cancel") { return .generic }
            return .screenshot(toClipboard: actionId.hasSuffix("-clipboard"))
        default:
            return .generic
        }
    }
}
