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

final class LiveTypistTests: XCTestCase {
    private func run(_ partials: [String], final: String) -> (edits: [LiveTypist.Edit], typed: String) {
        var typist = LiveTypist()
        var edits: [LiveTypist.Edit] = []
        var field = ""
        func apply(_ e: LiveTypist.Edit) {
            field.removeLast(min(e.backspaces, field.count))
            field += e.insert
            if !e.isEmpty { edits.append(e) }
        }
        for p in partials { apply(typist.update(partial: p)) }
        apply(typist.finish(final: final))
        return (edits, field)
    }

    func testWordsAppearOnlyOnceTheyAreStable() {
        var typist = LiveTypist()
        XCTAssertTrue(typist.update(partial: "hello").isEmpty)                  // first sight of anything
        XCTAssertTrue(typist.update(partial: "hello wor").isEmpty)              // "hello" has no space after it yet
        XCTAssertEqual(typist.update(partial: "hello world").insert, "hello ")  // "hello" stayed, "world" is still being said
        XCTAssertTrue(typist.update(partial: "hello world how").isEmpty)        // "world" has no space after it yet either
        XCTAssertEqual(typist.update(partial: "hello world how are").insert, "world ")
    }

    func testListeningNeverDeletesAnything() {
        // The recogniser changes its mind about the last word: nothing already typed is touched.
        let r = run(["the cat", "the cat sat", "the cap sat on", "the cap sat on a"], final: "the cap sat on a mat")
        for edit in r.edits.dropLast() { XCTAssertEqual(edit.backspaces, 0) }
        XCTAssertEqual(r.typed, "the cap sat on a mat")
    }

    func testFieldAlwaysEndsEqualToTheFinalText() {
        let finals = ["hello world", "one two three four five", "it's 5 o'clock, café ☕ time"]
        for final in finals {
            let words = final.split(separator: " ").map(String.init)
            let partials = (1...words.count).map { words.prefix($0).joined(separator: " ") }
            XCTAssertEqual(run(partials, final: final).typed, final, final)
        }
    }

    func testAnEarlierMistakeIsCorrectedByAFewBackspacesAtTheEnd() {
        let r = run(["we went to the", "we went to the pier today"], final: "we went to the pier today")
        XCTAssertEqual(r.typed, "we went to the pier today")
        let withMistake = run(["send it to bob", "send it to bob now"], final: "send it to rob now")
        XCTAssertEqual(withMistake.typed, "send it to rob now")
        XCTAssertLessThanOrEqual(withMistake.edits.map { $0.backspaces }.max() ?? 0, LiveTypist.maxCorrection)
    }

    func testAHugeDisagreementDoesNotDeleteLongStretchesOfText() {
        var typist = LiveTypist()
        let long = (1...30).map { "word\($0)" }.joined(separator: " ")
        _ = typist.update(partial: long)
        _ = typist.update(partial: long + " extra")
        let edit = typist.finish(final: "completely different sentence now " + long)
        XCTAssertEqual(edit.backspaces, 0)
    }

    func testNothingHeardTypesNothing() {
        var typist = LiveTypist()
        XCTAssertTrue(typist.update(partial: "").isEmpty)
        XCTAssertTrue(typist.finish(final: "   ").isEmpty)
        XCTAssertEqual(typist.typed, "")
    }

    func testRepeatedIdenticalPartialsAddNothingNew() {
        var typist = LiveTypist()
        _ = typist.update(partial: "good morning everyone")
        XCTAssertEqual(typist.update(partial: "good morning everyone").insert, "good morning ")
        XCTAssertTrue(typist.update(partial: "good morning everyone").isEmpty)
    }
}
