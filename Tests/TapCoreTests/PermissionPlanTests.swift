import XCTest
@testable import TapCore

final class PermissionPlanTests: XCTestCase {
    func testKeyPressActionsNeedAccessibility() {
        for id in ["copy", "paste", "play-pause", "volume-up", "lock-screen", "screenshot-area"] {
            XCTAssertEqual(PermissionPlan.items(forAction: id), [.accessibility], id)
        }
    }

    func testMicrophoneMuteNeedsNoPermission() {
        // It only changes the input volume. Nothing is recorded.
        XCTAssertEqual(PermissionPlan.items(forAction: "mic-mute"), [])
    }

    func testEjectNeedsFinderAndDarkModeNeedsSystemEvents() {
        XCTAssertEqual(PermissionPlan.items(forAction: "eject-all"), [.finder])
        XCTAssertEqual(PermissionPlan.items(forAction: "dark-mode"), [.systemEvents])
    }

    func testScreenshotToFileNeedsTheFolderButClipboardDoesNot() {
        XCTAssertEqual(PermissionPlan.items(forAction: "capture-full-save"), [.screenRecording, .screenshotFolder])
        XCTAssertEqual(PermissionPlan.items(forAction: "capture-area-clipboard"), [.screenRecording])
    }

    func testMarkupAlsoNeedsAccessibility() {
        let items = PermissionPlan.items(forAction: "capture-area-edit")
        XCTAssertTrue(items.contains(.accessibility))
        XCTAssertTrue(items.contains(.screenRecording))
        XCTAssertTrue(items.contains(.screenshotFolder))
    }

    func testUnknownActionNeedsNothing() {
        XCTAssertEqual(PermissionPlan.items(forAction: "does-not-exist"), [])
    }

    func testStarterProfilesTogetherNeedTheWholeSetup() {
        let usage = PermissionPlan.usage(in: AppConfig())
        XCTAssertNotNil(usage[.accessibility])
        XCTAssertNotNil(usage[.screenRecording])
        XCTAssertNotNil(usage[.screenshotFolder])
        XCTAssertEqual(usage[.accessibility]?.contains("Copy"), true)
        XCTAssertEqual(usage[.systemEvents] ?? [], [])
    }

    func testDisabledStepsDoNotCount() {
        var config = AppConfig()
        config.profiles = [Profile(name: "x", bindings: [
            GestureBinding(key: GestureKey(taps: 1), steps: [ActionStep(actionId: "eject-all", enabled: false)]),
        ])]
        config.activeProfileID = config.profiles[0].id
        XCTAssertNil(PermissionPlan.usage(in: config)[.finder])
    }

    func testAskingOrderListsEveryItemOnceWithSettingsTripsLast() {
        XCTAssertEqual(Set(PermissionPlan.order), Set(SetupItem.allCases))
        XCTAssertEqual(PermissionPlan.order.count, SetupItem.allCases.count)
        let order = PermissionPlan.order
        XCTAssertLessThan(order.firstIndex(of: .finder)!, order.firstIndex(of: .accessibility)!)
        XCTAssertLessThan(order.firstIndex(of: .screenshotFolder)!, order.firstIndex(of: .screenRecording)!)
    }
}

final class SetupPolicyTests: XCTestCase {
    private func show(done: Bool = true, last: String? = nil, build: String = "9-0.9.3", ax: Bool = true, screen: Bool = true) -> Bool {
        SetupPolicy.shouldShowSetup(
            onboardingDone: done, lastSetupBuild: last, currentBuild: build,
            accessibilityGranted: ax, screenRecordingGranted: screen
        )
    }

    func testFirstRunAlwaysShowsSetup() {
        XCTAssertTrue(show(done: false, ax: true, screen: true))
    }

    func testReinstallWithOldSettingsShowsSetupWhenPermissionsAreGone() {
        // The settings file survives an uninstall, the macOS permissions do not.
        XCTAssertTrue(show(done: true, last: nil, ax: false, screen: false))
    }

    func testNewBuildAskedAgainOnlyIfSomethingIsMissing() {
        XCTAssertTrue(show(last: "8-0.9.2", ax: false))
        XCTAssertTrue(show(last: "8-0.9.2", screen: false))
        XCTAssertFalse(show(last: "8-0.9.2"))
    }

    func testStaysQuietOnceThisBuildWasSetUp() {
        XCTAssertFalse(show(last: "9-0.9.3", ax: false, screen: false))
    }
}
