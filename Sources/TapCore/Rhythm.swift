import Foundation

public enum RhythmError: Error, Equatable {
    case notEnoughSamples
    case tooFewTaps
    case inconsistent

    public var message: String {
        switch self {
        case .notEnoughSamples: return "Repeat the rhythm at least 3 times."
        case .tooFewTaps: return "A rhythm needs at least 2 taps."
        case .inconsistent: return "The repeats were too different. Keep the same timing each time."
        }
    }
}

/// A tap rhythm such as "tap, tap, pause, tap", stored as the gaps between taps.
public struct RhythmPattern: Codable, Equatable, Hashable, Sendable {
    /// Seconds between consecutive taps. Count is taps - 1.
    public var gaps: [Double]
    /// Allowed deviation as a fraction of each gap (minimum 60 ms).
    public var tolerance: Double

    public init(gaps: [Double], tolerance: Double = 0.35) {
        self.gaps = gaps
        self.tolerance = tolerance
    }

    public var taps: Int { gaps.count + 1 }
    public var maxGap: Double { gaps.max() ?? 0 }

    public func matches(_ other: [Double]) -> Bool {
        guard other.count == gaps.count else { return false }
        for (expected, actual) in zip(gaps, other) {
            if abs(actual - expected) > max(0.06, expected * tolerance) { return false }
        }
        return true
    }

    /// Short description such as "tap, tap, pause, tap".
    public var summary: String {
        var parts = ["tap"]
        for gap in gaps {
            parts.append(gap > 0.5 ? "pause" : "tap")
        }
        return parts.joined(separator: ", ")
    }
}

public enum RhythmLearner {
    /// Builds a pattern from several repeats, each given as its list of gaps.
    public static func learn(repeats: [[Double]]) throws -> RhythmPattern {
        guard repeats.count >= 3 else { throw RhythmError.notEnoughSamples }
        guard let first = repeats.first, !first.isEmpty else { throw RhythmError.tooFewTaps }
        guard repeats.allSatisfy({ $0.count == first.count }) else { throw RhythmError.inconsistent }

        var mean: [Double] = []
        for index in 0..<first.count {
            let values = repeats.map { $0[index] }
            let average = values.reduce(0, +) / Double(values.count)
            for value in values where abs(value - average) > max(0.08, average * 0.35) {
                throw RhythmError.inconsistent
            }
            mean.append(average)
        }
        return RhythmPattern(gaps: mean)
    }
}
