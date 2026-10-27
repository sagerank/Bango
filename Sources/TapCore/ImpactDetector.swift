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
    /// How far the newest sample stands above the signal level of the last 50 ms. A new knock on top of
    /// ringing shows up as a ratio well above 1, the decaying ring itself does not.
    public var rise = 0.0
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
/// How it works, in the order a sample passes through it:
///
/// 1. **Dynamic motion.** A fast gravity follower (time constant 20 ms) is subtracted from the sample,
///    which leaves what is moving quickly: knocks, ringing and vibration.
/// 2. **Two envelopes.** `fast` jumps up at once and falls back over 6 ms. `slow` follows `fast` over 50 ms
///    and stands for the recent signal level, which is the ringing left by earlier taps.
/// 3. **Noise floor.** Every 20 ms the loudest `fast` value is put in a bucket. The floor is the lower
///    quartile of the last 100 buckets (two seconds). Buckets that hold taps or their ringing are left out,
///    so a burst of taps cannot raise the bar for its own next tap. The threshold sits above the floor.
/// 4. **A tap is an abrupt jump.** `fast` has to be several times higher than it was 8 ms earlier.
///    A first tap must also come out of calm: the 120 ms before it have to be quiet, which separates a knock from
///    the start of a vibration. A follow-up tap lands on ringing, so it only has to stand out from the signal
///    level instead of coming out of calm.
/// 5. **Carrying.** A second, slow gravity follower (250 ms) is compared with where it was half a second
///    earlier. If the Mac was tilted or lifted, taps are ignored for a while.
/// 6. **Warm-up.** For the first 0.4 s nothing is accepted, because the noise floor is still a guess.
/// 7. **Guard and spacing.** A tap that coincides with typing or clicking, or comes too soon after the last
///    one, is ignored.
///
/// The impact is reported 60 ms after it started, once its strongest moment and direction are known.
/// Grouping into double, triple taps and so on happens later, in `GestureRecognizer`.
public final class ImpactDetector {
    private struct Pending {
        var time: Double
        var peak: Double
        var gyro: Vec3 = .zero
        var gyroLen: Double = 0
        var accel: Vec3 = .zero
        var accelLen: Double = 0
    }

    /// A fixed-size ring of timestamped values, so storing a sample never allocates.
    private struct Ring<Value> {
        private var times: [Double]
        private var values: [Value]
        private var start = 0
        private(set) var count = 0

        init(capacity: Int, filler: Value) {
            times = [Double](repeating: 0, count: capacity)
            values = [Value](repeating: filler, count: capacity)
        }

        var isEmpty: Bool { count == 0 }

        mutating func removeAll() {
            start = 0
            count = 0
        }

        mutating func append(_ time: Double, _ value: Value) {
            if count == times.count {
                start = (start + 1) % times.count
                count -= 1
            }
            let slot = (start + count) % times.count
            times[slot] = time
            values[slot] = value
            count += 1
        }

        /// Drops entries older than `age` seconds before `now`.
        mutating func trim(now: Double, keeping age: Double) {
            while count > 0, now - times[start] > age {
                start = (start + 1) % times.count
                count -= 1
            }
        }

        /// The entry `index` places from the oldest.
        func entry(_ index: Int) -> (time: Double, value: Value) {
            let slot = (start + index) % times.count
            return (times[slot], values[slot])
        }
    }

    // Time constants (seconds).
    private static let gravityTau = 0.02
    private static let fastRelease = 0.006
    private static let slowTau = 0.05
    private static let carryTau = 0.25
    // Carry check.
    private static let carryLag = 0.5
    private static let carryLimit = 0.05
    private static let carryHold = 0.8
    /// Seconds after the first sample in which nothing is accepted, so the noise floor can learn the room first.
    private static let warmup = 0.4
    // Noise floor.
    private static let bucketLength = 0.02
    private static let bucketCount = 100
    private static let floorQuantile = 0.25
    private static let floorFactor = 5.0
    private static let floorOffset = 0.012
    /// After a tap, the chassis rings for about this long. Ringing is kept out of the noise floor.
    private static let settleTime = 0.3
    // Tap shape.
    private static let calmFraction = 0.35
    private static let preCalmFraction = 0.5
    private static let preCalmRatio = 0.4
    private static let preWindow = 0.15
    private static let preGap = 0.03
    private static let firstJump = 3.0
    private static let followJump = 2.0
    private static let followRise = 2.0
    private static let jumpWindow = 0.008
    public static let featureWindow = 0.06

    private var gravity = Vec3.zero
    private var slowGravity = Vec3.zero
    private var initialized = false
    private var lastTime: Double?
    private var startTime = 0.0
    private var fast = 0.0
    private var slow = 0.0
    private var lastAccepted = -Double.infinity
    private var lastPeak = 0.0
    private var lockoutUntil = -Double.infinity
    private var pending: Pending?
    private var carryDrift = 0.0

    private var recent = Ring<Double>(capacity: 512, filler: 0)
    private var slowGravityHistory = Ring<Vec3>(capacity: 64, filler: .zero)
    private var bucketStart = 0.0
    private var bucketPeak = 0.0
    private var bucketValues: [Double] = []
    private var floor = 0.005

    private var rejections = RejectionCounts()
    private var episode: Episode?

    /// A run of samples above the threshold that was not accepted as a tap.
    private struct Episode {
        var accepted = false
        var peak = 0.0
        var reason: Rejection?
    }

    public init() {
        bucketValues.reserveCapacity(Self.bucketCount + 1)
    }

    public func reset() {
        gravity = .zero
        slowGravity = .zero
        initialized = false
        lastTime = nil
        startTime = 0
        fast = 0
        slow = 0
        lastAccepted = -Double.infinity
        lastPeak = 0
        lockoutUntil = -Double.infinity
        pending = nil
        carryDrift = 0
        recent.removeAll()
        slowGravityHistory.removeAll()
        bucketStart = 0
        bucketPeak = 0
        bucketValues.removeAll(keepingCapacity: true)
        floor = 0.005
        rejections = RejectionCounts()
        episode = nil
    }

    public func process(_ s: SensorSample, config: DetectorConfig) -> DetectorOutput {
        let now = s.time
        let sample = s.accel

        if !initialized {
            gravity = sample
            slowGravity = sample
            bucketStart = now
            startTime = now
            initialized = true
        }

        var sampleRate = 0.0
        var elapsed = 0.00125
        if let previous = lastTime {
            elapsed = max(now - previous, 0.0001)
            sampleRate = 1.0 / elapsed
        }
        lastTime = now

        // 1. What is moving quickly.
        gravity = gravity + (sample - gravity) * (1 - exp(-elapsed / Self.gravityTau))
        let dynamic = sample - gravity
        let magnitude = dynamic.length

        // 2. Envelopes. `slow` is read before this sample changes it: it is the level the tap rises from.
        let slowBefore = slow
        fast = max(magnitude, fast * exp(-elapsed / Self.fastRelease))
        slow += (fast - slow) * (1 - exp(-elapsed / Self.slowTau))
        recent.append(now, fast)
        recent.trim(now: now, keeping: Self.preWindow)

        // 5. Carrying: has the slow gravity direction moved over the last half second?
        slowGravity = slowGravity + (sample - slowGravity) * (1 - exp(-elapsed / Self.carryTau))
        if slowGravityHistory.isEmpty || now - slowGravityHistory.entry(slowGravityHistory.count - 1).time >= 0.025 {
            slowGravityHistory.append(now, slowGravity)
        }
        slowGravityHistory.trim(now: now, keeping: Self.carryLag)
        carryDrift = slowGravityHistory.isEmpty ? 0 : (slowGravity - slowGravityHistory.entry(0).value).length
        let sequenceOpen = now - lastAccepted <= config.groupingWindow
        if carryDrift > Self.carryLimit, !sequenceOpen {
            lockoutUntil = max(lockoutUntil, now + Self.carryHold)
        }
        let inLockout = now < lockoutUntil

        // 3. Noise floor and threshold.
        updateFloor(now: now)
        let threshold = max(config.threshold, floor * Self.floorFactor + Self.floorOffset)

        // 4. Is this an abrupt jump?
        let guarded = config.guardEnabled && s.inputIdle < config.guardWindow
        let spacing = max(config.cooldown, Self.featureWindow + 0.01)
        let spaced = now - lastAccepted >= spacing
        var accepted = false
        var blocker: Rejection?

        if pending == nil, fast > threshold {
            if guarded {
                blocker = .typing
            } else if inLockout {
                blocker = .motion
            } else if !spaced {
                blocker = .cooldown
            } else if now - startTime < Self.warmup {
                // The noise floor has not learned the room yet, so the threshold is only a guess.
                blocker = .notQuiet
            } else {
                let jumpFactor = sequenceOpen ? Self.followJump : Self.firstJump
                let jumped = fast >= jumpFactor * max(valueBefore(now: now), 0.0001)
                if !jumped {
                    blocker = .notSharp
                } else if sequenceOpen {
                    if fast >= Self.followRise * max(slowBefore, 0.0001) {
                        accepted = true
                    } else {
                        blocker = .notSharp
                    }
                } else if slowBefore < threshold * Self.calmFraction,
                          quietBefore(now: now) < min(threshold * Self.preCalmFraction, Self.preCalmRatio * fast)
                {
                    accepted = true
                } else {
                    blocker = .notQuiet
                }
            }
            if accepted {
                lastAccepted = now
                lastPeak = fast
                pending = Pending(time: now, peak: fast)
            }
        }
        // Wiggles in the ringing of a tap we just accepted are not separate bumps worth reporting.
        let ringing = now - lastAccepted < Self.settleTime
        let ringWiggle = ringing && (blocker == .notSharp || blocker == .cooldown)
        trackRejections(
            fast: fast, threshold: threshold, accepted: accepted,
            blocker: ringWiggle ? nil : blocker
        )

        var impact: Impact?
        if var p = pending {
            p.peak = max(p.peak, fast)
            if let g = s.gyro {
                let length = g.length
                if length > p.gyroLen {
                    p.gyro = g
                    p.gyroLen = length
                }
            }
            if magnitude > p.accelLen {
                p.accel = dynamic
                p.accelLen = magnitude
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
        snapshot.filteredMagnitude = fast
        snapshot.threshold = threshold
        snapshot.sampleRate = sampleRate
        snapshot.lastPeak = lastPeak
        snapshot.noiseFloor = floor
        snapshot.motionLevel = carryDrift
        snapshot.guarded = guarded
        snapshot.rise = fast / max(slowBefore, 0.001)
        snapshot.rejections = rejections
        return DetectorOutput(snapshot: snapshot, impact: impact)
    }

    // MARK: - Helpers

    /// The `fast` value from about 8 ms ago (the newest entry at least that old, or the oldest there is).
    private func valueBefore(now: Double) -> Double {
        var index = recent.count - 1
        while index > 0, now - recent.entry(index).time < Self.jumpWindow { index -= 1 }
        return index >= 0 ? recent.entry(index).value : fast
    }

    /// The loudest `fast` value in the 120 ms that ended 30 ms ago.
    private func quietBefore(now: Double) -> Double {
        var loudest = 0.0
        var index = recent.count - 1
        while index >= 0 {
            let e = recent.entry(index)
            if now - e.time >= Self.preGap { loudest = max(loudest, e.value) }
            index -= 1
        }
        return loudest
    }

    /// Closes a 20 ms bucket now and then, and takes the floor from the quieter buckets.
    private func updateFloor(now: Double) {
        bucketPeak = max(bucketPeak, fast)
        guard now - bucketStart >= Self.bucketLength else { return }
        let ringing = now - lastAccepted < Self.settleTime
        // Buckets that hold a tap, or the ringing after one, say nothing about the room.
        if !ringing, bucketPeak <= floor * 3 + 0.03 {
            bucketValues.append(bucketPeak)
            if bucketValues.count > Self.bucketCount { bucketValues.removeFirst() }
        }
        bucketPeak = 0
        bucketStart = now
        if !bucketValues.isEmpty {
            let sorted = bucketValues.sorted()
            floor = sorted[min(Int(Double(sorted.count) * Self.floorQuantile), sorted.count - 1)]
        }
    }

    /// Counts one rejection per bump that crossed the threshold but never became a tap.
    private func trackRejections(fast: Double, threshold: Double, accepted: Bool, blocker: Rejection?) {
        if fast > threshold {
            var e = episode ?? Episode()
            if accepted { e.accepted = true }
            if let blocker, fast >= e.peak {
                e.peak = fast
                e.reason = blocker
            }
            episode = e
        } else if fast < threshold * 0.5, let e = episode {
            if !e.accepted, let reason = e.reason { rejections.record(reason) }
            episode = nil
        }
    }
}
