import AppKit
import Foundation
import IOKit.pwr_mgt
import TapCore

struct ActionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

/// Carries out the actions from the catalog. Each call returns a short sentence for the activity log.
@MainActor
final class ActionExecutor: ObservableObject {
    @Published private(set) var caffeineActive = false
    /// The file written by the latest screenshot action, or nil when it went to the clipboard or was cancelled.
    private(set) var lastCaptureURL: URL?

    private var caffeineAssertion = IOPMAssertionID(0)
    private var lastInputVolume = 75
    private var lastPermissionPrompt = Date.distantPast

    private static let allowedLinkSchemes: Set<String> = ["http", "https", "mailto"]

    func perform(_ step: ActionStep) async throws -> String {
        guard let definition = ActionCatalog.definition(for: step.actionId) else {
            throw ActionError("Unknown action \"\(step.actionId)\"")
        }
        try checkPermission(for: definition)
        try checkTool(for: definition)

        switch step.actionId {
        // Clipboard
        case "copy": KeyPoster.press(KeyPoster.Code.c, flags: .maskCommand)
        case "paste": KeyPoster.press(KeyPoster.Code.v, flags: .maskCommand)
        case "cut": KeyPoster.press(KeyPoster.Code.x, flags: .maskCommand)
        case "undo": KeyPoster.press(KeyPoster.Code.z, flags: .maskCommand)
        case "redo": KeyPoster.press(KeyPoster.Code.z, flags: [.maskCommand, .maskShift])
        case "select-all": KeyPoster.press(KeyPoster.Code.a, flags: .maskCommand)

        // Media and sound
        case "play-pause": KeyPoster.media(.play)
        case "next-track": KeyPoster.media(.next)
        case "previous-track": KeyPoster.media(.previous)
        case "volume-up": KeyPoster.media(.soundUp)
        case "volume-down": KeyPoster.media(.soundDown)
        case "mute": KeyPoster.media(.mute)
        case "mic-mute": return try await toggleMicrophone()

        // Display
        case "brightness-up": KeyPoster.press(KeyPoster.Code.brightnessUp)
        case "brightness-down": KeyPoster.press(KeyPoster.Code.brightnessDown)
        case "sleep-display": try await run("/usr/bin/pmset", ["displaysleepnow"])
        case "dark-mode":
            try await run("/usr/bin/osascript", [
                "-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
            ])

        // Power
        case "caffeine": return try toggleCaffeine()
        case "lock-screen": KeyPoster.press(KeyPoster.Code.q, flags: [.maskCommand, .maskControl])
        case "screensaver": try await run("/usr/bin/open", ["/System/Library/CoreServices/ScreenSaverEngine.app"])

        // Capture
        case "screenshot-area": KeyPoster.press(KeyPoster.Code.four, flags: [.maskCommand, .maskShift])
        case "screenshot-full": KeyPoster.press(KeyPoster.Code.three, flags: [.maskCommand, .maskShift])
        case "screenshot-toolbar": KeyPoster.press(KeyPoster.Code.five, flags: [.maskCommand, .maskShift])
        case "capture-full-save": return try await capture(.fullSave)
        case "capture-full-clipboard": return try await capture(.fullClipboard)
        case "capture-area-save": return try await capture(.areaSave)
        case "capture-area-clipboard": return try await capture(.areaClipboard)
        case "capture-window-save": return try await capture(.windowSave)
        case "capture-area-edit": return try await capture(.areaEdit)
        case "capture-full-edit": return try await capture(.fullEdit)

        // Apps and windows
        case "launch-app":
            let name = step.parameter.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw ActionError("Choose an app to open") }
            try await run("/usr/bin/open", ["-a", name])
            return "Opened \(name)"
        case "open-url":
            return try openLink(step.parameter)
        case "mission-control": try await run("/usr/bin/open", ["-a", "Mission Control"])
        case "show-desktop": KeyPoster.press(KeyPoster.Code.f11)
        case "hide-others": KeyPoster.press(KeyPoster.Code.h, flags: [.maskCommand, .maskAlternate])

        // Input
        case "emoji-picker": KeyPoster.press(KeyPoster.Code.space, flags: [.maskCommand, .maskControl])
        case "type-snippet":
            guard !step.parameter.isEmpty else { throw ActionError("Write the text to paste") }
            pasteSnippet(step.parameter)

        // Connectivity
        case "wifi-toggle": return try await toggleWiFi()
        case "bluetooth-toggle": return try await toggleBluetooth()
        case "audio-output":
            let name = step.parameter.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw ActionError("Write the name of the sound output") }
            let tool = try toolPath("SwitchAudioSource", hint: "brew install switchaudio-osx")
            try await run(tool, ["-s", name])
            return "Sound output: \(name)"
        case "eject-all":
            try await run("/usr/bin/osascript", [
                "-e", "tell application \"Finder\" to eject (every disk whose ejectable is true)",
            ])

        // Automation
        case "run-shortcut":
            let name = step.parameter.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw ActionError("Write the name of the Shortcut") }
            try await run("/usr/bin/shortcuts", ["run", name], timeout: 60)
            return "Ran Shortcut \(name)"
        case "shell-command":
            let command = step.parameter.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { throw ActionError("Write the command to run") }
            try await run("/bin/zsh", ["-lc", command], timeout: 30, captureOutput: false)
            return "Ran a Terminal command"
        case ActionCatalog.noneID:
            return "Nothing to do"
        default:
            throw ActionError("\"\(definition.name)\" is not available yet")
        }
        return definition.name
    }

    // MARK: - Permissions and tools

    private func checkPermission(for definition: ActionDefinition) throws {
        if definition.permission == .screenRecording {
            guard ScreenCapture.hasPermission else {
                if Date().timeIntervalSince(lastPermissionPrompt) > 60 {
                    lastPermissionPrompt = Date()
                    ScreenCapture.requestPermission()
                }
                throw ActionError("Allow TapDeck under Privacy & Security, Screen Recording, then quit and reopen TapDeck")
            }
            return
        }
        guard definition.permission == .accessibility else { return }
        if AccessibilityPermission.isTrusted(promptIfNeeded: false) { return }
        // Ask at most once a minute so repeated taps do not spam the settings window.
        if Date().timeIntervalSince(lastPermissionPrompt) > 60 {
            lastPermissionPrompt = Date()
            _ = AccessibilityPermission.requestIfNeeded()
        }
        throw ActionError("Allow TapDeck under Privacy & Security, Accessibility, then try again")
    }

    private func checkTool(for definition: ActionDefinition) throws {
        guard let tool = definition.tool else { return }
        _ = try toolPath(tool, hint: "brew install \(tool == "blueutil" ? "blueutil" : "switchaudio-osx")")
    }

    private func toolPath(_ tool: String, hint: String) throws -> String {
        for folder in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let path = "\(folder)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw ActionError("\(tool) is not installed. Install it with: \(hint)")
    }

    // MARK: - Screen capture

    private func capture(_ mode: ScreenCapture.Mode) async throws -> String {
        lastCaptureURL = nil
        let outcome: ScreenCapture.Outcome
        do {
            outcome = try await ScreenCapture.perform(mode)
        } catch {
            throw ActionError(error.localizedDescription)
        }
        switch outcome {
        case .cancelled:
            return "Screenshot cancelled"
        case .copied:
            return "Screenshot copied"
        case .saved(let url):
            lastCaptureURL = url
            return "Saved \(url.lastPathComponent)"
        case .editing(let url):
            lastCaptureURL = url
            await openForMarkup(url)
            return "Marking up \(url.lastPathComponent)"
        }
    }

    /// Opens the picture in Preview and, when allowed, switches its markup toolbar on.
    private func openForMarkup(_ url: URL) async {
        _ = try? await ProcessRunner.run("/usr/bin/open", ["-a", "Preview", url.path], timeout: 10)
        guard AccessibilityPermission.isTrusted(promptIfNeeded: false) else { return }
        try? await Task.sleep(nanoseconds: 900_000_000)
        KeyPoster.press(KeyPoster.Code.a, flags: [.maskCommand, .maskShift])
    }

    // MARK: - Helpers

    @discardableResult
    private func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 15,
        captureOutput: Bool = true
    ) async throws -> ProcessResult {
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(executable, arguments, timeout: timeout, captureOutput: captureOutput)
        } catch {
            throw ActionError("Could not start \((executable as NSString).lastPathComponent): \(error.localizedDescription)")
        }
        guard result.status == 0 else {
            if result.error.contains("not allowed") || result.error.contains("-1743") {
                throw ActionError("Allow TapDeck under Privacy & Security, Automation, then try again")
            }
            let detail = result.error.isEmpty ? "exit status \(result.status)" : result.error
            throw ActionError(detail)
        }
        return result
    }

    private func openLink(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            throw ActionError("That is not a valid link")
        }
        guard Self.allowedLinkSchemes.contains(scheme) else {
            throw ActionError("Only http, https and mailto links are allowed")
        }
        NSWorkspace.shared.open(url)
        return "Opened \(url.host ?? trimmed)"
    }

    private func pasteSnippet(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        KeyPoster.press(KeyPoster.Code.v, flags: .maskCommand)
        // Put the user's clipboard back once the paste has gone through.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let previous else { return }
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }
    }

    // MARK: - Stateful actions

    private func toggleCaffeine() throws -> String {
        if caffeineActive {
            IOPMAssertionRelease(caffeineAssertion)
            caffeineAssertion = IOPMAssertionID(0)
            caffeineActive = false
            return "Keep awake is off"
        }
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "TapDeck keep awake" as CFString,
            &id
        )
        guard status == kIOReturnSuccess else {
            throw ActionError("The Mac refused to stay awake (code \(status))")
        }
        caffeineAssertion = id
        caffeineActive = true
        return "Keep awake is on"
    }

    private func toggleMicrophone() async throws -> String {
        let current = try await run("/usr/bin/osascript", ["-e", "input volume of (get volume settings)"])
        let level = Int(current.output) ?? 0
        if level > 0 {
            lastInputVolume = level
            try await run("/usr/bin/osascript", ["-e", "set volume input volume 0"])
            return "Microphone muted"
        }
        try await run("/usr/bin/osascript", ["-e", "set volume input volume \(lastInputVolume)"])
        return "Microphone on"
    }

    private func wifiDevice() async throws -> String {
        let result = try await run("/usr/sbin/networksetup", ["-listallhardwareports"])
        var sawWiFi = false
        for line in result.output.split(separator: "\n") {
            if line.hasPrefix("Hardware Port:") {
                sawWiFi = line.contains("Wi-Fi") || line.contains("AirPort")
            } else if sawWiFi, line.hasPrefix("Device:") {
                return line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        throw ActionError("This Mac has no Wi-Fi adapter")
    }

    private func toggleWiFi() async throws -> String {
        let device = try await wifiDevice()
        let state = try await run("/usr/sbin/networksetup", ["-getairportpower", device])
        let isOn = state.output.lowercased().hasSuffix("on")
        try await run("/usr/sbin/networksetup", ["-setairportpower", device, isOn ? "off" : "on"])
        return isOn ? "Wi-Fi is off" : "Wi-Fi is on"
    }

    private func toggleBluetooth() async throws -> String {
        let tool = try toolPath("blueutil", hint: "brew install blueutil")
        let state = try await run(tool, ["--power"])
        let isOn = state.output.trimmingCharacters(in: .whitespaces) == "1"
        try await run(tool, ["--power", isOn ? "0" : "1"])
        return isOn ? "Bluetooth is off" : "Bluetooth is on"
    }
}
