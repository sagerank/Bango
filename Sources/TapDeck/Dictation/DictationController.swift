import AVFoundation
import AppKit
import Speech
import TapCore

/// Dictation that lives inside Bango: the microphone feeds Apple's on-device speech recogniser, a pill shows
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

    /// What the pill says about where the words are going, for example "Typing into Notes".
    @Published private(set) var typingNote = ""

    /// Told when a session ends by itself (the safety stop), so the person still sees the result.
    var onMessage: ((String) -> Void)?

    private var session = DictationSession()
    private var typist = LiveTypist()
    /// The app the words are typed into: the one in front when dictation started.
    private var typingTarget: String?
    private var typingAllowed = false
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognizer: SFSpeechRecognizer?
    /// The microphone tap appends to whichever request is current, so a new one can be swapped in mid-session.
    private let sink = RequestSink()
    /// Keeps every sentence: the recogniser starts its text over after a pause.
    private var stitcher = TranscriptStitcher()
    private var restartedAt = Date.distantPast
    private var task: SFSpeechRecognitionTask?
    private var finalWaiter: CheckedContinuation<Void, Never>?
    private var idleFlush: Task<Void, Never>?
    private var finalArrived = false
    private var lastHeardAt = Date()
    private var autoStop: Task<Void, Never>?
    private let pill = DictationPill()

    // MARK: Permissions

    /// A sentence saying what to allow, or nil when everything needed is allowed.
    nonisolated static func missingPermission() -> String? {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        switch (mic, speech) {
        case (true, true): return nil
        case (false, true): return "Allow Microphone for Bango in Setup, then try again"
        case (true, false): return "Allow Speech Recognition for Bango in Setup, then try again"
        case (false, false): return "Allow Microphone and Speech Recognition for Bango in Setup, then try again"
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

        self.recognizer = recognizer
        stitcher = TranscriptStitcher()
        transcript = ""
        prepareTyping()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw ActionError("No microphone was found") }
        input.removeTap(onBus: 0)
        let sink = self.sink
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            sink.append(buffer)
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

        startRecognition()

        isListening = true
        pill.show(controller: self)
        scheduleSafetyStop()
    }

    /// Starts one recognition task on a fresh request. Called at the start, and again whenever the recogniser ends
    /// a task by itself (it does after a long enough pause), so later sentences are still heard.
    private func startRecognition() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        self.request = request
        sink.set(request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let start = result?.bestTranscription.segments.first?.timestamp
            let done = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in self?.heard(text: text, start: start, done: done, request: request) }
        }
    }

    private func heard(text: String?, start: Double?, done: Bool, request: SFSpeechAudioBufferRecognitionRequest) {
        // A late result from a task that was already replaced or stopped must not disturb the current one.
        guard request === self.request else { return }
        if let text, !text.isEmpty {
            stitcher.update(text, start: start)
            transcript = stitcher.full
            lastHeardAt = Date()
            typeLive(transcript)
        }
        guard done else { return }
        if session.isListening {
            // The recogniser closed this stretch on its own while the person is still dictating. Keep what it
            // heard and open a new one. The delay stops a tight loop if it keeps failing straight away.
            stitcher.commit()
            task?.cancel()
            task = nil
            self.request = nil
            let wait = max(0, 0.3 - Date().timeIntervalSince(restartedAt))
            restartedAt = Date().addingTimeInterval(wait)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard let self, self.session.isListening, self.request == nil else { return }
                self.startRecognition()
            }
        } else {
            finalArrived = true
            resumeWaiter()
        }
    }

    // MARK: Typing into the app in front

    private static func frontBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func prepareTyping() {
        typist = LiveTypist()
        let front = NSWorkspace.shared.frontmostApplication
        typingTarget = front?.bundleIdentifier
        if !AccessibilityPermission.isTrusted(promptIfNeeded: false) {
            typingAllowed = false
            typingNote = "Not typing: allow Accessibility in Setup. The words will be copied instead"
        } else if front?.bundleIdentifier == Bundle.main.bundleIdentifier {
            typingAllowed = false
            typingNote = "Not typing: Bango itself is in front. Click into another app's text box first"
        } else {
            typingAllowed = true
            typingNote = "Typing into \(front?.localizedName ?? "the app in front")"
        }
    }

    /// Types words that have stayed the same across two updates. Stops for good if the person switches apps.
    private func typeLive(_ partial: String) {
        guard session.isListening, typingAllowed else { return }
        guard Self.frontBundleID() == typingTarget else {
            typingAllowed = false
            typingNote = "You switched apps, so typing stopped. The words will be copied at the end"
            return
        }
        KeyTyper.enqueue(typist.update(partial: partial))
        scheduleSettle()
    }

    /// When the person pauses, type the last word too instead of holding it back until the next word arrives.
    private func scheduleSettle() {
        idleFlush?.cancel()
        idleFlush = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.session.isListening, self.typingAllowed, Self.frontBundleID() == self.typingTarget else { return }
            KeyTyper.enqueue(self.typist.settle())
        }
    }

    private func finish() async -> String {
        autoStop?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()

        idleFlush?.cancel()

        // The recogniser sends its final, polished text (capitals, punctuation) after the audio ends. Wait for that
        // result itself, checking every 50 ms so there is no lag once it arrives, and never longer than 2.5 s.
        let stopped = Date()
        finalArrived = false
        while Date().timeIntervalSince(stopped) < 2.5, !finalArrived {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let text = DictationText.clean(transcript)
        let stillInTarget = Self.frontBundleID() == typingTarget
        let canType = typingAllowed && stillInTarget
        let reason: String
        if typingNote.hasPrefix("You switched") || (typingAllowed && !stillInTarget) {
            reason = "You switched apps"
        } else if typingNote.hasPrefix("Not typing: Bango") {
            reason = "Bango was in front"
        } else {
            reason = "Accessibility is not allowed"
        }
        var message: String
        if text.isEmpty {
            message = "Nothing was heard"
        } else if canType {
            KeyTyper.enqueue(typist.finish(final: text))
            await KeyTyper.flush()
            if typist.diverged {
                message = TextFallback.copy(text, reason: "The text changed too much to fix in place")
            } else {
                let words = DictationText.wordCount(typist.typed)
                message = "Typed \(words) \(words == 1 ? "word" : "words")"
            }
        } else {
            message = TextFallback.copy(text, reason: reason)
        }
        teardown()
        session.finished()
        return message
    }

    private func resumeWaiter() {
        finalWaiter?.resume()
        finalWaiter = nil
    }

    private func teardown() {
        autoStop?.cancel()
        idleFlush?.cancel()
        task?.cancel()
        task = nil
        request = nil
        sink.set(nil)
        recognizer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        isListening = false
        level = 0
        typingAllowed = false
        typingTarget = nil
        typingNote = ""
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

/// Hands microphone buffers to the current speech request from the audio thread.
private final class RequestSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let current = request; lock.unlock()
        current?.append(buffer)
    }
}
