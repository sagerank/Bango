import AppKit
import CoreGraphics
import Foundation

/// Takes screenshots with the `screencapture` tool that ships with macOS.
///
/// Unlike the keyboard shortcuts, this can save straight to a file, copy to the clipboard, and
/// hand the picture to Preview for markup. It needs the Screen Recording permission.
enum ScreenCapture {
    enum Mode {
        case fullSave, fullClipboard, areaSave, areaClipboard, windowSave, areaEdit, fullEdit

        var isInteractive: Bool {
            switch self {
            case .areaSave, .areaClipboard, .windowSave, .areaEdit: return true
            case .fullSave, .fullClipboard, .fullEdit: return false
            }
        }

        var copiesToClipboard: Bool { self == .fullClipboard || self == .areaClipboard }
        var editsAfterwards: Bool { self == .areaEdit || self == .fullEdit }
    }

    enum Outcome {
        case saved(URL)
        case copied
        case editing(URL)
        case cancelled
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// Where macOS itself saves screenshots, falling back to the Desktop.
    static func saveFolder() -> URL {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = (custom as NSString).expandingTildeInPath
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isFolder), isFolder.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static func newFileURL(in folder: URL, now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Screenshot \(formatter.string(from: now))"
        var url = folder.appendingPathComponent("\(base).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(counter).png")
            counter += 1
        }
        return url
    }

    static func perform(_ mode: Mode) async throws -> Outcome {
        var arguments: [String] = []
        let target = newFileURL(in: saveFolder())

        switch mode {
        case .areaSave, .areaEdit, .areaClipboard: arguments.append("-i")
        case .windowSave: arguments.append(contentsOf: ["-i", "-w"])
        case .fullSave, .fullClipboard, .fullEdit: break
        }
        if mode.copiesToClipboard {
            arguments.append("-c")
        } else {
            arguments.append(target.path)
        }

        // Picking an area waits for the user, so give it plenty of time.
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(
                "/usr/sbin/screencapture",
                arguments,
                timeout: mode.isInteractive ? 300 : 20
            )
        } catch {
            throw Failure("Could not start screencapture: \(error.localizedDescription)")
        }

        if mode.copiesToClipboard {
            // Escape leaves the clipboard untouched and exits quietly.
            if result.status != 0 && !result.error.isEmpty { throw Failure(result.error) }
            return mode.isInteractive && result.status != 0 ? .cancelled : .copied
        }

        guard FileManager.default.fileExists(atPath: target.path) else {
            if result.status != 0 && !result.error.isEmpty { throw Failure(result.error) }
            if mode.isInteractive { return .cancelled }
            throw Failure("The screenshot was not saved. Check the Screen Recording permission.")
        }
        return mode.editsAfterwards ? .editing(target) : .saved(target)
    }
}
