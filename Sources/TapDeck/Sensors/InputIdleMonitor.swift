import CoreGraphics
import Foundation

/// Tells how long ago the user last pressed a key or clicked.
///
/// This is the first layer of the typing guard: taps that coincide with typing are ignored,
/// because typing shakes the whole chassis. Reading these timers needs no extra permission.
/// The value is cached for a few milliseconds because the sensor delivers hundreds of reports a second.
final class InputIdleMonitor: @unchecked Sendable {
    private static let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    private static let refreshInterval = 0.004

    private let lock = NSLock()
    private var cachedIdle = 1000.0
    private var cachedAt = -Double.infinity

    /// Seconds since the last key press or click, or 1000 when nothing is known.
    func secondsSinceInput() -> Double {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        defer { lock.unlock() }

        if now - cachedAt >= Self.refreshInterval {
            var smallest = 1000.0
            for type in Self.types {
                let value = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
                if value >= 0, value < smallest { smallest = value }
            }
            cachedIdle = smallest
            cachedAt = now
            return smallest
        }
        return cachedIdle + (now - cachedAt)
    }
}
