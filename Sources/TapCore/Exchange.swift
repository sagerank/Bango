import Foundation

public enum ExchangeError: Error, Equatable {
    case notAProfile
    case unsupportedVersion(Int)

    public var message: String {
        switch self {
        case .notAProfile: return "This file is not a Bango profile."
        case .unsupportedVersion(let v): return "This profile was made by a newer version (format \(v))."
        }
    }
}

struct ProfileEnvelope: Codable {
    var format: String
    var version: Int
    var profile: Profile
}

public struct ImportResult: Equatable, Sendable {
    public var profile: Profile
    /// Steps switched off because they can run code or open links. The user must enable them by hand.
    public var disabledSteps: Int
}

/// Sharing profiles as JSON. Imports never run code silently.
public enum ProfileExchange {
    static let formatName = "tapdeck-profile"
    static let currentVersion = 1

    public static func export(_ profile: Profile) throws -> Data {
        let envelope = ProfileEnvelope(format: formatName, version: currentVersion, profile: profile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    public static func importProfile(from data: Data) throws -> ImportResult {
        let envelope: ProfileEnvelope
        do {
            envelope = try JSONDecoder().decode(ProfileEnvelope.self, from: data)
        } catch {
            throw ExchangeError.notAProfile
        }
        guard envelope.format == formatName else { throw ExchangeError.notAProfile }
        guard envelope.version <= currentVersion else { throw ExchangeError.unsupportedVersion(envelope.version) }

        var disabled = 0

        func sanitizeSteps(_ steps: [ActionStep]) -> [ActionStep] {
            steps.map { step in
                var s = step
                s.id = IDs.new()
                let definition = ActionCatalog.definition(for: step.actionId)
                if definition == nil || definition?.runsCode == true {
                    if s.enabled { disabled += 1 }
                    s.enabled = false
                }
                return s
            }
        }

        func sanitize(_ bindings: [GestureBinding]) -> [GestureBinding] {
            bindings.map { binding in
                var b = binding
                b.id = IDs.new()
                b.acknowledgedRisk = false
                b.steps = sanitizeSteps(binding.steps)
                if var workflow = binding.workflow {
                    workflow.branches = workflow.branches.map { branch in
                        var nb = branch
                        nb.id = IDs.new()
                        nb.conditions = branch.conditions.map { var c = $0; c.id = IDs.new(); return c }
                        nb.steps = sanitizeSteps(branch.steps)
                        return nb
                    }
                    b.workflow = workflow
                }
                return b
            }
        }

        var profile = envelope.profile
        profile.id = IDs.new()
        profile.bindings = sanitize(profile.bindings)
        profile.appOverrides = profile.appOverrides.map { o in
            var copy = o
            copy.bindings = sanitize(o.bindings)
            return copy
        }
        return ImportResult(profile: profile, disabledSteps: disabled)
    }
}
