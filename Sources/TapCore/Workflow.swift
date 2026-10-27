import Foundation

/// What the Mac looks like right now. The app fills this in at the moment of a gesture and TapCore decides from it,
/// so every rule can be tested without a Mac.
public struct SystemContext: Equatable, Sendable {
    /// Minutes since midnight in local time (0 to 1439).
    public var minutesSinceMidnight: Int
    /// 1 is Sunday and 7 is Saturday, as in `Calendar`.
    public var weekday: Int
    /// Minutes since the Mac was started. Nil when unknown.
    public var minutesSinceBoot: Double?
    public var frontmostBundleID: String?
    public var runningBundleIDs: Set<String>
    /// Nil when the Mac has no battery or it cannot be read.
    public var onBattery: Bool?
    public var batteryPercent: Double?
    public var externalDisplays: Int

    public init(
        minutesSinceMidnight: Int = 0,
        weekday: Int = 2,
        minutesSinceBoot: Double? = nil,
        frontmostBundleID: String? = nil,
        runningBundleIDs: Set<String> = [],
        onBattery: Bool? = nil,
        batteryPercent: Double? = nil,
        externalDisplays: Int = 0
    ) {
        self.minutesSinceMidnight = minutesSinceMidnight
        self.weekday = weekday
        self.minutesSinceBoot = minutesSinceBoot
        self.frontmostBundleID = frontmostBundleID
        self.runningBundleIDs = runningBundleIDs
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.externalDisplays = externalDisplays
    }

    /// Time fields taken from a date.
    public init(now: Date, calendar: Calendar = .current, bootDate: Date? = nil) {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: now)
        self.init(
            minutesSinceMidnight: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
            weekday: parts.weekday ?? 2,
            minutesSinceBoot: bootDate.map { now.timeIntervalSince($0) / 60 }
        )
    }
}

public struct WorkflowCondition: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case justStarted, frontApp, appRunning, timeBetween, weekday, onBattery, batteryBelow, externalDisplay

        public var title: String {
            switch self {
            case .justStarted: return "The Mac just started"
            case .frontApp: return "An app is in front"
            case .appRunning: return "An app is running"
            case .timeBetween: return "The time of day"
            case .weekday: return "The day of the week"
            case .onBattery: return "Battery or plugged in"
            case .batteryBelow: return "The battery level"
            case .externalDisplay: return "An external display"
            }
        }
    }

    public var id: String
    public var kind: Kind
    /// Turns the condition around: "is not in front", "plugged in", "no external display".
    public var negate: Bool
    /// Bundle identifier of the app, for the two app conditions.
    public var value: String
    /// Name of that app, for showing.
    public var label: String
    /// Minutes since midnight, for the time condition.
    public var from: Int
    public var to: Int
    /// Minutes for "just started", percent for the battery level.
    public var number: Double
    /// Calendar weekdays (1 Sunday to 7 Saturday).
    public var days: [Int]

    public init(
        id: String = IDs.new(), kind: Kind, negate: Bool = false, value: String = "", label: String = "",
        from: Int = 9 * 60, to: Int = 17 * 60, number: Double = 30, days: [Int] = [2, 3, 4, 5, 6]
    ) {
        self.id = id
        self.kind = kind
        self.negate = negate
        self.value = value
        self.label = label
        self.from = from
        self.to = to
        self.number = number
        self.days = days
    }

    enum CodingKeys: String, CodingKey { case id, kind, negate, value, label, from, to, number, days }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WorkflowCondition(kind: .justStarted)
        id = c.lenient(.id, IDs.new())
        kind = c.lenient(.kind, d.kind)
        negate = c.lenient(.negate, d.negate)
        value = c.lenient(.value, d.value)
        label = c.lenient(.label, d.label)
        from = c.lenient(.from, d.from)
        to = c.lenient(.to, d.to)
        number = c.lenient(.number, d.number)
        days = c.lenient(.days, d.days)
    }

    /// Whether the condition holds. Anything that cannot be known (no battery, boot time unreadable) counts as
    /// not met, in either direction, so a workflow never runs on a guess.
    public func isMet(in context: SystemContext) -> Bool {
        let result: Bool?
        switch kind {
        case .justStarted:
            result = context.minutesSinceBoot.map { $0 < number }
        case .frontApp:
            result = value.isEmpty ? nil : (context.frontmostBundleID == value)
        case .appRunning:
            result = value.isEmpty ? nil : context.runningBundleIDs.contains(value)
        case .timeBetween:
            let m = context.minutesSinceMidnight
            result = from <= to ? (m >= from && m < to) : (m >= from || m < to)
        case .weekday:
            result = days.isEmpty ? nil : days.contains(context.weekday)
        case .onBattery:
            result = context.onBattery
        case .batteryBelow:
            result = context.batteryPercent.map { $0 < number }
        case .externalDisplay:
            result = context.externalDisplays > 0
        }
        guard let result else { return false }
        return negate ? !result : result
    }

    /// The condition in plain words, for the editor and the log.
    public var summary: String {
        let name = label.isEmpty ? (value.isEmpty ? "an app" : value) : label
        switch kind {
        case .justStarted:
            let minutes = Int(number)
            return negate ? "the Mac started more than \(minutes) minutes ago" : "the Mac started less than \(minutes) minutes ago"
        case .frontApp: return negate ? "\(name) is not in front" : "\(name) is in front"
        case .appRunning: return negate ? "\(name) is not running" : "\(name) is running"
        case .timeBetween:
            let text = "\(Self.clock(from)) and \(Self.clock(to))"
            return negate ? "it is not between \(text)" : "it is between \(text)"
        case .weekday:
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let list = days.sorted().compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }.joined(separator: ", ")
            return negate ? "it is not \(list.isEmpty ? "any day" : list)" : "it is \(list.isEmpty ? "no day" : list)"
        case .onBattery: return negate ? "the Mac is plugged in" : "the Mac is on battery"
        case .batteryBelow:
            return negate ? "the battery is at \(Int(number))% or more" : "the battery is below \(Int(number))%"
        case .externalDisplay: return negate ? "no external display is connected" : "an external display is connected"
        }
    }

    public static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    /// What is missing before this condition can ever be true, or nil when it is complete.
    public var problem: String? {
        switch kind {
        case .frontApp, .appRunning: return value.isEmpty ? "Choose an app" : nil
        case .weekday: return days.isEmpty ? "Choose at least one day" : nil
        default: return nil
        }
    }
}

/// One "If these, then do this".
public struct WorkflowBranch: Codable, Equatable, Identifiable, Sendable {
    public enum Match: String, Codable, CaseIterable, Sendable {
        case all, any
        public var title: String { self == .all ? "all of these" : "any of these" }
    }

    public var id: String
    public var match: Match
    public var conditions: [WorkflowCondition]
    public var steps: [ActionStep]

    public init(id: String = IDs.new(), match: Match = .all, conditions: [WorkflowCondition] = [], steps: [ActionStep] = []) {
        self.id = id
        self.match = match
        self.conditions = conditions
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey { case id, match, conditions, steps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, IDs.new())
        match = c.lenient(.match, Match.all)
        conditions = c.lenient(.conditions, [WorkflowCondition]())
        steps = c.lenient(.steps, [ActionStep]())
    }

    /// A branch with no conditions is always met.
    public func isMet(in context: SystemContext) -> Bool {
        guard !conditions.isEmpty else { return true }
        switch match {
        case .all: return conditions.allSatisfy { $0.isMet(in: context) }
        case .any: return conditions.contains { $0.isMet(in: context) }
        }
    }

    public var summary: String {
        guard !conditions.isEmpty else { return "always" }
        let joiner = match == .all ? " and " : " or "
        return conditions.map { $0.summary }.joined(separator: joiner)
    }
}

/// If, else if, and (by the gesture's own actions) otherwise.
public struct Workflow: Codable, Equatable, Sendable {
    public var branches: [WorkflowBranch]

    public init(branches: [WorkflowBranch] = []) {
        self.branches = branches
    }

    enum CodingKeys: String, CodingKey { case branches }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        branches = c.lenient(.branches, [WorkflowBranch]())
    }

    /// The first branch whose conditions hold, in order.
    public func choose(in context: SystemContext) -> (index: Int, branch: WorkflowBranch)? {
        for (index, branch) in branches.enumerated() where branch.isMet(in: context) {
            return (index, branch)
        }
        return nil
    }

    /// Things to fix before this workflow can behave as intended.
    public var problems: [String] {
        var out: [String] = []
        for (index, branch) in branches.enumerated() {
            let number = index + 1
            if branch.steps.isEmpty { out.append("Branch \(number) has no actions") }
            for condition in branch.conditions {
                if let problem = condition.problem { out.append("Branch \(number): \(problem)") }
            }
        }
        return out
    }
}

public struct ResolvedSteps: Equatable, Sendable {
    public var steps: [ActionStep]
    /// Which branch decided, for the log. Nil when none matched and the gesture's own actions ran.
    public var branchNumber: Int?
    public var branchSummary: String?
}

extension GestureBinding {
    /// Every step this gesture could ever run, in any branch. Safety and permissions look at all of them,
    /// because which branch runs depends on the moment.
    public var allSteps: [ActionStep] {
        (workflow?.branches.flatMap { $0.steps } ?? []) + steps
    }

    /// The steps to run now. With a workflow the first matching branch wins and the gesture's own actions
    /// are the "otherwise". Without a workflow it is just the gesture's actions.
    public func resolvedSteps(in context: SystemContext) -> ResolvedSteps {
        if let workflow, let chosen = workflow.choose(in: context) {
            return ResolvedSteps(steps: chosen.branch.steps, branchNumber: chosen.index + 1, branchSummary: chosen.branch.summary)
        }
        return ResolvedSteps(steps: steps, branchNumber: nil, branchSummary: nil)
    }
}

/// Ready-made workflows, to start from. The apps in them are examples that every Mac has; the owner changes them.
public enum WorkflowTemplates {
    public struct Template: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let detail: String
        public let make: @Sendable () -> GestureBinding
    }

    private static func open(_ app: String, wait: Double = 0) -> ActionStep {
        ActionStep(actionId: "launch-app", parameter: app, delayAfter: wait)
    }

    public static let all: [Template] = [
        Template(
            id: "desk-after-restart",
            title: "Desk after restart",
            detail: "Double tap soon after the Mac started: open your apps. At any other time it does nothing. Change the apps to yours."
        ) {
            GestureBinding(
                key: GestureKey(taps: 2),
                steps: [ActionStep(actionId: ActionCatalog.noneID)],
                workflow: Workflow(branches: [
                    WorkflowBranch(
                        conditions: [WorkflowCondition(kind: .justStarted, number: 45)],
                        steps: [open("Mail", wait: 2), open("Calendar", wait: 2), open("Safari")]
                    ),
                ])
            )
        },
        Template(
            id: "evening-wind-down",
            title: "Evening wind-down",
            detail: "Triple tap between 7 pm and 6 am: dark mode and the screen saver. In the day it plays or pauses."
        ) {
            GestureBinding(
                key: GestureKey(taps: 3),
                steps: [ActionStep(actionId: "play-pause")],
                workflow: Workflow(branches: [
                    WorkflowBranch(
                        conditions: [WorkflowCondition(kind: .timeBetween, from: 19 * 60, to: 6 * 60)],
                        steps: [ActionStep(actionId: "dark-mode", delayAfter: 1), ActionStep(actionId: "screensaver")]
                    ),
                ])
            )
        },
        Template(
            id: "dim-when-low",
            title: "Dim when the battery is low",
            detail: "Triple tap on battery below 25 percent: lower the brightness. Otherwise raise it."
        ) {
            GestureBinding(
                key: GestureKey(taps: 3),
                steps: [ActionStep(actionId: "brightness-up")],
                workflow: Workflow(branches: [
                    WorkflowBranch(
                        match: .all,
                        conditions: [
                            WorkflowCondition(kind: .onBattery),
                            WorkflowCondition(kind: .batteryBelow, number: 25),
                        ],
                        steps: [
                            ActionStep(actionId: "brightness-down", delayAfter: 0.3),
                            ActionStep(actionId: "brightness-down", delayAfter: 0.3),
                            ActionStep(actionId: "brightness-down"),
                        ]
                    ),
                ])
            )
        },
    ]
}
