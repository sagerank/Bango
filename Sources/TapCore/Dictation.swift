import Foundation

/// The on and off of dictation. One gesture does the opposite of whatever state it is in:
/// idle starts, listening stops. A tap that arrives while it is busy is ignored, never queued.
public struct DictationSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Microphone and recogniser are being set up.
        case starting
        case listening
        /// The last words are being finalised before the text is typed.
        case finishing
    }

    public enum Command: Equatable, Sendable {
        case start, stop, ignore
    }

    /// A safety stop so a forgotten session does not listen for ever.
    public static let maxSeconds = 120.0

    public private(set) var phase: Phase = .idle

    public init() {}

    public mutating func toggle() -> Command {
        switch phase {
        case .idle:
            phase = .starting
            return .start
        case .listening:
            phase = .finishing
            return .stop
        case .starting, .finishing:
            return .ignore
        }
    }

    public mutating func started() {
        if phase == .starting { phase = .listening }
    }

    public mutating func startFailed() { phase = .idle }

    public mutating func finished() { phase = .idle }

    public var isListening: Bool { phase == .listening }

    public func shouldAutoStop(listeningFor seconds: Double) -> Bool {
        phase == .listening && seconds >= Self.maxSeconds
    }
}

/// Rules for the text that dictation types.
public enum DictationText {
    /// Trims the transcript and turns every run of spaces and line breaks into one space. Nothing else is
    /// changed, so what the recogniser heard is what gets typed.
    public static func clean(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    public static func wordCount(_ text: String) -> Int {
        clean(text).split(separator: " ").count
    }

    /// Pieces for typing with key events. Each piece has at most `size` UTF-16 units, which is what a key event
    /// carries, and a character is never split, so emoji and accents arrive whole.
    public static func chunks(_ text: String, size: Int = 20) -> [String] {
        var out: [String] = []
        var current = ""
        var units = 0
        for character in text {
            let length = String(character).utf16.count
            if units + length > size, !current.isEmpty {
                out.append(current)
                current = ""
                units = 0
            }
            current.append(character)
            units += length
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// The end of the transcript, for the small pill that shows the words so far.
    public static func tail(_ text: String, maxCharacters: Int = 90) -> String {
        let cleaned = clean(text)
        guard cleaned.count > maxCharacters else { return cleaned }
        let start = cleaned.index(cleaned.endIndex, offsetBy: -maxCharacters)
        let cut = String(cleaned[start...])
        if let space = cut.firstIndex(of: " ") { return "…" + cut[cut.index(after: space)...] }
        return "…" + cut
    }
}
