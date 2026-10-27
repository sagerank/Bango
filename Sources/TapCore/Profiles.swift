import Foundation

public enum IDs {
    public static func new() -> String { UUID().uuidString }
}

/// One step of an action chain.
public struct ActionStep: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var actionId: String
    public var parameter: String
    /// Pause after this step before the next one, in seconds.
    public var delayAfter: Double
    /// Imported steps that can run code start disabled.
    public var enabled: Bool

    public init(
        id: String = IDs.new(),
        actionId: String,
        parameter: String = "",
        delayAfter: Double = 0,
        enabled: Bool = true
    ) {
        self.id = id
        self.actionId = actionId
        self.parameter = parameter
        self.delayAfter = delayAfter
        self.enabled = enabled
    }
}

/// What a gesture must look like to trigger a binding.
public struct GestureKey: Codable, Hashable, Sendable {
    public var taps: Int
    public var zone: TapZone
    public var strength: TapStrength

    public init(taps: Int, zone: TapZone = .any, strength: TapStrength = .any) {
        self.taps = taps
        self.zone = zone
        self.strength = strength
    }
}

/// Links a gesture to a chain of actions.
public struct GestureBinding: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var key: GestureKey
    /// When set, the binding matches this tap rhythm instead of a plain tap count.
    public var rhythm: RhythmPattern?
    /// The gesture's own actions. With a workflow these are the "otherwise": what runs when no branch matches.
    public var steps: [ActionStep]
    /// Optional if and else branches that choose what runs.
    public var workflow: Workflow?
    /// The user confirmed that a risky action may fire on fewer than 4 taps.
    public var acknowledgedRisk: Bool

    public init(
        id: String = IDs.new(),
        key: GestureKey,
        rhythm: RhythmPattern? = nil,
        steps: [ActionStep] = [],
        workflow: Workflow? = nil,
        acknowledgedRisk: Bool = false
    ) {
        self.id = id
        self.key = key
        self.rhythm = rhythm
        self.steps = steps
        self.workflow = workflow
        self.acknowledgedRisk = acknowledgedRisk
    }

    /// Number of taps this binding needs.
    public var taps: Int { rhythm?.taps ?? key.taps }

    /// How well a gesture fits this binding. Nil means no match. Higher is more specific.
    public func score(for g: RecognizedGesture) -> Int? {
        var score = 0
        if let rhythm {
            guard g.taps == rhythm.taps, let deviation = rhythm.deviation(of: g.gaps), deviation <= 1 else { return nil }
            // A rhythm beats a plain tap count. Between two rhythms, the closer one wins.
            score = 1000 + Int((1 - deviation) * 99)
        } else {
            guard key.taps == g.taps else { return nil }
        }
        if key.zone != .any {
            guard g.zone == key.zone else { return nil }
            score += 200
        }
        if key.strength != .any {
            guard g.strength == key.strength else { return nil }
            score += 100
        }
        return score
    }

    public static func best(in bindings: [GestureBinding], for g: RecognizedGesture) -> GestureBinding? {
        var best: GestureBinding?
        var bestScore = -1
        for binding in bindings {
            if let s = binding.score(for: g), s > bestScore {
                best = binding
                bestScore = s
            }
        }
        return best
    }
}

/// Bindings that replace the profile's own while a given app is in front.
public struct AppOverride: Codable, Equatable, Identifiable, Sendable {
    /// Bundle identifier of the app.
    public var id: String
    public var appName: String
    public var bindings: [GestureBinding]

    public init(id: String, appName: String, bindings: [GestureBinding] = []) {
        self.id = id
        self.appName = appName
        self.bindings = bindings
    }
}

public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var bindings: [GestureBinding]
    public var appOverrides: [AppOverride]

    public init(
        id: String = IDs.new(),
        name: String,
        bindings: [GestureBinding] = [],
        appOverrides: [AppOverride] = []
    ) {
        self.id = id
        self.name = name
        self.bindings = bindings
        self.appOverrides = appOverrides
    }

    /// The binding to run for a gesture. The frontmost app's override wins, then the profile itself.
    public func resolve(_ gesture: RecognizedGesture, frontmostBundleID: String?) -> GestureBinding? {
        resolution(for: gesture, frontmostBundleID: frontmostBundleID)?.binding
    }

    /// Like `resolve`, and also says which app's override decided it, so the activity log can show it.
    public func resolution(
        for gesture: RecognizedGesture, frontmostBundleID: String?
    ) -> (binding: GestureBinding, appName: String?)? {
        if let bundleID = frontmostBundleID,
           let appOverride = appOverrides.first(where: { $0.id == bundleID }),
           let match = GestureBinding.best(in: appOverride.bindings, for: gesture)
        {
            return (match, appOverride.appName)
        }
        if let match = GestureBinding.best(in: bindings, for: gesture) {
            return (match, nil)
        }
        return nil
    }

    /// When a rhythm gesture exists for this tap count but the performed gaps did not fit it, says by how much,
    /// so a rhythm that falls back to the plain tap count can be understood. Nil when no rhythm was in play.
    public func rhythmMissNote(for gesture: RecognizedGesture, frontmostBundleID: String?) -> String? {
        var pool = bindings
        if let bundleID = frontmostBundleID, let appOverride = appOverrides.first(where: { $0.id == bundleID }) {
            pool = appOverride.bindings + pool
        }
        guard let rhythm = pool.compactMap({ $0.rhythm }).first(where: { $0.taps == gesture.taps }) else { return nil }
        func format(_ values: [Double]) -> String {
            values.map { String(format: "%.2f", $0) }.joined(separator: ", ")
        }
        return "rhythm not matched (you \(format(gesture.gaps)) s, recorded \(format(rhythm.gaps)) s)"
    }

    /// When a gesture matched nothing, says whether that is because a soft/hard or left/right/top gesture exists
    /// for this tap count but the detection it needs is switched off. Nil when that is not the reason.
    public func missingSetupHint(for gesture: RecognizedGesture, strengthOn: Bool, zonesOn: Bool) -> String? {
        let sameTaps = (bindings + appOverrides.flatMap { $0.bindings }).filter { $0.taps == gesture.taps }
        if !strengthOn, sameTaps.contains(where: { $0.key.strength != .any }) {
            return "A soft or hard gesture exists for \(gesture.taps) taps, but soft and hard detection is off. Teach it in Tuning."
        }
        if !zonesOn, sameTaps.contains(where: { $0.key.zone != .any }) {
            return "A left, right or top gesture exists for \(gesture.taps) taps, but zones are not set up. Set them up in Zones & rhythm."
        }
        return nil
    }

    /// A copy with fresh identifiers, so both profiles can be edited independently.
    public func duplicated(named newName: String? = nil) -> Profile {
        func fresh(_ bindings: [GestureBinding]) -> [GestureBinding] {
            bindings.map { binding in
                var b = binding
                b.id = IDs.new()
                b.steps = binding.steps.map { step in
                    var s = step
                    s.id = IDs.new()
                    return s
                }
                if var workflow = binding.workflow {
                    workflow.branches = workflow.branches.map { branch in
                        var nb = branch
                        nb.id = IDs.new()
                        nb.conditions = branch.conditions.map { var c = $0; c.id = IDs.new(); return c }
                        nb.steps = branch.steps.map { var s = $0; s.id = IDs.new(); return s }
                        return nb
                    }
                    b.workflow = workflow
                }
                return b
            }
        }
        var copy = self
        copy.id = IDs.new()
        copy.name = newName ?? "\(name) copy"
        copy.bindings = fresh(bindings)
        copy.appOverrides = appOverrides.map { o in
            var c = o
            c.bindings = fresh(o.bindings)
            return c
        }
        return copy
    }

    /// Every rhythm used anywhere in this profile.
    public var rhythms: [RhythmPattern] {
        let all = bindings + appOverrides.flatMap { $0.bindings }
        return all.compactMap { $0.rhythm }
    }
}

public enum DefaultProfiles {
    /// Name of the profile that is built for taking screenshots.
    public static let screenshotsName = "Screenshots"
    public static let voiceName = "Voice"

    private static func screenshots() -> Profile {
        func bind(_ taps: Int, _ action: String) -> GestureBinding {
            GestureBinding(key: GestureKey(taps: taps), steps: [ActionStep(actionId: action)])
        }
        return Profile(name: screenshotsName, bindings: [
            bind(1, "capture-area-clipboard"),
            bind(2, "capture-area-save"),
            bind(3, "capture-full-save"),
            bind(4, "capture-area-edit"),
            bind(5, "screenshot-toolbar"),
        ])
    }

    /// Starter profiles whose names are not in `existing`, for people who already have a saved setup.
    public static func missing(from existing: [Profile]) -> [Profile] {
        let names = Set(existing.map { $0.name.lowercased() })
        return make().filter { !names.contains($0.name.lowercased()) }
    }

    public static func make() -> [Profile] {
        func bind(_ taps: Int, _ action: String, _ parameter: String = "") -> GestureBinding {
            GestureBinding(
                key: GestureKey(taps: taps),
                steps: [ActionStep(actionId: action, parameter: parameter)]
            )
        }
        return [
            Profile(name: "Work", bindings: [
                bind(1, "play-pause"),
                bind(2, "copy"),
                bind(3, "paste"),
                bind(4, "lock-screen"),
            ]),
            Profile(name: voiceName, bindings: [
                bind(2, "dictation-toggle"),
            ]),
            Profile(name: "Media", bindings: [
                bind(1, "play-pause"),
                bind(2, "next-track"),
                bind(3, "previous-track"),
                bind(4, "mute"),
            ]),
            Profile(name: "Meeting", bindings: [
                bind(1, "mic-mute"),
                bind(2, "caffeine"),
                bind(3, "screenshot-area"),
                bind(4, "lock-screen"),
            ]),
            screenshots(),
        ]
    }
}
