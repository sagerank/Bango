import AppKit
import Combine
import Foundation
import TapCore

/// Owns every long-lived object and wires them together.
@MainActor
final class AppModel: ObservableObject {
    let store: ConfigStore
    let monitor: MotionMonitor
    let executor: ActionExecutor
    let engine: Engine
    let updater: AppUpdater
    let hud = HUDController()

    @Published private(set) var menuBarSymbol = "hand.tap"
    weak var mainWindow: NSWindow?
    /// True while a window the user asked for is being created, so it is not hidden like the launch window.
    var userRequestedWindow = false

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let store = ConfigStore()
        let monitor = MotionMonitor()
        let executor = ActionExecutor()
        self.store = store
        self.monitor = monitor
        self.executor = executor
        self.engine = Engine(store: store, monitor: monitor, executor: executor)
        self.updater = AppUpdater()

        engine.onFeedback = { [weak self] feedback in
            guard let self, self.store.config.showHUD else { return }
            self.hud.show(feedback)
        }

        // Pipeline settings flow to the sensor thread.
        store.$config
            .map { $0.pipelineConfig() }
            .removeDuplicates()
            .sink { monitor.updateConfig($0) }
            .store(in: &cancellables)

        // Start and stop the sensors.
        store.$config
            .map(\.monitoringEnabled)
            .removeDuplicates()
            .sink { monitor.setEnabled($0) }
            .store(in: &cancellables)

        // Menu bar icon reflects state and flashes on a gesture.
        Publishers.CombineLatest3(monitor.$isMonitoring, monitor.$isSupported, engine.$recentTaps)
            .map { monitoring, supported, recent -> String in
                if !supported { return "exclamationmark.triangle" }
                if !monitoring { return "pause.circle" }
                return recent == nil ? "hand.tap" : "hand.tap.fill"
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.menuBarSymbol = $0 }
            .store(in: &cancellables)

        // Settings are saved a moment after each change, so save now when the app is told to quit.
        NotificationCenter.default.publisher(for: .tapDeckWillTerminate)
            .sink { [weak self] _ in self?.store.flush() }
            .store(in: &cancellables)

        // While the window is open TapDeck is a normal app (Dock icon, Cmd+Tab, Force Quit, a Quit menu).
        // When it closes it goes back to the menu bar only.
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, let closing = note.object as? NSWindow, closing === self.mainWindow else { return }
                NSApp.setActivationPolicy(.accessory)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .tapDeckShowWindow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.showMainWindow() }
            .store(in: &cancellables)

        if let damaged = store.recoveredFromDamagedFile {
            NSLog("TapDeck: settings file was damaged, moved to \(damaged.path)")
        }
    }

    func showMainWindow() {
        guard let mainWindow else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.collectionBehavior.insert(.moveToActiveSpace)
        mainWindow.makeKeyAndOrderFront(nil)
        userRequestedWindow = false
    }

    func quit() {
        store.flush()
        NSApplication.shared.terminate(nil)
    }
}
