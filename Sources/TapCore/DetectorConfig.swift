import Foundation

/// Tunable detection settings. The starting values were checked on one real MacBook recording and still
/// need confirming on other models, which is what the Tuning screen and calibration are for.
public struct DetectorConfig: Codable, Equatable, Sendable {
    /// Minimum filtered acceleration (g) for a tap. The detector raises this in noisy conditions.
    public var threshold: Double
    /// Minimum time between two accepted impacts, seconds.
    public var cooldown: Double
    /// Silence needed after the last tap before a gesture is complete, seconds.
    public var groupingWindow: Double
    /// Ignore taps that coincide with key presses and clicks.
    public var guardEnabled: Bool
    /// Seconds around a key press or click in which impacts are ignored.
    public var guardWindow: Double
    /// Highest tap count recognized. Extra taps are folded into this count.
    public var maxTaps: Int
    /// Peak (g) at or above which a gesture counts as hard. 0 turns strength detection off.
    public var hardPeak: Double

    public init(
        threshold: Double = 0.03,
        cooldown: Double = 0.12,
        groupingWindow: Double = 0.40,
        guardEnabled: Bool = true,
        guardWindow: Double = 0.20,
        maxTaps: Int = 5,
        hardPeak: Double = 0
    ) {
        self.threshold = threshold
        self.cooldown = cooldown
        self.groupingWindow = groupingWindow
        self.guardEnabled = guardEnabled
        self.guardWindow = guardWindow
        self.maxTaps = maxTaps
        self.hardPeak = hardPeak
    }

    enum CodingKeys: String, CodingKey {
        case threshold, cooldown, groupingWindow, guardEnabled, guardWindow, maxTaps, hardPeak
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DetectorConfig()
        threshold = c.lenient(.threshold, d.threshold)
        cooldown = c.lenient(.cooldown, d.cooldown)
        groupingWindow = c.lenient(.groupingWindow, d.groupingWindow)
        guardEnabled = c.lenient(.guardEnabled, d.guardEnabled)
        guardWindow = c.lenient(.guardWindow, d.guardWindow)
        maxTaps = c.lenient(.maxTaps, d.maxTaps)
        hardPeak = c.lenient(.hardPeak, d.hardPeak)
    }

    /// A copy with every value forced into a sane range.
    public func normalized() -> DetectorConfig {
        var c = self
        c.threshold = min(max(c.threshold, 0.005), 0.2)
        c.cooldown = min(max(c.cooldown, 0.07), 0.5)
        c.groupingWindow = min(max(c.groupingWindow, 0.2), 1.5)
        c.guardWindow = min(max(c.guardWindow, 0), 1)
        c.maxTaps = min(max(c.maxTaps, 1), 5)
        c.hardPeak = max(c.hardPeak, 0)
        return c
    }
}
