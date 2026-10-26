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
    public var steps: [ActionStep]
    /// The user confirmed that a risky action may fire on fewer than 4 taps.
    public var acknowledgedRisk: Bool

    public init(
        id: String = IDs.new(),
        key: GestureKey,
        rhythm: RhythmPattern? = nil,
        steps: [ActionStep] = [],
        acknowledgedRisk: Bool = false
    ) {
        self.id = id
        self.key = key
        self.rhythm = rhythm
        self.steps = steps
        self.acknowledgedRisk = acknowledgedRisk
    }

    /// Number of taps this binding needs.
    public var taps: Int { rhythm?.taps ?? key.taps }

    /// How well a gesture fits this binding. Nil means no match. Higher is more specific.
    public func score(for g: RecognizedGesture) -> Int? {
        var score = 0
        if let rhythm {
            guard g.taps == rhythm.taps, rhythm.matches(g.gaps) else { return nil }
            score = 100
        } else {
            guard key.taps == g.taps else { return nil }
        }
        if key.zone != .any {
            guard g.zone == key.zone else { return nil }
            score += 2
        }
        if key.strength != .any {
            guard g.strength == key.strength else { return nil }
            score += 1
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
        if let bundleID = frontmostBundleID,
           let appOverride = appOverrides.first(where: { $0.id == bundleID }),
           let match = GestureBinding.best(in: appOverride.bindings, for: gesture)
        {
            return match
        }
        return GestureBinding.best(in: bindings, for: gesture)
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
