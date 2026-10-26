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
