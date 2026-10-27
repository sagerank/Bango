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

    /// Slowest and fastest repeat, compared with the recorded tempo, that still counts as the same rhythm.
    public static let tempoRange: ClosedRange<Double> = 0.6...1.7
    /// People cannot repeat timing exactly, so every gap may be off by at least this fraction.
    public static let minimumTolerance = 0.5
    /// Smallest allowed error on any gap, in seconds, so very short gaps are not impossible to hit.
    public static let minimumSlack = 0.08

    public init(gaps: [Double], tolerance: Double = 0.5) {
        self.gaps = gaps
        self.tolerance = tolerance
    }

    public var taps: Int { gaps.count + 1 }
    public var maxGap: Double { gaps.max() ?? 0 }

    /// How far a performed set of gaps is from this rhythm, as a multiple of what is allowed.
    /// 1 or less is a match. Nil when the tap count or the overall speed is too different to compare.
    ///
    /// The overall speed is allowed to differ a little, so the same rhythm played slightly faster
    /// or slower on another day still counts. What has to stay the same is the pattern of short and long gaps.
    public func deviation(of other: [Double]) -> Double? {
        guard other.count == gaps.count, !gaps.isEmpty else { return nil }
        let recorded = gaps.reduce(0, +)
        let performed = other.reduce(0, +)
        guard recorded > 0, performed > 0 else { return nil }
        let tempo = performed / recorded
        guard Self.tempoRange.contains(tempo) else { return nil }

        var worst = 0.0
        let fraction = max(tolerance, Self.minimumTolerance)
        for (expected, actual) in zip(gaps, other) {
            let target = expected * tempo
            let allowed = max(Self.minimumSlack, target * fraction)
            worst = max(worst, abs(actual - target) / allowed)
        }
        return worst
    }

    public func matches(_ other: [Double]) -> Bool {
        guard let deviation = deviation(of: other) else { return false }
        return deviation <= 1
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
            for value in values where abs(value - average) > max(0.10, average * 0.4) {
                throw RhythmError.inconsistent
            }
            mean.append(average)
        }
        return RhythmPattern(gaps: mean)
    }
}
