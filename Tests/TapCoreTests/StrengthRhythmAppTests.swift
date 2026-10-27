import XCTest
@testable import TapCore

final class StrengthCalibrationTests: XCTestCase {
    func testClearlyDifferentTapsGiveALevelBetweenThem() throws {
        let fit = try StrengthCalibration.fit(soft: [0.10, 0.12, 0.11, 0.13, 0.12], hard: [0.30, 0.34, 0.28, 0.33, 0.31]).get()
        XCTAssertGreaterThan(fit.hardPeak, fit.softMedian)
        XCTAssertLessThan(fit.hardPeak, fit.hardMedian)
        XCTAssertEqual(StrengthCalibration.label(peak: 0.11, hardPeak: fit.hardPeak), .soft)
        XCTAssertEqual(StrengthCalibration.label(peak: 0.32, hardPeak: fit.hardPeak), .hard)
    }

    func testSimilarTapsAreRefusedWithTheirRatio() {
        let result = StrengthCalibration.fit(soft: [0.20, 0.21, 0.22], hard: [0.24, 0.25, 0.26])
        guard case .failure(.notDifferentEnough(let ratio)) = result else { return XCTFail("expected refusal") }
        XCTAssertEqual(ratio, 0.25 / 0.21, accuracy: 0.01)
    }

    func testTooFewTapsAreRefused() {
        XCTAssertEqual(StrengthCalibration.fit(soft: [0.1, 0.1], hard: [0.3, 0.3, 0.3]), .failure(.tooFewTaps))
    }

    func testSuggestedThresholdNeverRaisesSensitivityLoss() {
        XCTAssertEqual(StrengthCalibration.suggestedThreshold(lightestMedian: 0.5, current: 0.03), 0.03)
        XCTAssertEqual(StrengthCalibration.suggestedThreshold(lightestMedian: 0.04, current: 0.03), 0.015, accuracy: 1e-9)
    }

    func testNoLabelWhenStrengthIsOff() {
        XCTAssertNil(StrengthCalibration.label(peak: 0.3, hardPeak: 0))
    }

    func testRealTapsAreNotAllCalledHardByTheOldDefault() throws {
        // On the real MacBook recording every tap peaks between 0.15 and 0.27 g. The old default of 0.15 g
        // would have called all of them hard, so soft and hard could never have worked without calibration.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/macbook_26_taps_800hz.csv")
        let samples = try RecordingCSV.decode(String(contentsOf: url, encoding: .utf8))
        let peaks = Replay.impacts(samples, config: PipelineConfig()).map { $0.peak }
        XCTAssertEqual(peaks.filter { $0 >= 0.15 }.count, peaks.count)
    }
}

final class RhythmOnRealDataTests: XCTestCase {
    private func gestures() throws -> [RecognizedGesture] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/macbook_26_taps_800hz.csv")
        return Replay.run(try RecordingCSV.decode(String(contentsOf: url, encoding: .utf8)), config: PipelineConfig())
    }

    func testARhythmLearnedFromOneFourTapBurstMatchesTheOther() throws {
        let fours = try gestures().filter { $0.taps == 4 }
        XCTAssertEqual(fours.count, 2)
        let pattern = try RhythmLearner.learn(repeats: [fours[0].gaps, fours[1].gaps, fours[0].gaps])
        XCTAssertTrue(pattern.matches(fours[0].gaps))
        XCTAssertTrue(pattern.matches(fours[1].gaps))
    }

    func testARhythmBindingBeatsAPlainBindingOnRealTaps() throws {
        let fours = try gestures().filter { $0.taps == 4 }
        let pattern = RhythmPattern(gaps: fours[0].gaps)
        let plain = GestureBinding(key: GestureKey(taps: 4), steps: [ActionStep(actionId: "lock-screen")])
        let rhythm = GestureBinding(key: GestureKey(taps: 4), rhythm: pattern, steps: [ActionStep(actionId: "mute")])
        XCTAssertEqual(GestureBinding.best(in: [plain, rhythm], for: fours[1])?.id, rhythm.id)
    }

    func testAFasterRepeatDoesNotMatchASlowRhythm() {
        let slow = RhythmPattern(gaps: [0.6, 0.6])
        XCTAssertFalse(slow.matches([0.2, 0.2]))
    }
}

final class AppOverrideTests: XCTestCase {
    private let gesture = RecognizedGesture(taps: 2, gaps: [0.2])

    func testAppOverrideWinsAndNamesTheApp() {
        let profile = Profile(
            name: "p",
            bindings: [GestureBinding(key: GestureKey(taps: 2), steps: [ActionStep(actionId: "copy")])],
            appOverrides: [AppOverride(id: "com.apple.Safari", appName: "Safari", bindings: [
                GestureBinding(key: GestureKey(taps: 2), steps: [ActionStep(actionId: "mute")]),
            ])]
        )
        let safari = profile.resolution(for: gesture, frontmostBundleID: "com.apple.Safari")
        XCTAssertEqual(safari?.appName, "Safari")
        XCTAssertEqual(safari?.binding.steps.first?.actionId, "mute")
        let other = profile.resolution(for: gesture, frontmostBundleID: "com.apple.Notes")
        XCTAssertNil(other?.appName)
        XCTAssertEqual(other?.binding.steps.first?.actionId, "copy")
    }

    func testARhythmInsideAnAppOverrideIsUsedThere() {
        let rhythm = RhythmPattern(gaps: [0.2])
        let profile = Profile(name: "p", appOverrides: [
            AppOverride(id: "com.apple.Safari", appName: "Safari", bindings: [
                GestureBinding(key: GestureKey(taps: 2), rhythm: rhythm, steps: [ActionStep(actionId: "mute")]),
            ]),
        ])
        XCTAssertNotNil(profile.resolution(for: gesture, frontmostBundleID: "com.apple.Safari"))
        XCTAssertNil(profile.resolution(for: gesture, frontmostBundleID: "com.apple.Notes"))
        XCTAssertEqual(profile.rhythms, [rhythm])
    }
}

final class MissingSetupHintTests: XCTestCase {
    private let gesture = RecognizedGesture(taps: 2, gaps: [0.2])

    private func profile(strength: TapStrength = .any, zone: TapZone = .any) -> Profile {
        Profile(name: "p", bindings: [
            GestureBinding(key: GestureKey(taps: 2, zone: zone, strength: strength), steps: [ActionStep(actionId: "copy")]),
        ])
    }

    func testHardBindingWithDetectionOffExplainsItself() {
        let hint = profile(strength: .hard).missingSetupHint(for: gesture, strengthOn: false, zonesOn: false)
        XCTAssertEqual(hint?.contains("soft and hard detection is off"), true)
    }

    func testZoneBindingWithoutZonesExplainsItself() {
        let hint = profile(zone: .left).missingSetupHint(for: gesture, strengthOn: true, zonesOn: false)
        XCTAssertEqual(hint?.contains("zones are not set up"), true)
    }

    func testNoHintWhenNothingIsMissingOrAnotherTapCount() {
        XCTAssertNil(profile(strength: .hard).missingSetupHint(for: gesture, strengthOn: true, zonesOn: true))
        XCTAssertNil(profile(strength: .hard).missingSetupHint(for: RecognizedGesture(taps: 3), strengthOn: false, zonesOn: false))
    }
}
