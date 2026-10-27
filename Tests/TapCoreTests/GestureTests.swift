import XCTest
@testable import TapCore

final class GestureTests: XCTestCase {
    private func gestures(_ samples: [SensorSample], _ config: PipelineConfig = PipelineConfig()) -> [RecognizedGesture] {
        Replay.run(samples, config: config)
    }

    func testFourTapsBecomeOneGestureWithCorrectGaps() {
        let taps = Synth.run(start: 1.5, count: 4, spacing: 0.2)
        let result = gestures(Synth.signal(duration: 4.5, taps: taps))
        XCTAssertEqual(result.count, 1)
        guard let g = result.first else { return }
        XCTAssertEqual(g.taps, 4)
        XCTAssertEqual(g.gaps.count, 3)
        for gap in g.gaps { XCTAssertEqual(gap, 0.2, accuracy: 0.03) }
        XCTAssertEqual(g.zone, .any)
        XCTAssertEqual(g.strength, .any)
    }

    func testSixTapsFoldIntoTheMaximumOfFive() {
        let taps = Synth.run(start: 1.5, count: 6, spacing: 0.15)
        let result = gestures(Synth.signal(duration: 5, taps: taps))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.taps, 5)
    }

    func testMaxTapsSettingIsRespected() {
        var config = PipelineConfig()
        config.detector.maxTaps = 3
        let taps = Synth.run(start: 1.5, count: 4, spacing: 0.15)
        let result = gestures(Synth.signal(duration: 4.5, taps: taps), config)
        XCTAssertEqual(result.first?.taps, 3)
    }

    func testTwoSeparateGesturesInOneSession() {
        var taps = [SynthTap(time: 1.5)]
        taps += Synth.run(start: 3.0, count: 2, spacing: 0.2)
        let result = gestures(Synth.signal(duration: 5, taps: taps))
        XCTAssertEqual(result.map { $0.taps }, [1, 2])
    }

    func testGestureIsNotEmittedBeforeTheGroupingWindowEnds() {
        let pipeline = TapPipeline()
        let config = PipelineConfig()
        var emittedAt: Double?
        for sample in Synth.signal(duration: 4, taps: [SynthTap(time: 1.5)]) {
            if pipeline.ingest(sample, config: config).gesture != nil, emittedAt == nil {
                emittedAt = sample.time
            }
        }
        guard let emittedAt else { return XCTFail("no gesture") }
        XCTAssertGreaterThanOrEqual(emittedAt, 1.5 + config.detector.groupingWindow)
        XCTAssertLessThan(emittedAt, 1.5 + config.detector.groupingWindow + 0.2)
    }

    func testKeyPressRightAfterATapCancelsTheGesture() {
        let signal = Synth.signal(duration: 3.5, taps: [SynthTap(time: 1.5)], inputEvents: [1.6])
        XCTAssertEqual(gestures(signal).count, 0)
    }

    func testTypingLongAfterATapDoesNotCancelIt() {
        let signal = Synth.signal(duration: 3.5, taps: [SynthTap(time: 1.5)], inputEvents: [2.4])
        XCTAssertEqual(gestures(signal).count, 1)
    }

    func testHardAndSoftTapsAreTold() {
        var config = PipelineConfig()
        config.detector.hardPeak = 0.12
        let soft = gestures(Synth.signal(duration: 3.5, taps: [SynthTap(time: 1.5, amp: 0.12)]), config)
        let hard = gestures(Synth.signal(duration: 3.5, taps: [SynthTap(time: 1.5, amp: 0.4)]), config)
        XCTAssertEqual(soft.first?.strength, .soft)
        XCTAssertEqual(hard.first?.strength, .hard)
    }

    func testStrengthIsUnknownWhenNotConfigured() {
        let result = gestures(Synth.signal(duration: 3.5, taps: [SynthTap(time: 1.5, amp: 0.4)]))
        XCTAssertEqual(result.first?.strength, TapStrength.any)
    }
}
