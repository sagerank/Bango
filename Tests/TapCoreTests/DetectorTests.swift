import XCTest
@testable import TapCore

final class DetectorTests: XCTestCase {
    private func impacts(_ samples: [SensorSample], _ config: PipelineConfig = PipelineConfig()) -> [Impact] {
        Replay.impacts(samples, config: config)
    }

    func testQuietSignalProducesNoTaps() {
        XCTAssertEqual(impacts(Synth.signal(duration: 3)).count, 0)
    }

    func testSingleTapIsFoundAtTheRightTime() {
        let result = impacts(Synth.signal(duration: 3, taps: [SynthTap(time: 1.5)]))
        XCTAssertEqual(result.count, 1)
        if let first = result.first {
            XCTAssertEqual(first.time, 1.5, accuracy: 0.02)
            XCTAssertGreaterThan(first.peak, 0.03)
        }
    }

    func testFourFastTapsAreAllFound() {
        let taps = Synth.run(start: 1.5, count: 4, spacing: 0.15)
        XCTAssertEqual(impacts(Synth.signal(duration: 4, taps: taps)).count, 4)
    }

    func testFiveFastTapsAreAllFound() {
        let taps = Synth.run(start: 1.5, count: 5, spacing: 0.15)
        XCTAssertEqual(impacts(Synth.signal(duration: 4, taps: taps)).count, 5)
    }

    func testSlowTiltIsNotATap() {
        let signal = Synth.signal(duration: 3, tilt: (start: 1.5, end: 2.0, dx: 0.3))
        XCTAssertEqual(impacts(signal).count, 0)
    }

    func testTapWhileTypingIsIgnored() {
        let signal = Synth.signal(duration: 3, taps: [SynthTap(time: 1.5)], inputEvents: [1.48])
        XCTAssertEqual(impacts(signal).count, 0)
    }

    func testTapHalfASecondAfterTypingIsAccepted() {
        let signal = Synth.signal(duration: 3, taps: [SynthTap(time: 1.5)], inputEvents: [1.0])
        XCTAssertEqual(impacts(signal).count, 1)
    }

    func testGuardCanBeTurnedOff() {
        var config = PipelineConfig()
        config.detector.guardEnabled = false
        let signal = Synth.signal(duration: 3, taps: [SynthTap(time: 1.5)], inputEvents: [1.48])
        XCTAssertEqual(impacts(signal, config).count, 1)
    }

    func testHigherThresholdIgnoresLightTap() {
        var config = PipelineConfig()
        config.detector.threshold = 0.2
        let signal = Synth.signal(duration: 3, taps: [SynthTap(time: 1.5)])
        XCTAssertEqual(impacts(signal, config).count, 0)
    }

    func testResetClearsState() {
        let detector = ImpactDetector()
        for sample in Synth.signal(duration: 1) {
            _ = detector.process(sample, config: DetectorConfig())
        }
        detector.reset()
        let result = detector.process(
            SensorSample(time: 0, accel: Vec3(0, 0, -1)),
            config: DetectorConfig()
        )
        XCTAssertNil(result.impact)
        XCTAssertEqual(result.snapshot.sampleRate, 0)
    }
}

/// Real chassis keep ringing after a knock. Follow-up taps arrive on top of that ringing.
final class RingingChassisTests: XCTestCase {
    private func gestureCounts(
        taps: Int, spacing: Double, decay: Double, frequencies: [Double] = [70]
    ) -> [Int] {
        let list = Synth.run(start: 1.5, count: taps, spacing: spacing, decay: decay, frequencies: frequencies)
        let signal = Synth.signal(duration: 1.5 + Double(taps) * spacing + 1.5, taps: list)
        return Replay.run(signal, config: PipelineConfig()).map { $0.taps }
    }

    func testEveryTapCountSurvivesLongRinging() {
        for decay in [0.03, 0.06, 0.10, 0.16] {
            for taps in 1...5 {
                XCTAssertEqual(
                    gestureCounts(taps: taps, spacing: 0.2, decay: decay), [taps],
                    "\(taps) taps with ring decay \(decay) s"
                )
            }
        }
    }

    func testFastTapsSurviveModerateRinging() {
        for decay in [0.03, 0.06, 0.10] {
            for taps in 2...5 {
                XCTAssertEqual(
                    gestureCounts(taps: taps, spacing: 0.15, decay: decay), [taps],
                    "\(taps) fast taps with ring decay \(decay) s"
                )
            }
        }
    }

    func testLowRingFrequencyStillSeparatesTaps() {
        for taps in 2...5 {
            XCTAssertEqual(gestureCounts(taps: taps, spacing: 0.2, decay: 0.012, frequencies: [35]), [taps])
        }
    }

    func testOneLongRingingTapIsNotCountedTwice() {
        for decay in [0.06, 0.10, 0.16] {
            XCTAssertEqual(gestureCounts(taps: 1, spacing: 0.2, decay: decay), [1], "decay \(decay) s")
        }
    }

    func testIgnoredBumpsAreCounted() {
        // A tap during typing is rejected and the reason is recorded.
        let signal = Synth.signal(duration: 3, taps: [SynthTap(time: 1.5)], inputEvents: [1.48])
        let detector = ImpactDetector()
        var last = DetectorSnapshot()
        for sample in signal {
            last = detector.process(sample, config: DetectorConfig()).snapshot
        }
        XCTAssertEqual(last.rejections.count(.typing), 1)
        XCTAssertEqual(last.rejections.last, .typing)
    }

    func testAcceptedTapsAreNotCountedAsRejections() {
        let signal = Synth.signal(duration: 3, taps: [SynthTap(time: 1.5)])
        let detector = ImpactDetector()
        var last = DetectorSnapshot()
        for sample in signal {
            last = detector.process(sample, config: DetectorConfig()).snapshot
        }
        XCTAssertEqual(last.rejections.total, 0)
    }
}
