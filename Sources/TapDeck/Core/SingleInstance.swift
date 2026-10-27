import AppKit

/// Makes sure only one TapDeck runs. A menu bar app has no Dock icon, so a copy left over from an earlier
/// install is easy to miss, and two copies mean two menu bar icons, two fights over the motion sensor and
/// a Quit button that only ever closes one of them. The newest copy wins: older ones are asked to quit,
/// then forced to if they do not.
enum SingleInstance {
    static func replaceOlderInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return } // `swift run` has none
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return }

        for app in others { app.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        for app in others where !app.isTerminated { app.forceTerminate() }
    }
}
