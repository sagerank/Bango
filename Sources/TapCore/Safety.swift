import Foundation

/// Keeps risky actions away from gestures that are easy to trigger by accident.
public enum SafetyPolicy {
    /// Risky actions need at least this many taps unless the user confirms otherwise.
    public static let minTapsForRisky = 4

    /// Highest danger among the enabled steps of a binding.
    public static func danger(of binding: GestureBinding) -> ActionDanger {
        var worst = ActionDanger.safe
        for step in binding.steps where step.enabled {
            let danger = ActionCatalog.definition(for: step.actionId)?.danger ?? .caution
            if danger > worst { worst = danger }
        }
        return worst
    }

    /// True when the binding does something risky on a gesture with fewer than 4 taps.
    public static func needsAcknowledgement(_ binding: GestureBinding) -> Bool {
        danger(of: binding) >= .caution && binding.taps < minTapsForRisky
    }

    /// Whether the engine may run this binding.
    public static func isAllowed(_ binding: GestureBinding) -> Bool {
        !needsAcknowledgement(binding) || binding.acknowledgedRisk
    }
}
