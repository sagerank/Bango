import Combine
import Foundation
import Sparkle

/// Checks for new versions with Sparkle. It does nothing unless the build carries its own update feed
/// and signing key, so a fork can never poll somebody else's feed.
@MainActor
final class AppUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    /// The version number of an update that is waiting, for the badge in the menu bar window.
    @Published private(set) var availableVersion: String?

    private var controller: SPUStandardUpdaterController?
    private var subscriptions = Set<AnyCancellable>()

    var isAvailable: Bool { controller != nil }

    override init() {
        super.init()
        guard isConfigured else { return }

        let created = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        controller = created
        created.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &subscriptions)
        created.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &subscriptions)
        created.startUpdater()
    }

    /// An app bundle, a feed address and a public key are all needed. `swift run` has no bundle.
    private var isConfigured: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        func text(_ key: String) -> String { Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "" }
        return !text("SUFeedURL").isEmpty && !text("SUPublicEDKey").isEmpty
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}

// An app without a Dock icon can have Sparkle's window appear behind other windows, so scheduled updates are
// announced through the app's own interface instead.
extension AppUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        availableVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
