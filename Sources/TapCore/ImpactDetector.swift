import Foundation

/// Direction signature of an impact, used to tell which part of the Mac was tapped.
public struct ImpactFeatures: Equatable, Sendable {
    /// Gyroscope vector at its strongest moment during the impact. Zero when no gyroscope.
    public var gyro: Vec3
    /// High-pass filtered acceleration at its strongest moment during the impact.
    public var accel: Vec3

    public init(gyro: Vec3 = .zero, accel: Vec3 = .zero) {
        self.gyro = gyro
        self.accel = accel
    }

    public var hasGyro: Bool { gyro.length > 1e-9 }

    /// Unit-length, scale-free 6 number description (gyro direction then accel direction).
    /// Empty parts stay zero. Returns all zeros when nothing was measured.
    public var directionVector: [Double] {
        var v = [Double](repeating: 0, count: 6)
        let gl = gyro.length
        let al = accel.length
        if gl > 1e-9 {
            v[0] = gyro.x / gl
            v[1] = gyro.y / gl
            v[2] = gyro.z / gl
        }
        if al > 1e-9 {
            v[3] = accel.x / al
            v[4] = accel.y / al
            v[5] = accel.z / al
        }
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }
}

/// A single accepted tap.
public struct Impact: Equatable, Sendable {
    /// When the tap began (seconds, same clock as the samples).
    public var time: Double
    /// Strongest filtered acceleration (g) in the 60 ms after the tap began.
    public var peak: Double
    public var features: ImpactFeatures

    public init(time: Double, peak: Double, features: ImpactFeatures = ImpactFeatures()) {
        self.time = time
        self.peak = peak
        self.features = features
    }
}

/// Live values for the waveform and diagnostics screens.
public struct DetectorSnapshot: Equatable, Sendable {
    public var x = 0.0
    public var y = 0.0
    public var z = 0.0
    public var magnitude = 0.0
    public var filteredMagnitude = 0.0
    public var threshold = 0.0
    public var sampleRate = 0.0
    public var lastPeak = 0.0
    public var noiseFloor = 0.0
    public var motionLevel = 0.0
    /// True while taps are being ignored because of typing or clicking.
    public var guarded = false
    /// How strongly the newest sample differs from what the ringing of earlier taps predicts.
    public var surprise = 0.0
    /// Why recent bumps were ignored, counted once per bump.
    public var rejections = RejectionCounts()

    public init() {}
}

/// Reasons the detector can ignore a bump that crossed the threshold.
public enum Rejection: String, CaseIterable, Sendable {
    /// Taps too close together.
    case cooldown
    /// The Mac was being moved or carried.
    case motion
    /// The Mac was still shaking from something else.
    case notQuiet
    /// The bump built up slowly, like a push, not a knock.
    case notSharp
    /// The bump lasted too long to be a knock.
    case tooLong
    /// Typing or clicking at the same time.
    case typing

    public var label: String {
        switch self {
        case .cooldown: return "Too close to the last tap"
        case .motion: return "Mac was moving"
        case .notQuiet: return "Not quiet before the tap"
        case .notSharp: return "Too gradual"
        case .tooLong: return "Lasted too long"
        case .typing: return "Typing or clicking"
        }
    }
}

public struct RejectionCounts: Equatable, Sendable {
    public private(set) var counts: [Rejection: Int] = [:]
    public private(set) var last: Rejection?

    public init() {}

    public func count(_ reason: Rejection) -> Int { counts[reason] ?? 0 }
    public var total: Int { counts.values.reduce(0, +) }

    mutating func record(_ reason: Rejection) {
        counts[reason, default: 0] += 1
        last = reason
    }
}

public struct DetectorOutput: Sendable {
    public var snapshot: DetectorSnapshot
    /// Set on the sample where a tap's feature window closes, about 60 ms after the tap began.
    public var impact: Impact?
}

/// Finds individual taps in a stream of accelerometer samples.
///
/// The structure follows the nocnoc detector: a low-pass filter separates gravity and slow
/// movement from sharp impacts, an adaptive threshold follows the noise floor, a motion
/// lockout rejects lifting or carrying the Mac, and a brief-impulse gate rejects long
/// vibrations. Differences: it emits single taps (grouping happens in GestureRecognizer),
/// supports a typing guard, and collects direction features for tap zones.
public final class ImpactDetector {
    private struct Recent {
        var time: Double
        var filtered: Double
        var lowStep: Double
        var lowPass: Vec3
    }

    private struct Pending {
        var time: Double
        var peak: Double
        var gyro: Vec3 = .zero
        var gyroLen: Double = 0
        var accel: Vec3 = .zero
        var accelLen: Double = 0
    }

    private static let quietWindow = 0.28
    private static let motionWindow = 0.40
    private static let impulseWindow = 0.14
    private static let historyWindow = 1.5
    private static let quietTail = 0.03
    private static let motionTail = 0.07
    private static let lockoutDuration = 0.9
    public static let featureWindow = 0.06

    private var lowPass = Vec3.zero
    private var previousSample = Vec3.zero
    private var previousLowPass = Vec3.zero
    private var initialized = false
    private var lastPeak = 0.0
    private var lastAccepted = -Double.infinity
    private var lastTime: Double?
    private var noiseFloor = 0.01
    private var lockoutUntil = -Double.infinity
    private var history: [Recent] = []
    private var pending: Pending?
    private var predictor = RingPredictor()
    private var rejections = RejectionCounts()
    private var episode: Episode?

    /// A run of samples above the threshold that was not accepted as a tap.
    private struct Episode {
        var accepted = false
        var peak = 0.0
        var reason: Rejection?
    }

    public init() {}

    public func reset() {
        lowPass = .zero
        previousSample = .zero
        previousLowPass = .zero
        initialized = false
        lastPeak = 0
        lastAccepted = -Double.infinity
        lastTime = nil
        noiseFloor = 0.01
        lockoutUntil = -Double.infinity
        history.removeAll()
        pending = nil
        predictor.reset()
        rejections = RejectionCounts()
        episode = nil
    }

    public func process(_ s: SensorSample, config: DetectorConfig) -> DetectorOutput {
        let now = s.time
        let sample = s.accel

        if !initialized {
            lowPass = sample
            previousSample = sample
            previousLowPass = sample
            initialized = true
        }

        var sampleRate = 0.0
        if let previous = lastTime {
            sampleRate = 1.0 / max(now - previous, 0.0001)
        }
        lastTime = now

        lowPass = lowPass + (sample - lowPass) * 0.08
        let lowStep = (lowPass - previousLowPass).length
        previousLowPass = lowPass
        let highPass = sample - lowPass
        let jerk = sample - previousSample
        previousSample = sample

        let highPassMagnitude = highPass.length
        let jerkMagnitude = jerk.length
        let filtered = max(highPassMagnitude, jerkMagnitude * 0.92)
        let surprise = predictor.update(highPass)

        history.append(Recent(time: now, filtered: filtered, lowStep: lowStep, lowPass: lowPass))
        while let first = history.first, now - first.time > Self.historyWindow {
            history.removeFirst()
        }

        let sequenceOpen = now - lastAccepted <= config.groupingWindow
        // While a tap sequence is open the ringing of the previous taps must not raise the noise floor.
        let adaptive = sequenceOpen
            ? currentThreshold(base: config.threshold)
            : updateAdaptiveThreshold(base: config.threshold, signal: filtered)

        let quiet = window(within: Self.quietWindow, now: now, excludingTail: Self.quietTail)
        let quietValues = quiet.map { $0.filtered }
        let quietAverage = quietValues.isEmpty ? 0 : quietValues.reduce(0, +) / Double(quietValues.count)
        let quietMax = quietValues.max() ?? 0

        let motion = window(within: Self.motionWindow, now: now, excludingTail: Self.motionTail)
        let lowMotion = motion.isEmpty ? 0 : motion.reduce(0) { $0 + $1.lowStep } / Double(motion.count)
        var drift = 0.0
        if let earliest = motion.first {
            drift = (lowPass - earliest.lowPass).length
        }

        if !sequenceOpen {
            let lowLimit = max(0.010, adaptive * 0.08)
            let driftLimit = max(0.080, adaptive * 0.55)
            if lowMotion > lowLimit || drift > driftLimit {
                lockoutUntil = max(lockoutUntil, now + Self.lockoutDuration)
            }
        }
        let inLockout = now < lockoutUntil

        let impulse = window(within: Self.impulseWindow, now: now, excludingTail: 0)
        let impulseDuration = durationAbove(
            impulse,
            threshold: adaptive * 0.55,
            fallback: sampleRate > 0 ? 1.0 / sampleRate : 0.01
        )

        let baselineQuiet = quietAverage < adaptive * 0.28 && quietMax < adaptive * 0.72
        // The first tap must look like a knock: sharp and short, after a quiet moment.
        // Follow-up taps land on top of the ringing of the previous one, so they are judged
        // by how far they depart from what that ringing predicts.
        let sharp: Bool
        let brief: Bool
        if sequenceOpen {
            sharp = surprise > adaptive * Self.surpriseRatio
            brief = true
        } else {
            sharp = jerkMagnitude > adaptive * 0.70 || jerkMagnitude > highPassMagnitude * 0.90
            brief = impulseDuration <= 0.08
        }
        let passesSequence = sequenceOpen || baselineQuiet
        let guarded = config.guardEnabled && s.inputIdle < config.guardWindow
        let cooldown = max(config.cooldown, Self.featureWindow + 0.01)
        let cooled = now - lastAccepted >= cooldown

        var accepted = false
        if filtered > adaptive,
           cooled,
           !inLockout,
           passesSequence,
           sharp,
           brief,
           !guarded,
           pending == nil
        {
            lastAccepted = now
            lastPeak = filtered
            pending = Pending(time: now, peak: filtered)
            accepted = true
        }

        let blocker: Rejection? = {
            if guarded { return .typing }
            if inLockout { return .motion }
            if !cooled { return .cooldown }
            if !passesSequence { return .notQuiet }
            if !sharp { return .notSharp }
            if !brief { return .tooLong }
            return nil
        }()
        trackRejections(filtered: filtered, threshold: adaptive, accepted: accepted, blocker: blocker)

        var impact: Impact?
        if var p = pending {
            p.peak = max(p.peak, filtered)
            if let g = s.gyro {
                let length = g.length
                if length > p.gyroLen {
                    p.gyro = g
                    p.gyroLen = length
                }
            }
            if highPassMagnitude > p.accelLen {
                p.accel = highPass
                p.accelLen = highPassMagnitude
            }
            if now - p.time >= Self.featureWindow {
                lastPeak = p.peak
                impact = Impact(
                    time: p.time,
                    peak: p.peak,
                    features: ImpactFeatures(gyro: p.gyro, accel: p.accel)
                )
                pending = nil
            } else {
                pending = p
            }
        }

        var snapshot = DetectorSnapshot()
        snapshot.x = sample.x
        snapshot.y = sample.y
        snapshot.z = sample.z
        snapshot.magnitude = sample.length
        snapshot.filteredMagnitude = filtered
        snapshot.threshold = adaptive
        snapshot.sampleRate = sampleRate
        snapshot.lastPeak = lastPeak
        snapshot.noiseFloor = noiseFloor
        snapshot.motionLevel = max(lowMotion, drift)
        snapshot.guarded = guarded
        snapshot.surprise = surprise
        snapshot.rejections = rejections
        return DetectorOutput(snapshot: snapshot, impact: impact)
    }

    // MARK: - Helpers

    /// Samples from the last `duration` seconds, oldest first, skipping the newest `tail` seconds.
    private func window(within duration: Double, now: Double, excludingTail tail: Double) -> [Recent] {
        var out: [Recent] = []
        var index = history.count - 1
        while index >= 0 {
            let age = now - history[index].time
            if age > duration { break }
            if age >= tail { out.append(history[index]) }
            index -= 1
        }
        return Array(out.reversed())
    }

    private static let surpriseRatio = 0.8

    private func currentThreshold(base: Double) -> Double {
        max(base, noiseFloor * 3.2 + 0.015)
    }

    /// Counts one rejection per bump that crossed the threshold but never became a tap.
    private func trackRejections(filtered: Double, threshold: Double, accepted: Bool, blocker: Rejection?) {
        if filtered > threshold {
            var e = episode ?? Episode()
            if accepted { e.accepted = true }
            if let blocker, filtered >= e.peak {
                e.peak = filtered
                e.reason = blocker
            }
            episode = e
        } else if filtered < threshold * 0.5, let e = episode {
            if !e.accepted, let reason = e.reason { rejections.record(reason) }
            episode = nil
        }
    }

    private func updateAdaptiveThreshold(base: Double, signal: Double) -> Double {
        let capped = min(signal, max(base * 0.9, noiseFloor * 2.5))
        noiseFloor = noiseFloor * 0.97 + capped * 0.03
        return max(base, noiseFloor * 3.2 + 0.015)
    }

    private func durationAbove(_ samples: [Recent], threshold: Double, fallback: Double) -> Double {
        var total = 0.0
        for (index, s) in samples.enumerated() where s.filtered > threshold {
            if index > 0 {
                total += max(s.time - samples[index - 1].time, 0)
            } else {
                total += fallback
            }
        }
        return total
    }
}

/// Predicts the next sample from the last few, per axis, with a normalized LMS filter.
///
/// The ringing of a knocked chassis is a sum of fading sine waves, which a short linear
/// predictor learns within a few milliseconds. A new knock is not predictable, so it shows
/// up as a large prediction error even while the old ringing is still louder than the noise.
struct RingPredictor {
    static let order = 12
    private static let step = 0.4
    private static let regularization = 1e-4

    private var weights = [[Double]](repeating: [Double](repeating: 0, count: order), count: 3)
    private var history = [[Double]](repeating: [Double](repeating: 0, count: order), count: 3)

    mutating func reset() {
        for axis in 0..<3 {
            for i in 0..<Self.order {
                weights[axis][i] = 0
                history[axis][i] = 0
            }
        }
    }

    /// Feeds the next high-pass sample and returns the size of the prediction error.
    mutating func update(_ x: Vec3) -> Double {
        let values = [x.x, x.y, x.z]
        var errorSquared = 0.0
        for axis in 0..<3 {
            var predicted = 0.0
            var energy = Self.regularization
            for i in 0..<Self.order {
                predicted += weights[axis][i] * history[axis][i]
                energy += history[axis][i] * history[axis][i]
            }
            let error = values[axis] - predicted
            errorSquared += error * error
            let gain = Self.step * error / energy
            for i in 0..<Self.order {
                weights[axis][i] += gain * history[axis][i]
            }
            for i in stride(from: Self.order - 1, to: 0, by: -1) {
                history[axis][i] = history[axis][i - 1]
            }
            history[axis][0] = values[axis]
        }
        let result = errorSquared.squareRoot()
        if !result.isFinite {
            reset()
            return 0
        }
        return result
    }
}
