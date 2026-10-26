import AppKit
import SwiftUI

@main
struct TapDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("TapDeck", id: "main") {
            DashboardView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.monitor)
                .environmentObject(model.engine)
                .environmentObject(model.updater)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.monitor)
                .environmentObject(model.engine)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }

    /// Clicking the app icon again, or opening it from Applications while it runs, brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .tapDeckShowWindow, object: nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

extension Notification.Name {
    static let tapDeckShowWindow = Notification.Name("tapDeckShowWindow")
}
