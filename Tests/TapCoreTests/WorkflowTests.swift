import XCTest
@testable import TapCore

final class WorkflowConditionTests: XCTestCase {
    private func context(minutes: Int = 600, weekday: Int = 3, boot: Double? = nil, front: String? = nil,
                         running: Set<String> = [], battery: Bool? = nil, percent: Double? = nil, displays: Int = 0) -> SystemContext {
        SystemContext(minutesSinceMidnight: minutes, weekday: weekday, minutesSinceBoot: boot, frontmostBundleID: front,
                      runningBundleIDs: running, onBattery: battery, batteryPercent: percent, externalDisplays: displays)
    }

    func testJustStartedUsesMinutesSinceBootAndNeverGuesses() {
        let c = WorkflowCondition(kind: .justStarted, number: 30)
        XCTAssertTrue(c.isMet(in: context(boot: 10)))
        XCTAssertFalse(c.isMet(in: context(boot: 90)))
        XCTAssertFalse(c.isMet(in: context(boot: nil)))
        var notRecent = c; notRecent.negate = true
        XCTAssertTrue(notRecent.isMet(in: context(boot: 90)))
        XCTAssertFalse(notRecent.isMet(in: context(boot: nil)), "unknown is not met in either direction")
    }

    func testTimeBetweenIncludingAcrossMidnight() {
        let day = WorkflowCondition(kind: .timeBetween, from: 9 * 60, to: 17 * 60)
        XCTAssertTrue(day.isMet(in: context(minutes: 9 * 60)))
        XCTAssertFalse(day.isMet(in: context(minutes: 17 * 60)))
        let night = WorkflowCondition(kind: .timeBetween, from: 19 * 60, to: 6 * 60)
        XCTAssertTrue(night.isMet(in: context(minutes: 23 * 60)))
        XCTAssertTrue(night.isMet(in: context(minutes: 2 * 60)))
        XCTAssertFalse(night.isMet(in: context(minutes: 12 * 60)))
    }

    func testWeekdays() {
        let weekdays = WorkflowCondition(kind: .weekday, days: [2, 3, 4, 5, 6])
        XCTAssertTrue(weekdays.isMet(in: context(weekday: 3)))
        XCTAssertFalse(weekdays.isMet(in: context(weekday: 1)))
        XCTAssertFalse(WorkflowCondition(kind: .weekday, days: []).isMet(in: context()))
    }

    func testAppConditionsAndTheirNegation() {
        var front = WorkflowCondition(kind: .frontApp, value: "com.apple.Safari")
        XCTAssertTrue(front.isMet(in: context(front: "com.apple.Safari")))
        XCTAssertFalse(front.isMet(in: context(front: "com.apple.Notes")))
        front.negate = true
        XCTAssertTrue(front.isMet(in: context(front: "com.apple.Notes")))
        XCTAssertFalse(WorkflowCondition(kind: .frontApp).isMet(in: context(front: "x")), "no app chosen is never met")
        XCTAssertTrue(WorkflowCondition(kind: .appRunning, value: "a.b").isMet(in: context(running: ["a.b"])))
    }

    func testPowerAndDisplayConditions() {
        XCTAssertTrue(WorkflowCondition(kind: .onBattery).isMet(in: context(battery: true)))
        XCTAssertFalse(WorkflowCondition(kind: .onBattery).isMet(in: context(battery: false)))
        XCTAssertFalse(WorkflowCondition(kind: .onBattery).isMet(in: context(battery: nil)))
        XCTAssertTrue(WorkflowCondition(kind: .batteryBelow, number: 25).isMet(in: context(percent: 20)))
        XCTAssertFalse(WorkflowCondition(kind: .batteryBelow, number: 25).isMet(in: context(percent: nil)))
        XCTAssertTrue(WorkflowCondition(kind: .externalDisplay).isMet(in: context(displays: 1)))
        XCTAssertTrue(WorkflowCondition(kind: .externalDisplay, negate: true).isMet(in: context(displays: 0)))
    }

    func testNetworkAndPowerConditionsNeverGuess() {
        let on = SystemContext(wifiOn: true, wifiConnected: false, lowPowerMode: true)
        XCTAssertTrue(WorkflowCondition(kind: .wifiOn).isMet(in: on))
        XCTAssertFalse(WorkflowCondition(kind: .wifiConnected).isMet(in: on))
        XCTAssertTrue(WorkflowCondition(kind: .wifiConnected, negate: true).isMet(in: on))
        XCTAssertTrue(WorkflowCondition(kind: .lowPowerMode).isMet(in: on))
        let unknown = SystemContext()
        for kind in [WorkflowCondition.Kind.wifiOn, .wifiConnected, .bluetoothOn, .lowPowerMode] {
            XCTAssertFalse(WorkflowCondition(kind: kind).isMet(in: unknown), "\(kind) unknown is not met")
            XCTAssertFalse(WorkflowCondition(kind: kind, negate: true).isMet(in: unknown), "\(kind) unknown is not met when negated")
        }
    }

    func testBluetoothDevicesMatchPartOfTheNameAndNeedBluetoothOn() {
        let c = SystemContext(bluetoothOn: true, bluetoothDevices: ["Alex's AirPods Pro", "Magic Keyboard"])
        XCTAssertTrue(WorkflowCondition(kind: .bluetoothDevice, value: "airpods").isMet(in: c), "capitals do not matter")
        XCTAssertTrue(WorkflowCondition(kind: .bluetoothDevice, value: "").isMet(in: c), "no name means any device")
        XCTAssertFalse(WorkflowCondition(kind: .bluetoothDevice, value: "Mouse").isMet(in: c))
        XCTAssertTrue(WorkflowCondition(kind: .bluetoothDevice, negate: true, value: "Mouse").isMet(in: c))
        let off = SystemContext(bluetoothOn: false, bluetoothDevices: [])
        XCTAssertFalse(WorkflowCondition(kind: .bluetoothDevice, value: "AirPods").isMet(in: off))
        XCTAssertTrue(WorkflowCondition(kind: .bluetoothDevice, negate: true, value: "AirPods").isMet(in: off))
        XCTAssertFalse(WorkflowCondition(kind: .bluetoothDevice, value: "AirPods").isMet(in: SystemContext()), "unreadable Bluetooth is unknown")
        XCTAssertFalse(WorkflowCondition(kind: .bluetoothDevice, negate: true, value: "AirPods").isMet(in: SystemContext()))
    }

    func testUSBAndAudioOutputConditions() {
        let c = SystemContext(usbDevices: ["Logitech MX Keys", "CalDigit TS4"], audioOutput: "MacBook Pro Speakers")
        XCTAssertTrue(WorkflowCondition(kind: .usbDevice, value: "caldigit").isMet(in: c))
        XCTAssertTrue(WorkflowCondition(kind: .usbDevice).isMet(in: c), "any USB device")
        XCTAssertFalse(WorkflowCondition(kind: .usbDevice).isMet(in: SystemContext()), "nothing plugged in")
        XCTAssertTrue(WorkflowCondition(kind: .usbDevice, negate: true).isMet(in: SystemContext()))
        XCTAssertTrue(WorkflowCondition(kind: .audioOutput, value: "speakers").isMet(in: c))
        XCTAssertFalse(WorkflowCondition(kind: .audioOutput, value: "AirPods").isMet(in: c))
        XCTAssertFalse(WorkflowCondition(kind: .audioOutput, value: "AirPods").isMet(in: SystemContext()), "unknown output")
        XCTAssertFalse(WorkflowCondition(kind: .audioOutput).isMet(in: c), "no name chosen is never met")
        XCTAssertNotNil(WorkflowCondition(kind: .audioOutput).problem)
        XCTAssertNil(WorkflowCondition(kind: .usbDevice).problem)
    }

    func testDeviceConditionsReadAsPlainWordsAndSurviveSaving() throws {
        XCTAssertEqual(WorkflowCondition(kind: .bluetoothDevice, value: "AirPods").summary, "AirPods is connected")
        XCTAssertEqual(WorkflowCondition(kind: .usbDevice, negate: true).summary, "A USB device is not plugged in")
        XCTAssertEqual(WorkflowCondition(kind: .audioOutput, value: "AirPods").summary, "the sound is going to AirPods")
        XCTAssertEqual(WorkflowCondition(kind: .wifiOn, negate: true).summary, "Wi-Fi is off")
        let original = WorkflowCondition(kind: .usbDevice, negate: true, value: "Dock")
        let decoded = try JSONDecoder().decode(WorkflowCondition.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        // A profile saved by a newer Bango with a condition this one does not know falls back to a safe default.
        let future = #"{"id":"x","kind":"someFutureKind"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(WorkflowCondition.self, from: future).kind, .justStarted)
    }

    func testSummariesReadAsPlainWords() {
        XCTAssertEqual(WorkflowCondition(kind: .justStarted, number: 30).summary, "the Mac started less than 30 minutes ago")
        XCTAssertEqual(WorkflowCondition(kind: .timeBetween, from: 19 * 60, to: 6 * 60).summary, "it is between 19:00 and 06:00")
        XCTAssertEqual(WorkflowCondition(kind: .weekday, days: [2, 6]).summary, "it is Mon, Fri")
        XCTAssertEqual(WorkflowCondition(kind: .frontApp, value: "x.y", label: "Safari").summary, "Safari is in front")
        XCTAssertEqual(WorkflowCondition(kind: .onBattery, negate: true).summary, "the Mac is plugged in")
    }

    func testSystemContextFromADate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_793_089_800) // Tue 2026-10-27 08:30 UTC
        let c = SystemContext(now: now, calendar: calendar, bootDate: now.addingTimeInterval(-20 * 60))
        XCTAssertEqual(c.minutesSinceMidnight, 8 * 60 + 30)
        XCTAssertEqual(c.weekday, 3)
        XCTAssertEqual(c.minutesSinceBoot ?? 0, 20, accuracy: 0.01)
    }
}

final class WorkflowBranchTests: XCTestCase {
    private func binding(branches: [WorkflowBranch], otherwise: [ActionStep] = [ActionStep(actionId: "mute")], taps: Int = 2) -> GestureBinding {
        GestureBinding(key: GestureKey(taps: taps), steps: otherwise, workflow: Workflow(branches: branches))
    }

    func testBranchMatchAllAnyAndEmpty() {
        let ctx = SystemContext(minutesSinceBoot: 5, onBattery: true)
        let yes = WorkflowCondition(kind: .justStarted, number: 30)
        let no = WorkflowCondition(kind: .externalDisplay)
        XCTAssertTrue(WorkflowBranch(match: .all, conditions: [yes, WorkflowCondition(kind: .onBattery)]).isMet(in: ctx))
        XCTAssertFalse(WorkflowBranch(match: .all, conditions: [yes, no]).isMet(in: ctx))
        XCTAssertTrue(WorkflowBranch(match: .any, conditions: [yes, no]).isMet(in: ctx))
        XCTAssertTrue(WorkflowBranch(conditions: []).isMet(in: ctx))
    }

    func testFirstMatchingBranchWinsAndOtherwiseRunsWhenNoneMatch() {
        let a = WorkflowBranch(conditions: [WorkflowCondition(kind: .externalDisplay)], steps: [ActionStep(actionId: "copy")])
        let b = WorkflowBranch(conditions: [WorkflowCondition(kind: .onBattery)], steps: [ActionStep(actionId: "paste")])
        let c = WorkflowBranch(conditions: [WorkflowCondition(kind: .onBattery)], steps: [ActionStep(actionId: "cut")])
        let gesture = binding(branches: [a, b, c])
        let r = gesture.resolvedSteps(in: SystemContext(onBattery: true))
        XCTAssertEqual(r.steps.first?.actionId, "paste")
        XCTAssertEqual(r.branchNumber, 2)
        let none = gesture.resolvedSteps(in: SystemContext(onBattery: false))
        XCTAssertEqual(none.steps.first?.actionId, "mute")
        XCTAssertNil(none.branchNumber)
    }

    func testAGestureWithoutAWorkflowBehavesAsBefore() {
        let plain = GestureBinding(key: GestureKey(taps: 2), steps: [ActionStep(actionId: "copy")])
        XCTAssertEqual(plain.resolvedSteps(in: SystemContext()).steps.map { $0.actionId }, ["copy"])
        XCTAssertEqual(plain.allSteps.count, 1)
    }

    func testSafetyLooksAtEveryBranchNotJustTheOneThatRunsNow() {
        let risky = WorkflowBranch(conditions: [WorkflowCondition(kind: .externalDisplay)], steps: [ActionStep(actionId: "wifi-toggle")])
        let gesture = binding(branches: [risky], taps: 2)
        XCTAssertTrue(SafetyPolicy.needsAcknowledgement(gesture))
        XCTAssertFalse(SafetyPolicy.isAllowed(gesture))
        XCTAssertTrue(SafetyPolicy.isAllowed(binding(branches: [risky], taps: 4)))
    }

    func testPermissionPlanCountsStepsInBranches() {
        let branch = WorkflowBranch(steps: [ActionStep(actionId: "eject-all")])
        var config = AppConfig()
        config.profiles = [Profile(name: "p", bindings: [binding(branches: [branch], otherwise: [ActionStep(actionId: "none")], taps: 4)])]
        config.activeProfileID = config.profiles[0].id
        XCTAssertEqual(PermissionPlan.usage(in: config)[.finder], ["Eject all drives"])
    }

    func testOldSavedGesturesStillLoadAndWorkflowsRoundTrip() throws {
        let old = Data(#"{"id":"1","key":{"taps":2,"zone":"any","strength":"any"},"steps":[],"acknowledgedRisk":false}"#.utf8)
        let loaded = try JSONDecoder().decode(GestureBinding.self, from: old)
        XCTAssertNil(loaded.workflow)

        let original = binding(branches: [WorkflowBranch(conditions: [WorkflowCondition(kind: .timeBetween)], steps: [ActionStep(actionId: "copy")])])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(GestureBinding.self, from: data), original)
    }

    func testAMalformedConditionFallsBackInsteadOfLosingTheGesture() throws {
        let json = Data(#"{"id":"1","kind":"nonsense","number":"x"}"#.utf8)
        let condition = try JSONDecoder().decode(WorkflowCondition.self, from: json)
        XCTAssertEqual(condition.kind, .justStarted)
        XCTAssertEqual(condition.number, 30)
    }

    func testImportSwitchesOffCodeRunningStepsInsideBranches() throws {
        let branch = WorkflowBranch(steps: [ActionStep(actionId: "shell-command", parameter: "echo hi"), ActionStep(actionId: "copy")])
        let profile = Profile(name: "shared", bindings: [binding(branches: [branch])])
        let data = try ProfileExchange.export(profile)
        let result = try ProfileExchange.importProfile(from: data)
        let steps = try XCTUnwrap(result.profile.bindings.first?.workflow?.branches.first?.steps)
        XCTAssertFalse(steps[0].enabled)
        XCTAssertTrue(steps[1].enabled)
        XCTAssertEqual(result.disabledSteps, 1)
        XCTAssertNotEqual(result.profile.bindings.first?.workflow?.branches.first?.id, branch.id)
    }

    func testDuplicatingAProfileGivesTheBranchesNewIdentifiers() {
        let branch = WorkflowBranch(conditions: [WorkflowCondition(kind: .onBattery)], steps: [ActionStep(actionId: "copy")])
        let profile = Profile(name: "p", bindings: [binding(branches: [branch])])
        let copy = profile.duplicated()
        let copied = copy.bindings[0].workflow!.branches[0]
        XCTAssertNotEqual(copied.id, branch.id)
        XCTAssertNotEqual(copied.conditions[0].id, branch.conditions[0].id)
        XCTAssertNotEqual(copied.steps[0].id, branch.steps[0].id)
        XCTAssertEqual(copied.steps[0].actionId, "copy")
    }

    func testProblemsAreReportedInPlainWords() {
        let workflow = Workflow(branches: [
            WorkflowBranch(conditions: [WorkflowCondition(kind: .frontApp)], steps: []),
            WorkflowBranch(conditions: [WorkflowCondition(kind: .weekday, days: [])], steps: [ActionStep(actionId: "copy")]),
        ])
        XCTAssertEqual(workflow.problems, ["Branch 1 has no actions", "Branch 1: Choose an app", "Branch 2: Choose at least one day"])
        XCTAssertTrue(Workflow(branches: [WorkflowBranch(steps: [ActionStep(actionId: "copy")])]).problems.isEmpty)
    }
}

final class WorkflowTemplateTests: XCTestCase {
    func testEveryTemplateIsCompleteSafeAndUsesKnownActions() {
        XCTAssertGreaterThanOrEqual(WorkflowTemplates.all.count, 3)
        for template in WorkflowTemplates.all {
            let gesture = template.make()
            XCTAssertEqual(gesture.workflow?.problems, [], template.id)
            XCTAssertTrue(SafetyPolicy.isAllowed(gesture), "\(template.id) must not need a confirmation")
            for step in gesture.allSteps {
                XCTAssertNotNil(ActionCatalog.definition(for: step.actionId), "\(template.id): \(step.actionId)")
            }
        }
    }

    func testDeskAfterRestartOnlyActsSoonAfterStart() {
        let gesture = WorkflowTemplates.all.first { $0.id == "desk-after-restart" }!.make()
        let soon = gesture.resolvedSteps(in: SystemContext(minutesSinceBoot: 5))
        XCTAssertEqual(soon.steps.map { $0.actionId }, ["open-apps", "apply-layout"])
        XCTAssertEqual(soon.steps.first?.parameter, "Mail, Calendar, Safari")
        let later = gesture.resolvedSteps(in: SystemContext(minutesSinceBoot: 600))
        XCTAssertEqual(later.steps.map { $0.actionId }, ["none"])
    }

    func testEveningWindDownChoosesByTime() {
        let gesture = WorkflowTemplates.all.first { $0.id == "evening-wind-down" }!.make()
        XCTAssertEqual(gesture.resolvedSteps(in: SystemContext(minutesSinceMidnight: 22 * 60)).steps.first?.actionId, "dark-mode")
        XCTAssertEqual(gesture.resolvedSteps(in: SystemContext(minutesSinceMidnight: 14 * 60)).steps.first?.actionId, "play-pause")
    }
}
