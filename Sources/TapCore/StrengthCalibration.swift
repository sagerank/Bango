import Foundation

/// Turns a few soft taps and a few hard taps into the level that tells them apart.
public enum StrengthCalibration {
    public struct Fit: Equatable, Sendable {
        /// Taps at or above this peak (g) count as hard.
        public var hardPeak: Double
        public var softMedian: Double
        public var hardMedian: Double
    }

    public enum Failure: Error, Equatable {
        case tooFewTaps
        /// The hard taps were not clearly stronger. `ratio` is hard divided by soft.
        case notDifferentEnough(ratio: Double)
    }

    /// Hard taps must be at least this many times stronger than soft ones, or the two overlap too much.
    public static let minimumRatio = 1.3
    public static let minimumTaps = 3

    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    public static func fit(soft: [Double], hard: [Double]) -> Result<Fit, Failure> {
        guard soft.count >= minimumTaps, hard.count >= minimumTaps else { return .failure(.tooFewTaps) }
        let softMedian = median(soft)
        let hardMedian = median(hard)
        guard softMedian > 0 else { return .failure(.tooFewTaps) }
        let ratio = hardMedian / softMedian
        guard ratio >= minimumRatio else { return .failure(.notDifferentEnough(ratio: ratio)) }
        // The geometric mean sits the same factor above the soft taps as below the hard ones.
        return .success(Fit(hardPeak: (softMedian * hardMedian).squareRoot(), softMedian: softMedian, hardMedian: hardMedian))
    }

    /// A detector threshold that still catches taps as light as the softest ones measured. It never raises
    /// the current threshold, because a higher one can only make light taps vanish.
    public static func suggestedThreshold(lightestMedian: Double, current: Double) -> Double {
        let wanted = min(max(lightestMedian * 0.3, 0.015), 0.06)
        return min(current, wanted)
    }

    /// Strength of a gesture for a given level. Nil when strength detection is off.
    public static func label(peak: Double, hardPeak: Double) -> TapStrength? {
        guard hardPeak > 0 else { return nil }
        return peak >= hardPeak ? .hard : .soft
    }
}
