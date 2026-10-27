import XCTest
@testable import TapCore

/// Things that are not taps must stay silent, now that follow-up taps are judged on a rise over the ringing.
final class FalsePositiveTests: XCTestCase {
    private func impacts(_ samples: [SensorSample]) -> Int {
        Replay.impacts(samples, config: PipelineConfig()).count
    }

    private func signal(
        duration: Double, noise: Double = 0.002,
        extra: (Double) -> Vec3
    ) -> [SensorSample] {
        var rng = SplitMix(state: 11)
        return (0..<Int(duration * Synth.rate)).map { i in
            let t = Double(i) / Synth.rate
            let n = Vec3(rng.gauss() * noise, rng.gauss() * noise, -1 + rng.gauss() * noise)
            return SensorSample(time: t, accel: n + extra(t))
        }
    }

    func testSteadyVibrationIsNotATap() {
        for hz in [25.0, 40, 60, 90] {
            for amp in [0.05, 0.15, 0.3] {
                let s = signal(duration: 5) { t in
                    let ramp = min(max((t - 1) / 0.6, 0), 1)
                    let v = amp * ramp * sin(2 * Double.pi * hz * t)
                    return Vec3(v, v * 0.6, v * 0.8)
                }
                XCTAssertEqual(impacts(s), 0, "\(hz) Hz at \(amp) g")
            }
        }
    }

    func testLiftingAndCarryingTheMacIsNotATap() {
        let s = signal(duration: 5, noise: 0.01) { t in
            let lift = min(max((t - 1) / 0.5, 0), 1)
            let sway = lift * 0.12 * sin(2 * Double.pi * 1.8 * t)
            return Vec3(0.45 * lift + sway, 0.2 * lift, 0.3 * lift + sway * 0.7)
        }
        XCTAssertEqual(impacts(s), 0)
    }

    func testSettingTheMacDownStaysQuiet() {
        // A slow tilt back to flat after being held.
        let s = signal(duration: 4) { t in
            let back = min(max((t - 1) / 0.8, 0), 1)
            return Vec3(0.4 * (1 - back), 0, 0.25 * (1 - back))
        }
        XCTAssertEqual(impacts(s), 0)
    }

    func testTypingOnTheTableIsIgnoredByTheGuard() {
        var events: [Double] = []
        var t = 1.0
        while t < 5 { events.append(t); t += 0.14 }
        let taps = events.map { SynthTap(time: $0, amp: 0.06, decay: 0.02) }
        let s = Synth.signal(duration: 6, taps: taps, inputEvents: events)
        XCTAssertEqual(impacts(s), 0)
    }

    func testRingingAloneNeverMakesASecondTap() {
        for decay in [0.02, 0.05, 0.1, 0.2] {
            for hz in [35.0, 50, 70, 110] {
                let s = Synth.signal(
                    duration: 4,
                    taps: [SynthTap(time: 1, amp: 0.2, decay: decay, frequencies: [hz, hz * 1.4])]
                )
                XCTAssertEqual(impacts(s), 1, "decay \(decay) s at \(hz) Hz")
            }
        }
    }
}
