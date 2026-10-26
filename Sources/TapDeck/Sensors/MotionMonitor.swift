import AppKit
import Combine
import Foundation
import TapCore

/// Runs the sensors and the tap pipeline and publishes what the UI needs.
///
/// Samples arrive on the sensor queue and go straight through `TapPipeline`. Only finished results
/// (taps, gestures, and a throttled live snapshot) are handed to the main thread.
@MainActor
final class MotionMonitor: ObservableObject {
    @Published private(set) var snapshot = DetectorSnapshot()
    /// Recent filtered signal strength for the waveform, newest last.
    @Published private(set) var waveform: [Double] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var isSupported = true
    @Published private(set) var hasGyroscope = false
    @Published private(set) var statusMessage = "Starting"
    @Published private(set) var isRecording = false

    /// Every finished gesture, on the main thread.
    var onGesture: ((RecognizedGesture) -> Void)?
    /// Every single tap before grouping. Used by calibration and learning screens.
    var onImpact: ((Impact) -> Void)?

    private let service = SensorService()
    private let idleMonitor = InputIdleMonitor()
    private let state = SensorState()
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []

    private static let waveformLength = 140

    init() {
        service.inputIdle = { [idleMonitor] in idleMonitor.secondsSinceInput() }
        service.onSample = { [weak self] sample in
            self?.process(sample)
        }

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restartAfterWake() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspendForSleep() }
        })
    }

    // MARK: - Control

    /// Starts or stops the sensors to match what the user wants.
    func setEnabled(_ enabled: Bool) {
        wantsRunning = enabled
        if enabled {
            startSensors()
        } else {
            stopSensors(message: "Paused")
        }
    }

    func updateConfig(_ config: PipelineConfig) {
        state.setConfig(config)
    }

    var isAccelerometerPresent: Bool { service.accelerometerAvailable() }

    private func startSensors() {
        guard !isMonitoring else { return }
        do {
            state.resetPipeline()
            try service.start()
            isSupported = true
            isMonitoring = true
            hasGyroscope = service.hasGyroscope
            statusMessage = service.hasGyroscope
                ? "Listening (accelerometer and gyroscope)"
                : "Listening (accelerometer only)"
        } catch {
            isSupported = false
            isMonitoring = false
            hasGyroscope = false
            statusMessage = error.localizedDescription
        }
    }

    private func stopSensors(message: String) {
        service.stop()
        state.resetPipeline()
        isMonitoring = false
        statusMessage = message
        snapshot = DetectorSnapshot()
        waveform.removeAll()
    }

    private func suspendForSleep() {
        if isMonitoring { stopSensors(message: "Asleep") }
    }

    private func restartAfterWake() {
        guard wantsRunning else { return }
        // Give the sensor drivers a moment to come back.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.wantsRunning else { return }
            self.startSensors()
        }
    }

    // MARK: - Recording

    func startRecording() {
        state.startRecording()
        isRecording = true
    }

    func stopRecording() -> [SensorSample] {
        isRecording = false
        return state.stopRecording()
    }

    // MARK: - Sensor queue

    private nonisolated func process(_ sample: SensorSample) {
        let result = state.ingest(sample)

        if let impact = result.output.impact {
            Task { @MainActor [weak self] in self?.onImpact?(impact) }
        }
        if let gesture = result.output.gesture {
            Task { @MainActor [weak self] in self?.onGesture?(gesture) }
        }
        if let live = result.live {
            Task { @MainActor [weak self] in self?.apply(live) }
        }
    }

    private func apply(_ live: LiveUpdate) {
        guard isMonitoring else { return }
        snapshot = live.snapshot
        waveform.append(min(max(live.peak, 0), 1.2))
        if waveform.count > Self.waveformLength {
            waveform.removeFirst(waveform.count - Self.waveformLength)
        }
    }
}

struct LiveUpdate: Sendable {
    var snapshot: DetectorSnapshot
    /// Strongest filtered value since the previous update, so short spikes stay visible.
    var peak: Double
}

/// State shared with the sensor queue, guarded by a lock.
private final class SensorState: @unchecked Sendable {
    struct Result {
        var output: PipelineOutput
        var live: LiveUpdate?
    }

    private let lock = NSLock()
    private let pipeline = TapPipeline()
    private var config = PipelineConfig()
    private var lastPublish = -Double.infinity
    private var peakSincePublish = 0.0
    private var recording: [SensorSample]?

    private static let publishInterval = 1.0 / 30.0
    private static let maxRecordedSamples = 400_000

    func setConfig(_ new: PipelineConfig) {
        lock.lock()
        config = new
        lock.unlock()
    }

    func resetPipeline() {
        lock.lock()
        pipeline.reset()
        lastPublish = -Double.infinity
        peakSincePublish = 0
        lock.unlock()
    }

    func startRecording() {
        lock.lock()
        recording = []
        lock.unlock()
    }

    func stopRecording() -> [SensorSample] {
        lock.lock()
        defer { lock.unlock() }
        let samples = recording ?? []
        recording = nil
        return samples
    }

    func ingest(_ sample: SensorSample) -> Result {
        lock.lock()
        defer { lock.unlock() }

        if recording != nil, recording!.count < Self.maxRecordedSamples {
            recording!.append(sample)
        }

        let output = pipeline.ingest(sample, config: config)
        peakSincePublish = max(peakSincePublish, output.snapshot.filteredMagnitude)

        var live: LiveUpdate?
        if sample.time - lastPublish >= Self.publishInterval {
            lastPublish = sample.time
            live = LiveUpdate(snapshot: output.snapshot, peak: peakSincePublish)
            peakSincePublish = 0
        }
        return Result(output: output, live: live)
    }
}
