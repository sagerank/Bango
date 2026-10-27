import XCTest
@testable import TapCore

final class RhythmTests: XCTestCase {
    func testPatternMatchesWithinTolerance() {
        let pattern = RhythmPattern(gaps: [0.2, 0.8])
        XCTAssertTrue(pattern.matches([0.2, 0.8]))
        XCTAssertTrue(pattern.matches([0.25, 0.7]))
        XCTAssertFalse(pattern.matches([0.2, 0.3]))
        XCTAssertFalse(pattern.matches([0.2]))
    }

    func testSameRhythmPlayedABitFasterOrSlowerStillMatches() {
        let pattern = RhythmPattern(gaps: [0.25, 0.25, 0.9])
        XCTAssertTrue(pattern.matches([0.22, 0.21, 0.78]))
        XCTAssertTrue(pattern.matches([0.30, 0.29, 1.05]))
    }

    func testSloppyButHumanRepeatMatches() {
        // Gaps off by 60 ms and 150 ms from the recording.
        let pattern = RhythmPattern(gaps: [0.25, 0.9])
        XCTAssertTrue(pattern.matches([0.31, 0.75]))
    }

    func testDifferentPatternWithSameTapCountDoesNotMatch() {
        let tapTapPauseTap = RhythmPattern(gaps: [0.2, 0.2, 0.9])
        XCTAssertFalse(tapTapPauseTap.matches([0.9, 0.2, 0.2]))
        XCTAssertFalse(tapTapPauseTap.matches([0.2, 0.9, 0.2]))
        XCTAssertFalse(tapTapPauseTap.matches([0.4, 0.4, 0.4]))
    }

    func testMuchFasterOrSlowerPlayingDoesNotMatch() {
        let pattern = RhythmPattern(gaps: [0.4, 0.4])
        XCTAssertFalse(pattern.matches([0.15, 0.15]))
        XCTAssertFalse(pattern.matches([0.9, 0.9]))
    }

    func testDeviationIsOneOrLessExactlyWhenItMatches() {
        let pattern = RhythmPattern(gaps: [0.25, 0.9])
        XCTAssertEqual(pattern.deviation(of: [0.25, 0.9]) ?? 9, 0, accuracy: 1e-9)
        XCTAssertNil(pattern.deviation(of: [0.25]))
        XCTAssertGreaterThan(pattern.deviation(of: [0.9, 0.25]) ?? 0, 1)
    }

    func testMissedRhythmIsExplainedWhenPlainGestureRuns() {
        let rhythm = GestureBinding(key: GestureKey(taps: 3), rhythm: RhythmPattern(gaps: [0.2, 0.9]), steps: [ActionStep(actionId: "mute")])
        let plain = GestureBinding(key: GestureKey(taps: 3), steps: [ActionStep(actionId: "copy")])
        let profile = Profile(name: "p", bindings: [rhythm, plain])
        let off = RecognizedGesture(taps: 3, gaps: [0.5, 0.2])
        XCTAssertEqual(profile.resolution(for: off, frontmostBundleID: nil)?.binding.id, plain.id)
        let note = profile.rhythmMissNote(for: off, frontmostBundleID: nil)
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("0.50, 0.20") ?? false)
        XCTAssertNil(profile.rhythmMissNote(for: RecognizedGesture(taps: 2, gaps: [0.2]), frontmostBundleID: nil))
    }

    func testLearnerAveragesConsistentRepeats() throws {
        let pattern = try RhythmLearner.learn(repeats: [[0.2, 0.8], [0.22, 0.78], [0.18, 0.82]])
        XCTAssertEqual(pattern.gaps[0], 0.2, accuracy: 0.01)
        XCTAssertEqual(pattern.gaps[1], 0.8, accuracy: 0.01)
        XCTAssertEqual(pattern.taps, 3)
    }

    func testLearnerRejectsInconsistentRepeats() {
        XCTAssertThrowsError(try RhythmLearner.learn(repeats: [[0.2, 0.8], [0.2, 0.3], [0.2, 0.8]])) {
            XCTAssertEqual($0 as? RhythmError, .inconsistent)
        }
    }

    func testLearnerNeedsThreeRepeats() {
        XCTAssertThrowsError(try RhythmLearner.learn(repeats: [[0.2], [0.2]])) {
            XCTAssertEqual($0 as? RhythmError, .notEnoughSamples)
        }
    }

    func testLongPausesWidenTheGroupingWindow() {
        var config = PipelineConfig()
        XCTAssertEqual(config.effectiveGroupingWindow, config.detector.groupingWindow)
        config.rhythms = [RhythmPattern(gaps: [0.2, 0.8])]
        XCTAssertGreaterThan(config.effectiveGroupingWindow, 0.8)
    }

    func testRhythmIsRecognizedEndToEnd() {
        let pattern = RhythmPattern(gaps: [0.2, 0.8])
        var config = PipelineConfig()
        config.rhythms = [pattern]
        let taps = [SynthTap(time: 1.5), SynthTap(time: 1.7), SynthTap(time: 2.5)]
        let result = Replay.run(Synth.signal(duration: 5, taps: taps), config: config)
        XCTAssertEqual(result.count, 1)
        guard let gesture = result.first else { return }
        XCTAssertEqual(gesture.taps, 3)
        XCTAssertTrue(pattern.matches(gesture.gaps))
    }

    func testRhythmBindingBeatsPlainTapCount() {
        let pattern = RhythmPattern(gaps: [0.2, 0.8])
        let plain = GestureBinding(key: GestureKey(taps: 3), steps: [ActionStep(actionId: "copy")])
        let rhythm = GestureBinding(key: GestureKey(taps: 3), rhythm: pattern, steps: [ActionStep(actionId: "paste")])
        let gesture = RecognizedGesture(taps: 3, gaps: [0.21, 0.79])
        XCTAssertEqual(GestureBinding.best(in: [plain, rhythm], for: gesture)?.id, rhythm.id)
        let fast = RecognizedGesture(taps: 3, gaps: [0.15, 0.15])
        XCTAssertEqual(GestureBinding.best(in: [plain, rhythm], for: fast)?.id, plain.id)
    }
}

final class ZoneTests: XCTestCase {
    private func features(_ gyro: Vec3, _ accel: Vec3, jitter: Double = 0, seed: UInt64 = 1) -> ImpactFeatures {
        var rng = SplitMix(state: seed)
        func j() -> Double { rng.gauss() * jitter }
        return ImpactFeatures(
            gyro: Vec3(gyro.x + j(), gyro.y + j(), gyro.z + j()),
            accel: Vec3(accel.x + j(), accel.y + j(), accel.z + j())
        )
    }

    private let leftGyro = Vec3(0, 0, 1)
    private let leftAccel = Vec3(0.3, -0.2, 1)
    private let rightGyro = Vec3(0, 0, -1)
    private let rightAccel = Vec3(-0.3, 0.2, 1)
    private let topGyro = Vec3(1, 0, 0)
    private let topAccel = Vec3(0, 0.5, 1)

    private func samples(_ gyro: Vec3, _ accel: Vec3, seed: UInt64) -> [ImpactFeatures] {
        (0..<4).map { features(gyro, accel, jitter: 0.05, seed: seed + UInt64($0)) }
    }

    private func learnedModel() throws -> ZoneModel {
        try ZoneModel.learn(
            left: samples(leftGyro, leftAccel, seed: 10),
            right: samples(rightGyro, rightAccel, seed: 20),
            top: samples(topGyro, topAccel, seed: 30)
        )
    }

    func testLearnedModelClassifiesEachZone() throws {
        let model = try learnedModel()
        XCTAssertEqual(model.classify(features(leftGyro, leftAccel, jitter: 0.05, seed: 91)), .left)
        XCTAssertEqual(model.classify(features(rightGyro, rightAccel, jitter: 0.05, seed: 92)), .right)
        XCTAssertEqual(model.classify(features(topGyro, topAccel, jitter: 0.05, seed: 93)), .top)
    }

    func testNoMotionDataGivesUnknownZone() throws {
        let model = try learnedModel()
        XCTAssertEqual(model.classify(ImpactFeatures()), .any)
    }

    func testLearningNeedsThreeTapsPerZone() {
        XCTAssertThrowsError(try ZoneModel.learn(
            left: Array(samples(leftGyro, leftAccel, seed: 10).prefix(2)),
            right: samples(rightGyro, rightAccel, seed: 20),
            top: samples(topGyro, topAccel, seed: 30)
        )) {
            XCTAssertEqual($0 as? ZoneError, .notEnoughSamples(.left))
        }
    }

    func testLearningRejectsZonesThatFeelTheSame() {
        XCTAssertThrowsError(try ZoneModel.learn(
            left: samples(leftGyro, leftAccel, seed: 10),
            right: samples(leftGyro, leftAccel, seed: 20),
            top: samples(topGyro, topAccel, seed: 30)
        )) {
            guard case .indistinguishable? = $0 as? ZoneError else {
                return XCTFail("expected indistinguishable, got \($0)")
            }
        }
    }

    func testLearningRejectsScatteredTaps() {
        let scattered = [
            features(Vec3(1, 0, 0), Vec3(1, 0, 0)),
            features(Vec3(0, 1, 0), Vec3(0, 1, 0)),
            features(Vec3(0, 0, 1), Vec3(0, 0, 1)),
            features(Vec3(-1, 0, 0), Vec3(-1, 0, 0)),
        ]
        XCTAssertThrowsError(try ZoneModel.learn(
            left: scattered,
            right: samples(rightGyro, rightAccel, seed: 20),
            top: samples(topGyro, topAccel, seed: 30)
        )) {
            XCTAssertEqual($0 as? ZoneError, .inconsistent(.left))
        }
    }

    func testZonesWorkEndToEndFromRecordedSignals() throws {
        // Teach the model from synthetic taps with gyro data, then recognize a new gesture.
        func zoneTap(_ time: Double, gyro: Vec3, accel: Vec3) -> SynthTap {
            SynthTap(time: time, accelDir: accel, gyroDir: gyro)
        }
        func learn(_ gyro: Vec3, _ accel: Vec3, seed: UInt64) -> [ImpactFeatures] {
            let taps = (0..<4).map { zoneTap(1.5 + Double($0) * 0.8, gyro: gyro, accel: accel) }
            let signal = Synth.signal(duration: 6, taps: taps, seed: seed, withGyro: true)
            return Replay.impacts(signal, config: PipelineConfig()).map { $0.features }
        }
        let model = try ZoneModel.learn(
            left: learn(leftGyro, leftAccel, seed: 1),
            right: learn(rightGyro, rightAccel, seed: 2),
            top: learn(topGyro, topAccel, seed: 3)
        )
        var config = PipelineConfig()
        config.zones = model
        let taps = [
            zoneTap(1.5, gyro: rightGyro, accel: rightAccel),
            zoneTap(1.7, gyro: rightGyro, accel: rightAccel),
        ]
        let result = Replay.run(Synth.signal(duration: 4, taps: taps, seed: 9, withGyro: true), config: config)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.taps, 2)
        XCTAssertEqual(result.first?.zone, .right)
    }

    func testZoneBindingOnlyMatchesItsZone() {
        let left = GestureBinding(key: GestureKey(taps: 1, zone: .left), steps: [ActionStep(actionId: "copy")])
        let anywhere = GestureBinding(key: GestureKey(taps: 1), steps: [ActionStep(actionId: "paste")])
        let leftTap = RecognizedGesture(taps: 1, zone: .left)
        let rightTap = RecognizedGesture(taps: 1, zone: .right)
        XCTAssertEqual(GestureBinding.best(in: [anywhere, left], for: leftTap)?.id, left.id)
        XCTAssertEqual(GestureBinding.best(in: [anywhere, left], for: rightTap)?.id, anywhere.id)
        XCTAssertNil(GestureBinding.best(in: [left], for: rightTap))
    }
}
