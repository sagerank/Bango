import AppKit
import ApplicationServices
import TapCore

/// Moves and resizes other apps' windows through the Accessibility API.
///
/// Coordinates: the Accessibility API and the window list measure from the top left of the main screen, while
/// `NSScreen` measures from the bottom left. Everything here converts to the first kind.
enum WindowArranger {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    struct ScreenInfo {
        let index: Int
        /// The whole screen in top-left coordinates.
        let frame: LayoutRect
        /// The usable area, without the menu bar and the Dock, in top-left coordinates.
        let visible: LayoutRect
    }

    static func screens() -> [ScreenInfo] {
        let all = NSScreen.screens
        guard let primaryHeight = all.first?.frame.height else { return [] }
        return all.enumerated().map { index, screen in
            let f = screen.frame, v = screen.visibleFrame
            return ScreenInfo(
                index: index,
                frame: LayoutRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height),
                visible: LayoutRect(x: v.minX, y: primaryHeight - v.maxY, width: v.width, height: v.height)
            )
        }
    }

    /// The screen a point is on, or the main screen when it is on none.
    static func screen(containing x: Double, _ y: Double) -> ScreenInfo? {
        let list = screens()
        return list.first { $0.frame.contains(x: x, y: y) } ?? list.first
    }

    // MARK: Windows

    static func window(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success, let value {
            return (value as! AXUIElement)
        }
        value = nil
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let list = value as? [AXUIElement], let first = list.first {
            return first
        }
        return nil
    }

    static func frame(of window: AXUIElement) -> LayoutRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let p = value, AXValueGetValue(p as! AXValue, .cgPoint, &position) else { return nil }
        value = nil
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let s = value, AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return LayoutRect(x: position.x, y: position.y, width: size.width, height: size.height)
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success, let value else { return false }
        return (value as? Bool) ?? false
    }

    /// Size, position, then size again: some apps adjust the size when the position changes.
    @discardableResult
    static func set(_ rect: LayoutRect, on window: AXUIElement) -> Bool {
        var size = CGSize(width: rect.width, height: rect.height)
        var position = CGPoint(x: rect.x, y: rect.y)
        guard let sizeValue = AXValueCreate(.cgSize, &size), let positionValue = AXValueCreate(.cgPoint, &position) else { return false }
        let first = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let second = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return moved == .success && (first == .success || second == .success)
    }

    // MARK: One window

    /// Puts the front window of an app in a preset place on the screen it is on.
    static func arrange(_ preset: WindowPreset, pid: pid_t) throws -> String {
        guard AXIsProcessTrusted() else { throw Failure("Allow Accessibility for TapDeck in Setup, then try again") }
        guard let window = window(of: pid) else { throw Failure("That app has no window to move") }
        if isFullScreen(window) { throw Failure("The window is full screen. Leave full screen first") }
        guard let current = frame(of: window), let screen = screen(containing: current.midX, current.midY) else {
            throw Failure("Could not read where the window is")
        }
        let target = preset.rect(in: screen.visible)
        guard set(target, on: window) else { throw Failure("This app does not allow its window to be moved") }
        return "Window moved: \(preset.rawValue)"
    }
}
