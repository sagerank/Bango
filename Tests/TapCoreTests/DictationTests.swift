import XCTest
@testable import TapCore

final class DictationSessionTests: XCTestCase {
    func testSameGestureAlternatesBetweenStartAndStop() {
        var session = DictationSession()
        XCTAssertEqual(session.toggle(), .start)
        session.started()
        XCTAssertTrue(session.isListening)
        XCTAssertEqual(session.toggle(), .stop)
        session.finished()
        XCTAssertEqual(session.toggle(), .start)
    }

    func testTapsWhileBusyAreIgnoredNotQueued() {
        var session = DictationSession()
        XCTAssertEqual(session.toggle(), .start)
        XCTAssertEqual(session.toggle(), .ignore)       // still starting
        session.started()
        XCTAssertEqual(session.toggle(), .stop)
        XCTAssertEqual(session.toggle(), .ignore)       // still finishing
        session.finished()
        XCTAssertEqual(session.phase, .idle)
    }

    func testFailedStartReturnsToIdleSoTheNextTapTriesAgain() {
        var session = DictationSession()
        XCTAssertEqual(session.toggle(), .start)
        session.startFailed()
        XCTAssertEqual(session.toggle(), .start)
    }

    func testSafetyStopOnlyWhileListening() {
        var session = DictationSession()
        XCTAssertFalse(session.shouldAutoStop(listeningFor: 500))
        _ = session.toggle(); session.started()
        XCTAssertFalse(session.shouldAutoStop(listeningFor: 119))
        XCTAssertTrue(session.shouldAutoStop(listeningFor: DictationSession.maxSeconds))
    }

    func testLateStartedCallbackCannotResurrectAnIdleSession() {
        var session = DictationSession()
        session.started()
        XCTAssertEqual(session.phase, .idle)
    }
}

final class DictationTextTests: XCTestCase {
    func testCleanTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(DictationText.clean("  hello \n  world\t again  "), "hello world again")
        XCTAssertEqual(DictationText.clean("   \n "), "")
    }

    func testWordCount() {
        XCTAssertEqual(DictationText.wordCount("  one two   three "), 3)
        XCTAssertEqual(DictationText.wordCount(""), 0)
    }

    func testChunksNeverSplitACharacterAndKeepAllText() {
        let text = "Café déjà vu 👩‍👩‍👧‍👦 and 🎤 voice typing works"
        let pieces = DictationText.chunks(text, size: 8)
        XCTAssertEqual(pieces.joined(), text)
        // A family emoji is 11 UTF-16 units, longer than the limit, so it travels alone rather than being cut.
        XCTAssertTrue(pieces.contains("👩‍👩‍👧‍👦") || pieces.contains(where: { $0.contains("👩‍👩‍👧‍👦") }))
        for piece in pieces where piece.count > 1 { XCTAssertLessThanOrEqual(piece.utf16.count, 12) }
    }

    func testChunkSizeIsRespectedForPlainText() {
        let pieces = DictationText.chunks(String(repeating: "a", count: 45), size: 20)
        XCTAssertEqual(pieces.map { $0.count }, [20, 20, 5])
        XCTAssertEqual(DictationText.chunks("", size: 20), [])
    }

    func testTailShowsTheLastWordsWithAnEllipsis() {
        let long = (1...40).map { "word\($0)" }.joined(separator: " ")
        let tail = DictationText.tail(long, maxCharacters: 40)
        XCTAssertTrue(tail.hasPrefix("…"))
        XCTAssertTrue(tail.hasSuffix("word40"))
        XCTAssertLessThanOrEqual(tail.count, 41)
        XCTAssertEqual(DictationText.tail("short text", maxCharacters: 40), "short text")
    }
}

final class DictationPlanTests: XCTestCase {
    func testDictationNeedsMicrophoneSpeechAndAccessibility() {
        XCTAssertEqual(PermissionPlan.items(forAction: "dictation-toggle"), [.microphone, .speechRecognition, .accessibility])
    }

    func testDictationIsTheFirstActionInItsOwnGroup() {
        XCTAssertEqual(ActionCategory.allCases.first, .voice)
        XCTAssertEqual(ActionCatalog.actions(in: .voice).map { $0.id }, ["dictation-toggle"])
        XCTAssertEqual(ActionCatalog.definition(for: "dictation-toggle")?.danger, .safe)
    }

    func testVoiceStarterProfileMakesDoubleTapTheToggle() throws {
        let voice = try XCTUnwrap(DefaultProfiles.make().first { $0.name == DefaultProfiles.voiceName })
        XCTAssertEqual(voice.bindings.map { $0.taps }, [2])
        XCTAssertEqual(voice.bindings.first?.steps.first?.actionId, "dictation-toggle")
    }

    func testExistingSetupsCanAddTheVoiceProfileWithoutTouchingTheRest() {
        var config = AppConfig()
        config.profiles.removeAll { $0.name == DefaultProfiles.voiceName }
        let before = config.profiles.map { $0.name }
        XCTAssertEqual(config.addMissingStarterProfiles(), [DefaultProfiles.voiceName])
        XCTAssertEqual(config.profiles.map { $0.name }.prefix(before.count), before[...])
    }

    func testFeedbackFollowsTheResultSentence() {
        XCTAssertEqual(FeedbackKind.classify(actionId: "dictation-toggle", parameter: "", summary: "Listening… double tap again to finish"), .dictation(listening: true))
        XCTAssertEqual(FeedbackKind.classify(actionId: "dictation-toggle", parameter: "", summary: "Pasted 12 words"), .dictation(listening: false))
    }
}
