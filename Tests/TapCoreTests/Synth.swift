import Foundation
@testable import TapCore

/// Small deterministic random source so tests give the same result on every run and platform.
struct SplitMix {
    var state: UInt64

    mutating func nextUInt() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform() -> Double {
        Double(nextUInt() >> 11) / 9_007_199_254_740_992.0
    }

    /// Approximately standard normal.
    mutating func gauss() -> Double {
        var sum = 0.0
        for _ in 0..<12 { sum += uniform() }
        return sum - 6.0
    }
}

struct SynthTap {
    var time: Double
    /// Peak acceleration of the burst in g.
    var amp: Double = 0.12
    /// Direction of the acceleration burst.
    var accelDir = Vec3(0.3, -0.2, 1)
    /// Direction of the gyroscope burst, when the test has gyro data.
    var gyroDir: Vec3? = nil
    /// How long the chassis keeps ringing after the knock (seconds until the ring fades to 37%).
    /// Real laptops ring longer than the 12 ms default, which is what makes fast taps hard to separate.
    var decay: Double = 0.012
    /// Ring frequencies in Hz. Several frequencies make the ringing beat, like a real chassis.
    var frequencies: [Double] = [70]
}

enum Synth {
    static let rate = 800.0

    /// A resting MacBook (gravity on z) with optional taps, a slow tilt, and typing events.
    static func signal(
        duration: Double,
        taps: [SynthTap] = [],
        noise: Double = 0.002,
        seed: UInt64 = 7,
        tilt: (start: Double, end: Double, dx: Double)? = nil,
        inputEvents: [Double] = [],
        withGyro: Bool = false
    ) -> [SensorSample] {
        var rng = SplitMix(state: seed)
        let count = Int(duration * rate)
        var out: [SensorSample] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i) / rate
            var a = Vec3(rng.gauss() * noise, rng.gauss() * noise, -1 + rng.gauss() * noise)
            var g = Vec3(rng.gauss() * noise, rng.gauss() * noise, rng.gauss() * noise)

            for tap in taps {
                let d = t - tap.time
                if d >= 0 {
                    let share = 1.0 / Double(tap.frequencies.count)
                    var burst = 0.0
                    for (k, hz) in tap.frequencies.enumerated() {
                        burst += share * exp(-d / tap.decay) * sin(2 * Double.pi * hz * d + Double(k))
                    }
                    if tap.frequencies.count == 1 { burst = exp(-d / tap.decay) * sin(2 * Double.pi * tap.frequencies[0] * d) }
                    a = a + tap.accelDir * (tap.amp * burst)
                    if let gd = tap.gyroDir {
                        g = g + gd * (tap.amp * 10 * burst)
                    }
                }
            }
            if let tilt, t >= tilt.start {
                let fraction = min((t - tilt.start) / (tilt.end - tilt.start), 1)
                a.x += tilt.dx * fraction
            }

            var idle = 1000.0
            for event in inputEvents where t >= event {
                idle = min(idle, t - event)
            }
            out.append(SensorSample(time: t, accel: a, gyro: withGyro ? g : nil, inputIdle: idle))
        }
        return out
    }

    /// Evenly spaced taps.
    static func run(
        start: Double, count: Int, spacing: Double, amp: Double = 0.12,
        decay: Double = 0.012, frequencies: [Double] = [70]
    ) -> [SynthTap] {
        (0..<count).map {
            SynthTap(time: start + Double($0) * spacing, amp: amp, decay: decay, frequencies: frequencies)
        }
    }
}
