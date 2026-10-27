import XCTest
@testable import TapCore

final class WindowPresetTests: XCTestCase {
    // A 1440 x 900 screen with a 25 point menu bar on top and a Dock taking 70 at the bottom.
    private let visible = LayoutRect(x: 0, y: 25, width: 1440, height: 805)

    func testHalvesFillTheirSideExactly() {
        let left = WindowPreset.leftHalf.rect(in: visible)
        let right = WindowPreset.rightHalf.rect(in: visible)
        XCTAssertEqual(left, LayoutRect(x: 0, y: 25, width: 720, height: 805))
        XCTAssertEqual(right, LayoutRect(x: 720, y: 25, width: 720, height: 805))
        XCTAssertEqual(left.maxX, right.x)
        let top = WindowPreset.topHalf.rect(in: visible)
        let bottom = WindowPreset.bottomHalf.rect(in: visible)
        XCTAssertEqual(top.maxY, bottom.y, accuracy: 1)
        XCTAssertEqual(bottom.maxY, visible.maxY)
    }

    func testOddWidthsNeverOverlapOrLeaveTheScreen() {
        let odd = LayoutRect(x: 10, y: 0, width: 1001, height: 600)
        let l = WindowPreset.leftHalf.rect(in: odd), r = WindowPreset.rightHalf.rect(in: odd)
        XCTAssertLessThanOrEqual(l.maxX, r.x)
        XCTAssertEqual(r.maxX, odd.maxX)
        for third in [WindowPreset.leftThird, .middleThird, .rightThird] {
            let t = third.rect(in: odd)
            XCTAssertGreaterThanOrEqual(t.x, odd.x)
            XCTAssertLessThanOrEqual(t.maxX, odd.maxX)
        }
    }

    func testMaximizeAndCenter() {
        XCTAssertEqual(WindowPreset.maximize.rect(in: visible), visible)
        let c = WindowPreset.center.rect(in: visible)
        XCTAssertEqual(c.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(c.midY, visible.midY, accuracy: 1)
        XCTAssertLessThan(c.width, visible.width)
    }

    func testPeopleCanTypeNaturalNames() {
        XCTAssertEqual(WindowPreset.parse("Left"), .leftHalf)
        XCTAssertEqual(WindowPreset.parse("  the right half "), .rightHalf)
        XCTAssertEqual(WindowPreset.parse("Full Screen"), .maximize)
        XCTAssertEqual(WindowPreset.parse("top-half"), .topHalf)
        XCTAssertEqual(WindowPreset.parse("centre"), .center)
        XCTAssertNil(WindowPreset.parse("somewhere nice"))
        for preset in WindowPreset.allCases { XCTAssertEqual(WindowPreset.parse(preset.rawValue), preset) }
    }
}

final class LayoutMathTests: XCTestCase {
    private let screen = LayoutRect(x: 0, y: 25, width: 1440, height: 805)

    func testSaveThenApplyOnTheSameScreenGivesTheSameWindow() {
        let window = LayoutRect(x: 100, y: 125, width: 700, height: 500)
        let f = LayoutMath.fractions(of: window, in: screen)
        XCTAssertEqual(LayoutMath.frame(fractions: f, in: screen), window)
    }

    func testALayoutSurvivesADifferentScreenSize() {
        let window = LayoutRect(x: 0, y: 25, width: 720, height: 805)           // left half
        let f = LayoutMath.fractions(of: window, in: screen)
        let bigger = LayoutRect(x: 0, y: 30, width: 2560, height: 1370)
        let placed = LayoutMath.frame(fractions: f, in: bigger)
        XCTAssertEqual(placed.width, 1280)
        XCTAssertEqual(placed.x, 0)
        XCTAssertEqual(placed.height, 1370)
    }

    func testAWindowHangingOffTheScreenIsClampedWhenSaved() {
        let f = LayoutMath.fractions(of: LayoutRect(x: 1300, y: 25, width: 600, height: 805), in: screen)
        XCTAssertLessThanOrEqual(f.x + f.width, 1.0001)
        XCTAssertGreaterThanOrEqual(f.x, 0)
    }

    func testAppliedFramesStayOnScreenAndKeepAUsableSize() {
        let tiny = LayoutMath.frame(fractions: LayoutRect(x: 0.99, y: 0.99, width: 0.01, height: 0.01), in: screen)
        XCTAssertGreaterThanOrEqual(tiny.width, 120)
        XCTAssertGreaterThanOrEqual(tiny.height, 120)
        XCTAssertLessThanOrEqual(tiny.maxX, screen.maxX)
        XCTAssertLessThanOrEqual(tiny.maxY, screen.maxY)
    }

    func testAnEmptyScreenDoesNotCrash() {
        let f = LayoutMath.fractions(of: LayoutRect(x: 1, y: 1, width: 5, height: 5), in: LayoutRect(x: 0, y: 0, width: 0, height: 0))
        XCTAssertEqual(f, LayoutRect(x: 0, y: 0, width: 1, height: 1))
    }
}

final class DeskParsingTests: XCTestCase {
    func testItemListSplitsTrimsAndDropsRepeats() {
        XCTAssertEqual(ItemList.parse(" Mail, Calendar ;Safari\n mail \n\n,"), ["Mail", "Calendar", "Safari"])
        XCTAssertEqual(ItemList.parse(""), [])
    }

    func testOpenItemsAcceptOnlyWebMailAndAbsolutePaths() {
        XCTAssertEqual(OpenItem.classify("https://example.com/a?b=1"), .link(URL(string: "https://example.com/a?b=1")!))
        XCTAssertEqual(OpenItem.classify("mailto:me@example.com"), .link(URL(string: "mailto:me@example.com")!))
        XCTAssertEqual(OpenItem.classify("/Users/me/Documents"), .path("/Users/me/Documents"))
        if case .path(let expanded) = OpenItem.classify("~/Desktop") {
            XCTAssertTrue(expanded.hasSuffix("/Desktop") && !expanded.hasPrefix("~"))
        } else { XCTFail("expected a path") }
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "ssh://host", "ftp://x.y", "https://", "notes.txt", ""] {
            XCTAssertEqual(OpenItem.classify(bad), .invalid(bad), bad)
        }
    }

    func testLayoutsAreFoundByNameOrFirstWhenEmpty() {
        let a = DeskLayout(name: "Desk"), b = DeskLayout(name: "Meeting")
        XCTAssertEqual(DeskLayout.find("meeting", in: [a, b])?.name, "Meeting")
        XCTAssertEqual(DeskLayout.find("", in: [a, b])?.name, "Desk")
        XCTAssertNil(DeskLayout.find("Nope", in: [a, b]))
        XCTAssertNil(DeskLayout.find("", in: []))
    }

    func testDeskActionsAreInTheCatalogWithTheRightRules() {
        for id in ["open-apps", "open-items", "arrange-window", "apply-layout"] {
            XCTAssertNotNil(ActionCatalog.definition(for: id), id)
        }
        XCTAssertTrue(ActionCatalog.definition(for: "open-items")!.runsCode)
        XCTAssertFalse(ActionCatalog.definition(for: "open-apps")!.runsCode)
        XCTAssertEqual(PermissionPlan.items(forAction: "arrange-window"), [.accessibility])
        XCTAssertEqual(PermissionPlan.items(forAction: "apply-layout"), [.accessibility])
        XCTAssertEqual(ActionCatalog.definition(for: "arrange-window")?.parameter?.choices, WindowPreset.choices)
    }

    func testLayoutsSurviveSavingAndOldSettingsLoadWithoutThem() throws {
        var config = AppConfig()
        config.layouts = [DeskLayout(name: "Desk", entries: [
            LayoutEntry(bundleID: "com.apple.mail", appName: "Mail", display: 1, fractions: LayoutRect(x: 0, y: 0, width: 0.5, height: 1)),
        ])]
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: data).layouts, config.layouts)
        let old = try JSONDecoder().decode(AppConfig.self, from: Data("{\"hasCompletedOnboarding\": true}".utf8))
        XCTAssertEqual(old.layouts, [])
    }

    func testImportedProfilesCannotOpenFilesOrLinksUntilEnabledByHand() throws {
        let profile = Profile(name: "shared", bindings: [
            GestureBinding(key: GestureKey(taps: 2), steps: [ActionStep(actionId: "open-items", parameter: "https://example.com")]),
        ])
        let result = try ProfileExchange.importProfile(from: try ProfileExchange.export(profile))
        XCTAssertEqual(result.profile.bindings.first?.steps.first?.enabled, false)
        XCTAssertEqual(result.disabledSteps, 1)
    }
}
