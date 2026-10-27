import Foundation

public struct PipelineConfig: Equatable, Sendable {
    public var detector: DetectorConfig
    /// Rhythm patterns in use. They widen the grouping window so slow rhythms stay in one gesture.
    public var rhythms: [RhythmPattern]
    public var zones: ZoneModel?

    public init(detector: DetectorConfig = DetectorConfig(), rhythms: [RhythmPattern] = [], zones: ZoneModel? = nil) {
        self.detector = detector
        self.rhythms = rhythms
        self.zones = zones
    }

    /// Silence needed to close a gesture. Longer when rhythms with long pauses exist.
    public var effectiveGroupingWindow: Double {
        guard let longest = rhythms.map({ $0.maxGap }).max() else { return detector.groupingWindow }
        return max(detector.groupingWindow, longest * 1.3 + 0.05)
    }
}

public struct PipelineOutput: Sendable {
    public var snapshot: DetectorSnapshot
    public var impact: Impact?
    public var gesture: RecognizedGesture?
}

/// Sensor samples in, gestures out. Deterministic, so recordings replay to the same result.
public final class TapPipeline {
    private let detector = ImpactDetector()
    private let recognizer = GestureRecognizer()

    public init() {}

    public func reset() {
        detector.reset()
        recognizer.reset()
    }

    public func ingest(_ sample: SensorSample, config: PipelineConfig) -> PipelineOutput {
        let grouping = config.effectiveGroupingWindow
        var detectorConfig = config.detector
        detectorConfig.groupingWindow = grouping

        recognizer.noteInput(sampleTime: sample.time, idle: sample.inputIdle)
        let result = detector.process(sample, config: detectorConfig)
        if let impact = result.impact {
            recognizer.add(impact)
        }
        let gesture = recognizer.poll(
            now: sample.time,
            config: detectorConfig,
            groupingWindow: grouping,
            zones: config.zones
        )
        return PipelineOutput(snapshot: result.snapshot, impact: result.impact, gesture: gesture)
    }
}

public enum Replay {
    /// Runs recorded samples through a fresh pipeline and returns every gesture found.
    public static func run(_ samples: [SensorSample], config: PipelineConfig) -> [RecognizedGesture] {
        let pipeline = TapPipeline()
        var found: [RecognizedGesture] = []
        for sample in samples {
            if let gesture = pipeline.ingest(sample, config: config).gesture {
                found.append(gesture)
            }
        }
        return found
    }

    /// Runs recorded samples and returns every individual tap found, with its features.
    public static func impacts(_ samples: [SensorSample], config: PipelineConfig) -> [Impact] {
        let pipeline = TapPipeline()
        var found: [Impact] = []
        for sample in samples {
            if let impact = pipeline.ingest(sample, config: config).impact {
                found.append(impact)
            }
        }
        return found
    }
}
