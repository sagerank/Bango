import Combine
import Foundation
import TapCore

/// Saves and loads `AppConfig` as JSON in Application Support.
///
/// Saves are atomic and slightly delayed so dragging a slider does not hit the disk on every tick.
/// A file that cannot be read is moved aside, never deleted, so the user can recover it by hand.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig {
        didSet { scheduleSave() }
    }

    /// Set when a damaged settings file had to be set aside at launch.
    private(set) var recoveredFromDamagedFile: URL?

    let fileURL: URL
    private var pendingSave: DispatchWorkItem?

    init(directory: URL? = nil) {
        let folder = directory ?? Self.defaultDirectory()
        fileURL = folder.appendingPathComponent("config.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var loaded = AppConfig()
        var moved: URL?
        if let data = try? Data(contentsOf: fileURL) {
            do {
                loaded = try JSONDecoder.tapDeck.decode(AppConfig.self, from: data)
            } catch {
                let stamp = Int(Date().timeIntervalSince1970)
                let backup = folder.appendingPathComponent("config.damaged-\(stamp).json")
                try? FileManager.default.moveItem(at: fileURL, to: backup)
                moved = backup
            }
        }
        config = loaded
        recoveredFromDamagedFile = moved
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("Bango", isDirectory: true)
        // The app has had other names. Bring the settings of the most recent one along, once, and leave
        // the old folder untouched.
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            for previous in ["Bingo", "TapDeck"] {
                let old = base.appendingPathComponent(previous, isDirectory: true)
                if fm.fileExists(atPath: old.path) {
                    try? fm.copyItem(at: old, to: directory)
                    break
                }
            }
        }
        return directory
    }

    /// Change the config in one step so observers see a single update.
    func update(_ change: (inout AppConfig) -> Void) {
        var copy = config
        change(&copy)
        config = copy
    }

    /// Writes immediately. Called when the app quits.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        save()
    }

    func resetEverything() {
        config = AppConfig()
        flush()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.save() }
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func save() {
        do {
            let data = try JSONEncoder.tapDeck.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bango: could not save settings: \(error.localizedDescription)")
        }
    }
}

extension JSONEncoder {
    static var tapDeck: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var tapDeck: JSONDecoder { JSONDecoder() }
}
