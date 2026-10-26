import XCTest
@testable import TapCore

/// Detector behaviour on a recording from a real MacBook (Lab recording, 800 Hz, with gyroscope).
///
/// The person tapped 26 times in total (3 single, 3 double, 3 triple taps and 2 four-tap bursts were
/// asked for). The taps in that file are about 0.21 s apart and the pauses between gestures are only
/// 0.7 to 0.9 s, except at the start where ten taps run on without a pause. So the tap count and the
/// tap times are known, but how the person meant to group them is not. These tests check what is
/// known: every tap is found, none is invented, and groups follow the pauses.
final class RealRecordingTests: XCTestCase {
    private func load() throws -> [SensorSample] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/macbook_26_taps_800hz.csv")
        return try RecordingCSV.decode(String(contentsOf: url, encoding: .utf8))
    }

    /// Seconds from the start of the recording, found by hand from the raw signal.
    private let tapTimes: [Double] = [
        0.954, 1.168, 1.378, 1.586, 1.789, 2.004, 2.219, 2.435, 2.654, 2.866,
        3.618, 3.814,
        4.716, 4.939, 5.159, 5.365,
        6.378, 6.598,
        7.442, 7.648, 7.849, 8.046,
        8.726, 8.951, 9.172,
        9.879,
    ]

    func testEveryTapIsFoundAndNothingElse() throws {
        let samples = try load()
        let start = samples[0].time
        let found = Replay.impacts(samples, config: PipelineConfig()).map { $0.time - start }
        XCTAssertEqual(found.count, tapTimes.count, "found \(found)")
        for (expected, actual) in zip(tapTimes, found) {
            XCTAssertEqual(actual, expected, accuracy: 0.03)
        }
    }

    func testGroupsFollowThePauses() throws {
        let samples = try load()
        let counts = Replay.run(samples, config: PipelineConfig()).map { $0.taps }
        // The first run of ten taps has no pause, so it is folded into the highest count.
        XCTAssertEqual(counts, [5, 2, 4, 2, 4, 3, 1])
    }

    func testStillWorksWhenTheSensorRunsSlower() throws {
        // Every other sample dropped, as on a Mac that delivers 400 Hz.
        let samples = try load().enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }
        let found = Replay.impacts(samples, config: PipelineConfig()).count
        XCTAssertEqual(found, tapTimes.count)
    }

    func testGyroscopeIsPresentInTheRecording() throws {
        let samples = try load()
        XCTAssertTrue(samples.allSatisfy { $0.gyro != nil })
        let impacts = Replay.impacts(samples, config: PipelineConfig())
        XCTAssertTrue(impacts.allSatisfy { $0.features.hasGyro })
    }
}
