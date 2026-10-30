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

/// Joins what the recogniser says across pauses into one running transcript.
///
/// The recogniser reports the text of the current stretch of speech only. After a pause (or when it finishes a
/// stretch by itself) the next report starts again from the first new word, so the earlier sentences are no longer
/// in it. Without stitching, the running text stops being an extension of what was already typed and nothing more
/// is ever typed, although the pill still shows the new words.
public struct TranscriptStitcher: Equatable, Sendable {
    /// Finished stretches of speech, in order.
    public private(set) var committed = ""
    private var current = ""
    private var currentStart: Double?

    public init() {}

    /// Everything said so far.
    public var full: String { Self.join(committed, current) }

    /// A new report from the recogniser. `start` is when its first word began, in seconds, if known.
    public mutating func update(_ text: String, start: Double? = nil) {
        if startsNewStretch(text, start: start) { commit() }
        current = text
        if currentStart == nil || start != nil { currentStart = start ?? currentStart }
    }

    /// The recogniser ended this stretch (final result, or its task ended). Whatever comes next is a new stretch.
    public mutating func commit() {
        committed = Self.join(committed, current)
        current = ""
        currentStart = nil
    }

    private static func join(_ a: String, _ b: String) -> String {
        let left = DictationText.clean(a), right = DictationText.clean(b)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + " " + right
    }

    private static func words(_ text: String) -> [String] {
        DictationText.clean(text).split(separator: " ").map {
            $0.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }
    }

    /// Fixes to the last words are normal. A report that is much shorter, shares no opening word, or starts clearly
    /// later in the audio is a fresh stretch, not a correction.
    private func startsNewStretch(_ text: String, start: Double?) -> Bool {
        let old = Self.words(current)
        let new = Self.words(text)
        guard !old.isEmpty, !new.isEmpty else { return false }
        if let start, let currentStart, start - currentStart > 1.0 { return true }
        if new.count + 1 < old.count { return true }
        return old.count >= 2 && old[0] != new[0] && new.count <= old.count
    }
}

/// Decides what to type into the text box while someone is speaking.
///
/// The recogniser keeps changing its mind: it fixes the last words, and it adds capitals and punctuation to words
/// it has already shown. A field cannot be edited the way a draft can, so the rule is: while listening only ever
/// add words that stayed the same across two updates, never delete. When the person finishes, the text in the
/// field is made equal to the final transcript, exactly, by deleting only what was typed here from the first
/// difference onwards and typing the rest again.
public struct LiveTypist: Equatable, Sendable {
    public struct Edit: Equatable, Sendable {
        public var backspaces: Int
        public var insert: String

        public init(backspaces: Int = 0, insert: String = "") {
            self.backspaces = backspaces
            self.insert = insert
        }

        public var isEmpty: Bool { backspaces == 0 && insert.isEmpty }
    }

    /// The most that is ever deleted to correct the ending. Beyond this the text is not touched and the caller is
    /// told (`diverged`), so a very long draft is never wiped on a guess.
    public static let maxCorrection = 600

    /// Everything sent to the app so far.
    public private(set) var typed = ""
    /// True when the final text differs from what was typed by more than `maxCorrection` characters.
    public private(set) var diverged = false
    private var previous = ""

    public init() {}

    private static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var count = 0
        var i = a.startIndex, j = b.startIndex
        while i < a.endIndex, j < b.endIndex, a[i] == b[j] {
            count += 1
            i = a.index(after: i)
            j = b.index(after: j)
        }
        return count
    }

    /// A new partial transcript. Returns what to type now, which is only ever an addition.
    public mutating func update(partial: String) -> Edit {
        let cleaned = DictationText.clean(partial)
        let agreed = Array(cleaned).prefix(Self.commonPrefixLength(previous, cleaned))
        previous = cleaned

        // Only whole words that are followed by a space: the word being spoken right now is not finished.
        guard let lastSpace = agreed.lastIndex(of: " ") else { return Edit() }
        return addition(upTo: String(agreed[...lastSpace]))
    }

    /// The person paused and no new update arrived, so what was heard so far, including the last word, can be typed.
    /// It is still only an addition. Anything the recogniser changes later is fixed at the end.
    public mutating func settle() -> Edit {
        addition(upTo: previous)
    }

    private mutating func addition(upTo safe: String) -> Edit {
        guard safe.count > typed.count, safe.hasPrefix(typed) else { return Edit() }
        let addition = String(safe.dropFirst(typed.count))
        typed = safe
        return Edit(insert: addition)
    }

    /// The final transcript. Returns the edit that makes what was typed equal to it, exactly.
    public mutating func finish(final: String) -> Edit {
        let target = DictationText.clean(final)
        guard !target.isEmpty else { return Edit() }

        let shared = Self.commonPrefixLength(typed, target)
        let tail = typed.count - shared
        guard tail <= Self.maxCorrection else {
            diverged = true
            return Edit()
        }
        typed = target
        return Edit(backspaces: tail, insert: String(target.dropFirst(shared)))
    }
}
