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

    public init() {}
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

        history.append(Recent(time: now, filtered: filtered, lowStep: lowStep, lowPass: lowPass))
        while let first = history.first, now - first.time > Self.historyWindow {
            history.removeFirst()
        }

        let adaptive = updateAdaptiveThreshold(base: config.threshold, signal: filtered)
        let sequenceOpen = now - lastAccepted <= config.groupingWindow

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
        let sharp = jerkMagnitude > adaptive * 0.70 || jerkMagnitude > highPassMagnitude * 0.90
        let brief = impulseDuration <= (sequenceOpen ? 0.11 : 0.08)
        let passesSequence = sequenceOpen || baselineQuiet
        let guarded = config.guardEnabled && s.inputIdle < config.guardWindow
        let cooldown = max(config.cooldown, Self.featureWindow + 0.01)

        if filtered > adaptive,
           now - lastAccepted >= cooldown,
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
        }

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
