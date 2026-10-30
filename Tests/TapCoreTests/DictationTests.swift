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
    /// Plays partials and the final text against a pretend text box and returns what ended up in it.
    private func run(_ partials: [String], final: String, settleAfter: Set<Int> = []) -> (edits: [LiveTypist.Edit], field: String, typist: LiveTypist) {
        var typist = LiveTypist()
        var edits: [LiveTypist.Edit] = []
        var field = ""
        func apply(_ e: LiveTypist.Edit) {
            field.removeLast(min(e.backspaces, field.count))
            field += e.insert
            if !e.isEmpty { edits.append(e) }
        }
        for (index, p) in partials.enumerated() {
            apply(typist.update(partial: p))
            if settleAfter.contains(index) { apply(typist.settle()) }
        }
        apply(typist.finish(final: final))
        return (edits, field, typist)
    }

    func testWordsAppearOnlyOnceTheyAreStable() {
        var typist = LiveTypist()
        XCTAssertTrue(typist.update(partial: "hello").isEmpty)
        XCTAssertTrue(typist.update(partial: "hello wor").isEmpty)
        XCTAssertEqual(typist.update(partial: "hello world").insert, "hello ")
        XCTAssertTrue(typist.update(partial: "hello world how").isEmpty)
        XCTAssertEqual(typist.update(partial: "hello world how are").insert, "world ")
    }

    func testAPauseTypesTheLastWordWithoutWaitingForTheNextOne() {
        var typist = LiveTypist()
        _ = typist.update(partial: "send the report")
        XCTAssertEqual(typist.update(partial: "send the report").insert, "send the ")
        XCTAssertEqual(typist.settle().insert, "report")           // paused: no trailing space invented
        XCTAssertTrue(typist.settle().isEmpty)                      // nothing new
        XCTAssertTrue(typist.update(partial: "send the report today now").isEmpty)        // "today" is not confirmed yet
        XCTAssertEqual(typist.update(partial: "send the report today now soon").insert, " today ")
    }

    func testListeningNeverDeletesAnything() {
        let r = run(["the cat", "the cat sat", "the cap sat on", "the cap sat on a"], final: "the cap sat on a mat", settleAfter: [1, 3])
        for edit in r.edits.dropLast() { XCTAssertEqual(edit.backspaces, 0) }
        XCTAssertEqual(r.field, "the cap sat on a mat")
    }

    func testTheFieldAlwaysEndsExactlyEqualToTheFinalText() {
        let finals = ["hello world", "one two three four five", "it's 5 o'clock, café ☕ time", "Hello world. How are you doing today, my friend? I hope all is well."]
        for final in finals {
            let words = final.split(separator: " ").map(String.init)
            let partials = (1...words.count).map { words.prefix($0).joined(separator: " ").lowercased() }
            XCTAssertEqual(run(partials, final: final).field, final, final)
            XCTAssertEqual(run(partials, final: final, settleAfter: Set(0..<partials.count)).field, final, final)
        }
    }

    func testPunctuationAndCapitalsAddedLaterAreFixedAtTheEnd() {
        // The bug that was reported: the draft had no punctuation, the final had, and the text came out scrambled.
        let partials = ["hello", "hello world", "hello world how are", "hello world how are you doing", "hello world how are you doing today my", "hello world how are you doing today my friend i hope"]
        let final = "Hello world. How are you doing today, my friend? I hope all is well."
        let r = run(partials, final: final)
        XCTAssertEqual(r.field, final)
        XCTAssertFalse(r.typist.diverged)
    }

    func testAMistakeInTheMiddleIsCorrectedFromThereOnly() {
        let r = run(["send it to bob", "send it to bob now please"], final: "send it to rob now please")
        XCTAssertEqual(r.field, "send it to rob now please")
        // Only the words from the mistake onwards are deleted, never the start of the sentence.
        XCTAssertLessThanOrEqual(r.edits.last?.backspaces ?? 0, "bob now ".count)
    }

    func testOnlyTextTypedHereIsEverDeleted() {
        let r = run(["alpha beta gamma delta"], final: "Alpha, beta gamma delta.", settleAfter: [0])
        let deleted = r.edits.map { $0.backspaces }.reduce(0, +)
        XCTAssertLessThanOrEqual(deleted, r.typist.typed.count + "alpha beta gamma delta".count)
        XCTAssertEqual(r.field, "Alpha, beta gamma delta.")
    }

    func testAnAbsurdlyLargeDisagreementIsNotWipedAndIsReported() {
        var typist = LiveTypist()
        let long = (1...140).map { "word\($0)" }.joined(separator: " ")
        _ = typist.update(partial: long)
        _ = typist.update(partial: long + " tail")
        XCTAssertGreaterThan(typist.typed.count, LiveTypist.maxCorrection)
        let edit = typist.finish(final: "Totally different. " + long)
        XCTAssertTrue(edit.isEmpty)
        XCTAssertTrue(typist.diverged)
    }

    func testNothingHeardTypesNothing() {
        var typist = LiveTypist()
        XCTAssertTrue(typist.update(partial: "").isEmpty)
        XCTAssertTrue(typist.settle().isEmpty)
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


final class TranscriptStitcherTests: XCTestCase {
    func testKeepsEarlierSentencesWhenTheRecogniserStartsOver() {
        var stitcher = TranscriptStitcher()
        stitcher.update("Hello there")
        stitcher.update("Hello there my friend.")
        stitcher.update("How")
        stitcher.update("How are you")
        XCTAssertEqual(stitcher.full, "Hello there my friend. How are you")
    }

    func testCorrectionsToTheLastWordsDoNotDuplicateText() {
        var stitcher = TranscriptStitcher()
        stitcher.update("I want to go their")
        stitcher.update("I want to go there")
        XCTAssertEqual(stitcher.full, "I want to go there")
    }

    func testNewStretchThatSharesTheFirstWordIsStillDetectedFromTheTimestamp() {
        var stitcher = TranscriptStitcher()
        stitcher.update("Babu Priya", start: 0.2)
        stitcher.update("Babu", start: 6.0)
        XCTAssertEqual(stitcher.full, "Babu Priya Babu")
    }

    func testCommitMakesTheNextReportANewStretch() {
        var stitcher = TranscriptStitcher()
        stitcher.update("First sentence.")
        stitcher.commit()
        stitcher.update("Second sentence.")
        XCTAssertEqual(stitcher.full, "First sentence. Second sentence.")
    }

    func testTypistKeepsTypingAfterAPause() {
        var stitcher = TranscriptStitcher()
        var typist = LiveTypist()
        stitcher.update("one two three")
        _ = typist.update(partial: stitcher.full)
        stitcher.update("one two three four")
        _ = typist.update(partial: stitcher.full)
        stitcher.update("five six")
        _ = typist.update(partial: stitcher.full)
        stitcher.update("five six seven")
        let edit = typist.update(partial: stitcher.full)
        XCTAssertFalse(edit.isEmpty)
        XCTAssertTrue(typist.typed.hasPrefix("one two three four five"))
    }
}
