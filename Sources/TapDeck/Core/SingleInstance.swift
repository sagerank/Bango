import AppKit
import TapCore

/// Makes sure only one Bingo runs. A menu bar app has no Dock icon, so a copy left over from an earlier
/// install is easy to miss, and every extra copy means another menu bar icon, another round of permission
/// prompts, a fight over the motion sensor and a Quit button that closes only the copy it was clicked in.
enum SingleInstance {
    private static func copy(_ app: NSRunningApplication) -> InstancePolicy.Copy {
        InstancePolicy.Copy(pid: app.processIdentifier, launched: app.launchDate?.timeIntervalSince1970 ?? 0)
    }

    private static func otherCopies() -> [NSRunningApplication] {
        guard let id = Bundle.main.bundleIdentifier else { return [] } // `swift run` has none
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != me }
    }

    /// The app has had other names. Close a copy that is still running under an old identity, since two
    /// menu bar icons would fight over the motion sensor.
    static func closeLegacyApp() {
        for id in ["app.tapdeck.TapDeck", "app.bango.Bango"] {
            close(NSRunningApplication.runningApplications(withBundleIdentifier: id))
        }
    }

    /// At launch: close the older copies. A copy that is newer than this one will close this one, so two
    /// copies started together cannot close each other.
    static func replaceOlderInstances() {
        let others = otherCopies()
        guard !others.isEmpty else { return }
        let me = InstancePolicy.Copy(
            pid: ProcessInfo.processInfo.processIdentifier,
            launched: NSRunningApplication.current.launchDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        )
        let doomed = Set(InstancePolicy.copiesToClose(me: me, others: others.map(copy)).map { $0.pid })
        close(others.filter { doomed.contains($0.processIdentifier) })
    }

    /// For Quit: close every other copy too, so one press really quits Bingo.
    static func closeAllOtherInstances() {
        close(otherCopies())
    }

    private static func close(_ apps: [NSRunningApplication]) {
        guard !apps.isEmpty else { return }
        for app in apps { app.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, apps.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        for app in apps where !app.isTerminated { app.forceTerminate() }
    }
}
