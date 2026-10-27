import AVFoundation
import AppKit
import Speech
import TapCore

/// Dictation that lives inside TapDeck: the microphone feeds Apple's on-device speech recogniser, a pill shows
/// what it hears, and when the same gesture is made again the text is typed into the app that was in front.
///
/// The on and off is `DictationSession` in TapCore, so one gesture always does the opposite of the current state.
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    /// Microphone loudness from 0 to 1, for the meter.
    @Published private(set) var level = 0.0

    /// Told when a session ends by itself (the safety stop), so the person still sees the result.
    var onMessage: ((String) -> Void)?

    private var session = DictationSession()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalWaiter: CheckedContinuation<Void, Never>?
    private var autoStop: Task<Void, Never>?
    private let pill = DictationPill()

    // MARK: Permissions

    /// A sentence saying what to allow, or nil when everything needed is allowed.
    nonisolated static func missingPermission() -> String? {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        switch (mic, speech) {
        case (true, true): return nil
        case (false, true): return "Allow Microphone for TapDeck in Setup, then try again"
        case (true, false): return "Allow Speech Recognition for TapDeck in Setup, then try again"
        case (false, false): return "Allow Microphone and Speech Recognition for TapDeck in Setup, then try again"
        }
    }

    // MARK: The toggle

    /// Starts when idle, finishes when listening. Returns the sentence for the activity log and the toast.
    func toggle() async throws -> String {
        switch session.toggle() {
        case .ignore:
            return isListening ? "Finishing dictation…" : "Starting dictation…"
        case .start:
            do {
                try await begin()
                session.started()
                return "Listening… double tap again to finish"
            } catch {
                session.startFailed()
                teardown()
                throw error
            }
        case .stop:
            return await finish()
        }
    }

    private func begin() async throws {
        if let missing = Self.missingPermission() { throw ActionError(missing) }

        let locale = Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            throw ActionError("Speech recognition is not available for this language")
        }
        guard recognizer.isAvailable else {
            throw ActionError("Speech recognition is not available right now. Check your internet connection once, or try again")
        }
        // Audio must not leave the Mac. If this language has no on-device model, say so instead of sending it away.
        guard recognizer.supportsOnDeviceRecognition else {
            throw ActionError("On-device speech recognition is not available for \(locale.identifier). Add the language in System Settings, Keyboard, Dictation")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        self.request = request
        transcript = ""

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw ActionError("No microphone was found") }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let loudness = Self.loudness(of: buffer)
            Task { @MainActor in self?.level = loudness }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw ActionError("Could not start the microphone: \(error.localizedDescription)")
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in self?.heard(text: text, done: done) }
        }

        isListening = true
        pill.show(controller: self)
        scheduleSafetyStop()
    }

    private func heard(text: String?, done: Bool) {
        if let text { transcript = text }
        if done { resumeWaiter() }
    }

    private func finish() async -> String {
        autoStop?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()

        // The recogniser sends its last words after the audio ends. Wait for them, but never for long.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finalWaiter = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self?.resumeWaiter()
            }
        }

        let text = DictationText.clean(transcript)
        teardown()
        session.finished()
        guard !text.isEmpty else { return "Nothing was heard" }
        return await TextTyper.insert(text)
    }

    private func resumeWaiter() {
        finalWaiter?.resume()
        finalWaiter = nil
    }

    private func teardown() {
        autoStop?.cancel()
        task?.cancel()
        task = nil
        request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        isListening = false
        level = 0
        pill.hide()
    }

    private func scheduleSafetyStop() {
        autoStop?.cancel()
        autoStop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(DictationSession.maxSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if self.session.toggle() == .stop {
                let message = await self.finish()
                self.onMessage?("Stopped after 2 minutes. \(message)")
            }
        }
    }

    // MARK: Audio

    nonisolated private static func loudness(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frames { sum += channel[index] * channel[index] }
        let rms = (sum / Float(frames)).squareRoot()
        return Double(min(1, rms * 9))
    }
}
