import Foundation

/// Which part of the Mac was tapped. `.any` means unknown (when detected) or "do not care" (in a binding).
public enum TapZone: String, Codable, CaseIterable, Sendable {
    case any, left, right, top

    public var title: String {
        switch self {
        case .any: return "Anywhere"
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        }
    }
}

/// How hard the Mac was tapped. `.any` means not measured (when detected) or "do not care" (in a binding).
public enum TapStrength: String, Codable, CaseIterable, Sendable {
    case any, soft, hard

    public var title: String {
        switch self {
        case .any: return "Any strength"
        case .soft: return "Soft"
        case .hard: return "Hard"
        }
    }
}

/// A finished group of taps.
public struct RecognizedGesture: Equatable, Sendable {
    public var taps: Int
    public var zone: TapZone
    public var strength: TapStrength
    /// Seconds between consecutive taps (count is taps - 1).
    public var gaps: [Double]
    /// Average peak of the taps, in g.
    public var peak: Double
    /// Time of the last tap.
    public var time: Double

    public init(
        taps: Int,
        zone: TapZone = .any,
        strength: TapStrength = .any,
        gaps: [Double] = [],
        peak: Double = 0,
        time: Double = 0
    ) {
        self.taps = taps
        self.zone = zone
        self.strength = strength
        self.gaps = gaps
        self.peak = peak
        self.time = time
    }
}

/// Groups taps into gestures and applies the second layer of the typing guard.
public final class GestureRecognizer {
    private var impacts: [Impact] = []
    private var inputTimes: [Double] = []

    public init() {}

    public func reset() {
        impacts.removeAll()
        inputTimes.removeAll()
    }

    /// Call for every sample so the recognizer knows when the user typed or clicked.
    public func noteInput(sampleTime: Double, idle: Double) {
        guard idle < 5 else { return }
        let eventTime = sampleTime - idle
        if let last = inputTimes.last, abs(eventTime - last) < 0.02 { return }
        inputTimes.append(eventTime)
        inputTimes.removeAll { sampleTime - $0 > 3.0 }
    }

    public func add(_ impact: Impact) {
        impacts.append(impact)
    }

    /// Returns a gesture once `groupingWindow` seconds have passed since the last tap.
    public func poll(
        now: Double,
        config: DetectorConfig,
        groupingWindow: Double,
        zones: ZoneModel?
    ) -> RecognizedGesture? {
        guard let last = impacts.last, now - last.time >= groupingWindow else { return nil }
        let group = impacts
        impacts.removeAll()

        if config.guardEnabled {
            for impact in group {
                if inputTimes.contains(where: { abs($0 - impact.time) <= config.guardWindow }) {
                    return nil
                }
            }
        }

        let limit = min(max(config.maxTaps, 1), 5)
        let taps = min(group.count, limit)
        var gaps: [Double] = []
        if group.count > 1 {
            for index in 1..<group.count {
                gaps.append(group[index].time - group[index - 1].time)
            }
        }
        if gaps.count > taps - 1 {
            gaps = Array(gaps.prefix(max(taps - 1, 0)))
        }

        let meanPeak = group.reduce(0) { $0 + $1.peak } / Double(group.count)
        var strength = TapStrength.any
        if config.hardPeak > 0 {
            strength = meanPeak >= config.hardPeak ? .hard : .soft
        }

        var zone = TapZone.any
        if let zones {
            var votes: [TapZone: Int] = [:]
            for impact in group {
                let z = zones.classify(impact.features)
                if z != .any { votes[z, default: 0] += 1 }
            }
            if let best = votes.max(by: { $0.value < $1.value }), best.value * 2 > group.count {
                zone = best.key
            }
        }

        return RecognizedGesture(
            taps: taps,
            zone: zone,
            strength: strength,
            gaps: gaps,
            peak: meanPeak,
            time: last.time
        )
    }
}
