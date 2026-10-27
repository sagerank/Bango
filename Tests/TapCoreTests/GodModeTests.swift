import XCTest
@testable import TapCore

/// Groups of conditions, and "only if" on a single action.
final class GodModeTests: XCTestCase {
    private let evening = SystemContext(minutesSinceMidnight: 20 * 60, weekday: 3, onBattery: false, batteryPercent: 80,
                                        wifiOn: true, wifiConnected: true, bluetoothOn: true,
                                        bluetoothDevices: ["AirPods Pro"], audioOutput: "AirPods Pro")

    private func night() -> WorkflowCondition { WorkflowCondition(kind: .timeBetween, from: 19 * 60, to: 6 * 60) }
    private func airpods() -> WorkflowCondition { WorkflowCondition(kind: .bluetoothDevice, value: "AirPods") }
    private func lowBattery() -> WorkflowCondition { WorkflowCondition(kind: .batteryBelow, number: 20) }

    func testGroupsNestAndOrWithNot() {
        // (night and AirPods) or low battery
        let both = WorkflowCondition(kind: .group, children: [night(), airpods()], match: .all)
        let outer = WorkflowCondition(kind: .group, children: [both, lowBattery()], match: .any)
        XCTAssertTrue(outer.isMet(in: evening))
        var noPods = evening; noPods.bluetoothDevices = []
        XCTAssertFalse(outer.isMet(in: noPods))
        noPods.batteryPercent = 10
        XCTAssertTrue(outer.isMet(in: noPods), "the low battery side is enough")
        var negated = outer; negated.negate = true
        XCTAssertFalse(negated.isMet(in: noPods))
    }

    func testEmptyOrBrokenGroupsNeverMatch() {
        let empty = WorkflowCondition(kind: .group)
        XCTAssertFalse(empty.isMet(in: evening))
        var negated = empty; negated.negate = true
        XCTAssertFalse(negated.isMet(in: evening), "an empty group is unknown, also when negated")
        XCTAssertEqual(empty.problem, "Add at least one condition to the group")
        let broken = WorkflowCondition(kind: .group, children: [WorkflowCondition(kind: .audioOutput)])
        XCTAssertNotNil(broken.problem, "a problem inside a group is reported")
    }

    func testKindsIncludeGroupMembersSoTheAppReadsThem() {
        let group = WorkflowCondition(kind: .group, children: [
            airpods(),
            WorkflowCondition(kind: .group, children: [WorkflowCondition(kind: .wifiConnected), WorkflowCondition(kind: .usbDevice)]),
        ])
        XCTAssertEqual(group.kinds, [.group, .bluetoothDevice, .wifiConnected, .usbDevice])
        let branch = WorkflowBranch(conditions: [group, night()])
        XCTAssertTrue(branch.kinds.contains(.timeBetween))
        XCTAssertTrue(Workflow(branches: [branch]).kinds.contains(.usbDevice))
    }

    func testGroupSummaryReadsAsPlainWords() {
        let group = WorkflowCondition(kind: .group, children: [airpods(), night()], match: .any)
        XCTAssertEqual(group.summary, "(AirPods is connected or it is between 19:00 and 06:00)")
        var negated = group; negated.negate = true
        XCTAssertEqual(negated.summary, "not (AirPods is connected or it is between 19:00 and 06:00)")
    }

    func testStepGuardDecidesFromItsOwnConditions() {
        XCTAssertTrue(StepGuard().isMet(in: evening), "no conditions: always runs")
        let g = StepGuard(conditions: [airpods(), night()], match: .all)
        XCTAssertTrue(g.isMet(in: evening))
        var day = evening; day.minutesSinceMidnight = 12 * 60
        XCTAssertFalse(g.isMet(in: day))
        XCTAssertTrue(StepGuard(conditions: [airpods(), night()], match: .any).isMet(in: day))
    }

    func testWaitIsKeptInRange() {
        XCTAssertEqual(StepGuard(otherwise: .wait, waitSeconds: 9999).waitLimit, 60)
        XCTAssertEqual(StepGuard(otherwise: .wait, waitSeconds: 0).waitLimit, 1)
        XCTAssertEqual(StepGuard(otherwise: .wait, waitSeconds: 12).waitLimit, 12)
    }

    func testGuardsAndGroupsSurviveSavingAndOldFilesStillLoad() throws {
        let step = ActionStep(
            actionId: "copy",
            guardIf: StepGuard(conditions: [WorkflowCondition(kind: .group, children: [airpods()], match: .any)], otherwise: .wait, waitSeconds: 15)
        )
        let decoded = try JSONDecoder().decode(ActionStep.self, from: JSONEncoder().encode(step))
        XCTAssertEqual(decoded, step)
        let old = #"{"id":"a","actionId":"paste","parameter":"","delayAfter":0.5,"enabled":true}"#.data(using: .utf8)!
        let loaded = try JSONDecoder().decode(ActionStep.self, from: old)
        XCTAssertNil(loaded.guardIf)
        XCTAssertEqual(loaded.actionId, "paste")
    }

    func testWorkflowReportsProblemsInStepGuards() {
        let bad = ActionStep(actionId: "copy", guardIf: StepGuard(conditions: [WorkflowCondition(kind: .frontApp)]))
        let workflow = Workflow(branches: [WorkflowBranch(conditions: [night()], steps: [bad])])
        XCTAssertTrue(workflow.problems.contains { $0.contains("Choose an app") })
    }
}
