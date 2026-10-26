import Foundation
import TapCore

/// Plain-language names used across the interface.
enum Describe {
    static func taps(_ count: Int) -> String {
        switch count {
        case 1: return "Single tap"
        case 2: return "Double tap"
        case 3: return "Triple tap"
        default: return "\(count) taps"
        }
    }

    static func key(_ key: GestureKey, rhythm: RhythmPattern? = nil) -> String {
        var parts: [String] = []
        if let rhythm {
            parts.append("Rhythm: \(rhythm.summary)")
        } else {
            parts.append(taps(key.taps))
        }
        if key.zone != .any { parts.append(key.zone.title + " side") }
        if key.strength != .any { parts.append(key.strength.title) }
        return parts.joined(separator: " · ")
    }

    static func gesture(_ g: RecognizedGesture) -> String {
        var parts = [taps(g.taps)]
        if g.zone != .any { parts.append(g.zone.title + " side") }
        if g.strength != .any { parts.append(g.strength.title.lowercased()) }
        return parts.joined(separator: " · ")
    }

    static func actionName(_ id: String) -> String {
        ActionCatalog.definition(for: id)?.name ?? "Unknown action"
    }

    /// "Copy, then Paste"
    static func chain(_ steps: [ActionStep]) -> String {
        let names = steps.filter { $0.enabled }.map { step -> String in
            let base = actionName(step.actionId)
            return step.parameter.isEmpty ? base : "\(base) (\(step.parameter))"
        }
        return names.isEmpty ? "Nothing" : names.joined(separator: ", then ")
    }

    static func symbol(for binding: GestureBinding) -> String {
        guard let first = binding.steps.first(where: { $0.enabled }) else { return "nosign" }
        return ActionCatalog.definition(for: first.actionId)?.symbol ?? "questionmark"
    }
}
