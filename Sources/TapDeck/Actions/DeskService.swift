import AppKit
import ApplicationServices
import TapCore

/// Saves where windows are and puts them back.
@MainActor
enum DeskService {
    /// Every app with a visible window, as fractions of the screen each window is on.
    /// Reading window positions needs no permission. Putting them back needs Accessibility.
    static func captureCurrentLayout(name: String) -> DeskLayout {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        var largest: [pid_t: CGRect] = [:]
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 150, rect.height >= 100,
                  ((window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.1
            else { continue }
            if let existing = largest[pid], existing.width * existing.height >= rect.width * rect.height { continue }
            largest[pid] = rect
        }

        var entries: [LayoutEntry] = []
        for (pid, rect) in largest {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  let screen = WindowArranger.screen(containing: rect.midX, rect.midY)
            else { continue }
            let frame = LayoutRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
            entries.append(LayoutEntry(
                bundleID: bundleID,
                appName: app.localizedName ?? bundleID,
                display: screen.index,
                fractions: LayoutMath.fractions(of: frame, in: screen.visible)
            ))
        }
        entries.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        return DeskLayout(name: name, entries: entries)
    }

    /// Opens apps that are not running, waits for their windows, and moves each window to its saved place.
    static func apply(_ layout: DeskLayout) async -> String {
        guard AXIsProcessTrusted() else { return "Allow Accessibility for Bango in Setup to move windows" }
        let screens = WindowArranger.screens()
        guard !screens.isEmpty else { return "No screen was found" }

        var arranged = 0
        var problems: [String] = []
        for entry in layout.entries {
            guard let app = await running(entry.bundleID) else {
                problems.append("\(entry.appName) would not open")
                continue
            }
            guard let window = await firstWindow(of: app.processIdentifier, waitingUpTo: 8) else {
                problems.append("\(entry.appName) has no window")
                continue
            }
            if WindowArranger.isFullScreen(window) {
                problems.append("\(entry.appName) is full screen")
                continue
            }
            let screen = screens.first { $0.index == entry.display } ?? screens[0]
            let target = LayoutMath.frame(fractions: entry.fractions, in: screen.visible)
            if WindowArranger.set(target, on: window) {
                arranged += 1
            } else {
                problems.append("\(entry.appName) cannot be moved")
            }
        }

        var text = "Arranged \(arranged) of \(layout.entries.count) windows"
        if !problems.isEmpty { text += ". " + problems.prefix(3).joined(separator: ", ") }
        return text
    }

    private static func running(_ bundleID: String) async -> NSRunningApplication? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { return app }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        return try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func firstWindow(of pid: pid_t, waitingUpTo seconds: Double) async -> AXUIElement? {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let window = WindowArranger.window(of: pid) { return window }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return WindowArranger.window(of: pid)
    }
}
