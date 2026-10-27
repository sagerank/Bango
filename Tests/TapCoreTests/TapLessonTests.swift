import XCTest
@testable import TapCore

final class TapLessonTests: XCTestCase {
    private func gesture(_ taps: Int, zone: TapZone = .any, gap: Double = 0.2) -> RecognizedGesture {
        RecognizedGesture(taps: taps, zone: zone, gaps: Array(repeating: gap, count: max(taps - 1, 0)))
    }

    func testCorrectCountPassesAndSaysSo() {
        for lesson in TapLessons.basic {
            XCTAssertEqual(TapLessons.evaluate(lesson, gesture: gesture(lesson.taps)), .success(lesson.successText))
        }
    }

    func testTooManyTapsSaysHowManyAndWhatToDo() {
        let single = TapLessons.basic[0]
        guard case .tryAgain(let text) = TapLessons.evaluate(single, gesture: gesture(3)) else { return XCTFail() }
        XCTAssertTrue(text.contains("3 taps") && text.contains("Tap once"))
        let double = TapLessons.basic[1]
        guard case .tryAgain(let more) = TapLessons.evaluate(double, gesture: gesture(4)) else { return XCTFail() }
        XCTAssertTrue(more.contains("exactly 2"))
    }

    func testTooFewTapsAndTooSlowAreToldApart() {
        let triple = TapLessons.basic[2]
        guard case .tryAgain(let fewFast) = TapLessons.evaluate(triple, gesture: gesture(2, gap: 0.2)) else { return XCTFail() }
        XCTAssertTrue(fewFast.contains("only 2 taps"))
        guard case .tryAgain(let slow) = TapLessons.evaluate(triple, gesture: gesture(2, gap: 0.8)) else { return XCTFail() }
        XCTAssertTrue(slow.contains("Too slow"))
        guard case .tryAgain(let one) = TapLessons.evaluate(TapLessons.basic[1], gesture: gesture(1)) else { return XCTFail() }
        XCTAssertTrue(one.contains("only 1 tap."))
    }

    func testZoneLessonNeedsTheRightSide() {
        let left = TapLessons.zones[0]
        XCTAssertEqual(TapLessons.evaluate(left, gesture: gesture(1, zone: .left)), .success(left.successText))
        guard case .tryAgain(let wrong) = TapLessons.evaluate(left, gesture: gesture(1, zone: .right)) else { return XCTFail() }
        XCTAssertTrue(wrong.contains("right side") && wrong.contains("left side"))
        guard case .tryAgain(let unsure) = TapLessons.evaluate(left, gesture: gesture(1, zone: .any)) else { return XCTFail() }
        XCTAssertTrue(unsure.contains("could not tell"))
    }

    func testOnlyZoneLessonsNeedZones() {
        XCTAssertTrue(TapLessons.basic.allSatisfy { !$0.needsZones })
        XCTAssertTrue(TapLessons.zones.allSatisfy { $0.needsZones })
        XCTAssertEqual(Set((TapLessons.basic + TapLessons.zones).map { $0.id }).count, 6)
    }

    func testLessonsMatchWhatTheDetectorSeesOnRealTaps() throws {
        // A person tapping once, twice, three times like the real recording: the same counts come out.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/macbook_26_taps_800hz.csv")
        let gestures = Replay.run(try RecordingCSV.decode(String(contentsOf: url, encoding: .utf8)), config: PipelineConfig())
        let two = gestures.first { $0.taps == 2 }!
        XCTAssertEqual(TapLessons.evaluate(TapLessons.basic[1], gesture: two), .success(TapLessons.basic[1].successText))
        let three = gestures.first { $0.taps == 3 }!
        XCTAssertEqual(TapLessons.evaluate(TapLessons.basic[2], gesture: three), .success(TapLessons.basic[2].successText))
    }
}
