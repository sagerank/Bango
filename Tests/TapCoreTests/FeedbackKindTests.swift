import XCTest
@testable import TapCore

final class FeedbackKindTests: XCTestCase {
    func testCapturesGetTheShutter() {
        XCTAssertEqual(FeedbackKind.classify(actionId: "capture-full-save", parameter: "", summary: "Saved x.png"), .screenshot(toClipboard: false))
        XCTAssertEqual(FeedbackKind.classify(actionId: "capture-area-clipboard", parameter: "", summary: "Screenshot copied"), .screenshot(toClipboard: true))
        XCTAssertEqual(FeedbackKind.classify(actionId: "capture-area-edit", parameter: "", summary: "Marking up x.png"), .screenshot(toClipboard: false))
    }

    func testCancelledCaptureHasNoShutter() {
        XCTAssertEqual(FeedbackKind.classify(actionId: "capture-area-save", parameter: "", summary: "Screenshot cancelled"), .generic)
    }

    func testMacShortcutScreenshotsKeepTheirOwnInterface() {
        XCTAssertEqual(FeedbackKind.classify(actionId: "screenshot-area", parameter: "", summary: "Screenshot of an area"), .generic)
    }

    func testMicrophoneStateFollowsTheResult() {
        XCTAssertEqual(FeedbackKind.classify(actionId: "mic-mute", parameter: "", summary: "Microphone muted"), .microphone(muted: true))
        XCTAssertEqual(FeedbackKind.classify(actionId: "mic-mute", parameter: "", summary: "Microphone on"), .microphone(muted: false))
    }

    func testOpeningAnAppCarriesItsName() {
        XCTAssertEqual(FeedbackKind.classify(actionId: "launch-app", parameter: " Superwhisper ", summary: "Opened Superwhisper"), .app(name: "Superwhisper"))
        XCTAssertEqual(FeedbackKind.classify(actionId: "launch-app", parameter: "  ", summary: ""), .generic)
    }

    func testEverythingElseIsGeneric() {
        XCTAssertEqual(FeedbackKind.classify(actionId: "copy", parameter: "", summary: "Copy"), .generic)
    }
}
