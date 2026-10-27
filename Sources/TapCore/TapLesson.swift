import Foundation

/// One step of the guided practice: what to do with your hands, and where.
public struct TapLesson: Identifiable, Equatable, Sendable {
    /// Where on the Mac to tap, used to point at the spot on the picture.
    public enum Spot: Equatable, Sendable {
        case anywhere, left, right, top
    }

    public let id: String
    public let title: String
    public let instruction: String
    public let taps: Int
    public let spot: Spot
    public let successText: String

    /// Zone the tap must land in, or nil when any place counts.
    public var zone: TapZone? {
        switch spot {
        case .anywhere: return nil
        case .left: return .left
        case .right: return .right
        case .top: return .top
        }
    }

    public var needsZones: Bool { zone != nil }
}

public enum LessonResult: Equatable, Sendable {
    case success(String)
    case tryAgain(String)
}

public enum TapLessons {
    /// The first practice: counting taps. Works on every Mac with the sensor.
    public static let basic: [TapLesson] = [
        TapLesson(
            id: "single", title: "Tap once",
            instruction: "Knock the palm rest once with one fingertip, like knocking on a door. The palm rest is the flat area under the keyboard.",
            taps: 1, spot: .anywhere, successText: "One tap. That is the simplest gesture."
        ),
        TapLesson(
            id: "double", title: "Tap twice",
            instruction: "Knock twice, quickly, like a double click: tap-tap. Then stop and wait a moment.",
            taps: 2, spot: .anywhere, successText: "Two taps. Double taps are easy to repeat on purpose."
        ),
        TapLesson(
            id: "triple", title: "Tap three times",
            instruction: "Three quick knocks in a row: tap-tap-tap. Keep the same speed, then stop.",
            taps: 3, spot: .anywhere, successText: "Three taps. Four and five work the same way."
        ),
    ]

    /// Needs the one-time zone setup. Experimental.
    public static let zones: [TapLesson] = [
        TapLesson(
            id: "left", title: "Tap the left side",
            instruction: "Knock once on the palm rest to the left of the trackpad.",
            taps: 1, spot: .left, successText: "Left side recognised."
        ),
        TapLesson(
            id: "right", title: "Tap the right side",
            instruction: "Knock once on the palm rest to the right of the trackpad.",
            taps: 1, spot: .right, successText: "Right side recognised."
        ),
        TapLesson(
            id: "top", title: "Tap near the hinge",
            instruction: "Knock once on the strip just above the keyboard, close to the screen hinge.",
            taps: 1, spot: .top, successText: "Top recognised."
        ),
    ]

    /// Judges one finished gesture against a lesson and says what to do next in plain words.
    public static func evaluate(_ lesson: TapLesson, gesture g: RecognizedGesture) -> LessonResult {
        if g.taps != lesson.taps {
            return .tryAgain(miscount(want: lesson.taps, gesture: g))
        }
        if let wanted = lesson.zone {
            switch g.zone {
            case wanted:
                break
            case .any:
                return .tryAgain("Bango could not tell where that tap was. Tap closer to the edge of the \(name(of: wanted)), with one fingertip.")
            default:
                return .tryAgain("That felt like the \(name(of: g.zone)). Try the \(name(of: wanted)) instead.")
            }
        }
        return .success(lesson.successText)
    }

    private static func name(of zone: TapZone) -> String {
        zone == .top ? "top, near the hinge" : "\(zone.title.lowercased()) side"
    }

    private static func plural(_ n: Int) -> String { n == 1 ? "1 tap" : "\(n) taps" }

    private static func miscount(want: Int, gesture g: RecognizedGesture) -> String {
        if g.taps > want {
            return want == 1
                ? "That counted as \(plural(g.taps)). Tap once, then keep your hand still for a moment."
                : "That counted as \(plural(g.taps)). Tap exactly \(want) times, then stop."
        }
        let meanGap = g.gaps.isEmpty ? 0 : g.gaps.reduce(0, +) / Double(g.gaps.count)
        if g.taps >= 2 && meanGap > 0.45 {
            return "Too slow: that was \(g.taps) separate taps. Tap faster, with almost no pause between them."
        }
        return "That was only \(plural(g.taps)). Tap \(want) times quickly in a row."
    }
}
