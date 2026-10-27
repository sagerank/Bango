import Foundation

public enum ActionCategory: String, CaseIterable, Codable, Sendable {
    case voice, clipboard, media, sound, display, power, capture, apps, input, connectivity, automation

    public var title: String {
        switch self {
        case .voice: return "Voice"
        case .clipboard: return "Clipboard"
        case .media: return "Media"
        case .sound: return "Sound"
        case .display: return "Display"
        case .power: return "Power"
        case .capture: return "Capture"
        case .apps: return "Apps and windows"
        case .input: return "Input"
        case .connectivity: return "Connectivity"
        case .automation: return "Automation"
        }
    }
}

/// How much harm a misfire can do. Used by the safety policy.
public enum ActionDanger: Int, Codable, Comparable, Sendable {
    case safe = 0
    case caution = 1
    case destructive = 2

    public static func < (lhs: ActionDanger, rhs: ActionDanger) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum ActionPermission: String, Codable, Sendable {
    case none
    case accessibility
    case automation
    case screenRecording
    /// Microphone and Speech Recognition, for dictation.
    case dictation

    public var title: String {
        switch self {
        case .none: return "No permission"
        case .accessibility: return "Accessibility"
        case .automation: return "Automation"
        case .screenRecording: return "Screen Recording"
        case .dictation: return "Microphone and Speech Recognition"
        }
    }
}

public struct ParameterSpec: Equatable, Sendable {
    public let label: String
    public let placeholder: String

    public init(label: String, placeholder: String) {
        self.label = label
        self.placeholder = placeholder
    }
}

public struct ActionDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// SF Symbol name.
    public let symbol: String
    public let category: ActionCategory
    public let danger: ActionDanger
    public let permission: ActionPermission
    public let parameter: ParameterSpec?
    /// Optional command line tool the action needs (for example blueutil).
    public let tool: String?
    /// True when the action can run arbitrary code or open arbitrary links. Imported profiles get these disabled.
    public let runsCode: Bool

    public init(
        _ id: String,
        _ name: String,
        symbol: String,
        category: ActionCategory,
        danger: ActionDanger = .safe,
        permission: ActionPermission = .none,
        parameter: ParameterSpec? = nil,
        tool: String? = nil,
        runsCode: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.category = category
        self.danger = danger
        self.permission = permission
        self.parameter = parameter
        self.tool = tool
        self.runsCode = runsCode
    }
}

public enum ActionCatalog {
    public static let noneID = "none"

    public static let all: [ActionDefinition] = [
        // Voice
        ActionDefinition("dictation-toggle", "Dictation: start or stop", symbol: "mic.fill", category: .voice, permission: .dictation),

        // Clipboard
        ActionDefinition("copy", "Copy", symbol: "doc.on.doc", category: .clipboard, permission: .accessibility),
        ActionDefinition("paste", "Paste", symbol: "doc.on.clipboard", category: .clipboard, permission: .accessibility),
        ActionDefinition("cut", "Cut", symbol: "scissors", category: .clipboard, permission: .accessibility),
        ActionDefinition("undo", "Undo", symbol: "arrow.uturn.backward", category: .clipboard, permission: .accessibility),
        ActionDefinition("redo", "Redo", symbol: "arrow.uturn.forward", category: .clipboard, permission: .accessibility),
        ActionDefinition("select-all", "Select all", symbol: "checkmark.rectangle", category: .clipboard, permission: .accessibility),

        // Media
        ActionDefinition("play-pause", "Play or pause", symbol: "playpause", category: .media, permission: .accessibility),
        ActionDefinition("next-track", "Next track", symbol: "forward.end", category: .media, permission: .accessibility),
        ActionDefinition("previous-track", "Previous track", symbol: "backward.end", category: .media, permission: .accessibility),

        // Sound
        ActionDefinition("volume-up", "Volume up", symbol: "speaker.plus", category: .sound, permission: .accessibility),
        ActionDefinition("volume-down", "Volume down", symbol: "speaker.minus", category: .sound, permission: .accessibility),
        ActionDefinition("mute", "Mute or unmute speakers", symbol: "speaker.slash", category: .sound, permission: .accessibility),
        ActionDefinition("mic-mute", "Mute or unmute microphone", symbol: "mic.slash", category: .sound),

        // Display
        ActionDefinition("brightness-up", "Brightness up", symbol: "sun.max", category: .display, permission: .accessibility),
        ActionDefinition("brightness-down", "Brightness down", symbol: "sun.min", category: .display, permission: .accessibility),
        ActionDefinition("sleep-display", "Sleep display", symbol: "display", category: .display, danger: .caution),
        ActionDefinition("dark-mode", "Toggle dark mode", symbol: "circle.lefthalf.filled", category: .display, permission: .automation),

        // Power
        ActionDefinition("caffeine", "Keep awake on or off", symbol: "cup.and.saucer", category: .power),
        ActionDefinition("lock-screen", "Lock screen", symbol: "lock", category: .power, danger: .caution, permission: .accessibility),
        ActionDefinition("screensaver", "Start screen saver", symbol: "moon.stars", category: .power),

        // Capture
        ActionDefinition("screenshot-area", "Screenshot of an area (macOS shortcut)", symbol: "viewfinder", category: .capture, permission: .accessibility),
        ActionDefinition("screenshot-full", "Screenshot of the screen (macOS shortcut)", symbol: "rectangle.dashed", category: .capture, permission: .accessibility),
        ActionDefinition("screenshot-toolbar", "Screenshot and recording toolbar", symbol: "camera.viewfinder", category: .capture, permission: .accessibility),
        ActionDefinition("capture-full-save", "Full screen: save to file now", symbol: "rectangle.on.rectangle", category: .capture, permission: .screenRecording),
        ActionDefinition("capture-full-clipboard", "Full screen: copy to clipboard", symbol: "doc.on.clipboard", category: .capture, permission: .screenRecording),
        ActionDefinition("capture-area-save", "Area: pick and save to file", symbol: "viewfinder", category: .capture, permission: .screenRecording),
        ActionDefinition("capture-area-clipboard", "Area: pick and copy to clipboard", symbol: "viewfinder.circle", category: .capture, permission: .screenRecording),
        ActionDefinition("capture-window-save", "Window: pick and save to file", symbol: "macwindow.badge.plus", category: .capture, permission: .screenRecording),
        ActionDefinition("capture-area-edit", "Area: pick, then mark up in Preview", symbol: "pencil.and.outline", category: .capture, permission: .screenRecording),
        ActionDefinition("capture-full-edit", "Full screen: capture, then mark up in Preview", symbol: "pencil.tip.crop.circle", category: .capture, permission: .screenRecording),

        // Apps and windows
        ActionDefinition("launch-app", "Open an app", symbol: "app", category: .apps,
                         parameter: ParameterSpec(label: "App name", placeholder: "Safari")),
        ActionDefinition("open-url", "Open a link", symbol: "link", category: .apps,
                         parameter: ParameterSpec(label: "Link", placeholder: "https://example.com"), runsCode: true),
        ActionDefinition("mission-control", "Mission Control", symbol: "rectangle.3.group", category: .apps, permission: .accessibility),
        ActionDefinition("show-desktop", "Show desktop", symbol: "macwindow", category: .apps, permission: .accessibility),
        ActionDefinition("hide-others", "Hide other apps", symbol: "eye.slash", category: .apps, permission: .accessibility),

        // Input
        ActionDefinition("emoji-picker", "Emoji and symbols", symbol: "face.smiling", category: .input, permission: .accessibility),
        ActionDefinition("type-snippet", "Paste a saved snippet", symbol: "text.cursor", category: .input, permission: .accessibility,
                         parameter: ParameterSpec(label: "Text", placeholder: "Thanks, I will get back to you today.")),

        // Connectivity
        ActionDefinition("wifi-toggle", "Wi-Fi on or off", symbol: "wifi", category: .connectivity, danger: .destructive),
        ActionDefinition("bluetooth-toggle", "Bluetooth on or off", symbol: "dot.radiowaves.left.and.right", category: .connectivity,
                         danger: .destructive, tool: "blueutil"),
        ActionDefinition("audio-output", "Switch sound output", symbol: "hifispeaker", category: .connectivity,
                         parameter: ParameterSpec(label: "Output name", placeholder: "MacBook Pro Speakers"), tool: "SwitchAudioSource"),
        ActionDefinition("eject-all", "Eject all drives", symbol: "eject", category: .connectivity, danger: .destructive, permission: .automation),

        // Automation
        ActionDefinition("run-shortcut", "Run a Shortcut", symbol: "bolt", category: .automation,
                         parameter: ParameterSpec(label: "Shortcut name", placeholder: "Toggle Focus")),
        ActionDefinition("shell-command", "Run a Terminal command", symbol: "terminal", category: .automation, danger: .destructive,
                         parameter: ParameterSpec(label: "Command", placeholder: "echo hello"), runsCode: true),
        ActionDefinition(noneID, "Do nothing", symbol: "nosign", category: .automation),
    ]

    public static func definition(for id: String) -> ActionDefinition? {
        all.first { $0.id == id }
    }

    public static func actions(in category: ActionCategory) -> [ActionDefinition] {
        all.filter { $0.category == category }
    }
}
