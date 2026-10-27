import XCTest
@testable import TapCore

final class ProfileTests: XCTestCase {
    func testDefaultProfilesUseOnlyKnownActions() {
        for profile in DefaultProfiles.make() {
            for binding in profile.bindings {
                for step in binding.steps {
                    XCTAssertNotNil(ActionCatalog.definition(for: step.actionId), "\(profile.name): \(step.actionId)")
                }
            }
        }
    }

    func testDefaultProfilesNeedNoSafetyConfirmation() {
        for profile in DefaultProfiles.make() {
            for binding in profile.bindings {
                XCTAssertTrue(SafetyPolicy.isAllowed(binding), "\(profile.name) \(binding.taps) taps")
            }
        }
    }

    func testScreenshotsProfileMapsEveryTapCount() throws {
        let profile = try XCTUnwrap(DefaultProfiles.make().first { $0.name == DefaultProfiles.screenshotsName })
        XCTAssertEqual(profile.bindings.map { $0.taps }, [1, 2, 3, 4, 5])
        let triple = try XCTUnwrap(profile.bindings.first { $0.taps == 3 })
        XCTAssertEqual(triple.steps.first?.actionId, "capture-full-save")
    }

    func testMissingStarterProfilesAreAddedOnceByName() {
        var config = AppConfig()
        config.profiles.removeAll { $0.name == DefaultProfiles.screenshotsName }
        XCTAssertEqual(config.addMissingStarterProfiles(), [DefaultProfiles.screenshotsName])
        XCTAssertEqual(config.addMissingStarterProfiles(), [])
        XCTAssertEqual(config.profiles.filter { $0.name == DefaultProfiles.screenshotsName }.count, 1)
    }

    func testCaptureActionsNeedScreenRecording() {
        let capture = ActionCatalog.actions(in: .capture).filter { $0.id.hasPrefix("capture-") }
        XCTAssertEqual(capture.count, 7)
        for action in capture { XCTAssertEqual(action.permission, .screenRecording, action.id) }
    }

    func testCatalogIDsAreUnique() {
        let ids = ActionCatalog.all.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testCodeRunningActionsAreFlagged() {
        XCTAssertEqual(ActionCatalog.definition(for: "shell-command")?.runsCode, true)
        XCTAssertEqual(ActionCatalog.definition(for: "open-url")?.runsCode, true)
        XCTAssertEqual(ActionCatalog.definition(for: "copy")?.runsCode, false)
    }

    func testAppOverrideWinsOverTheProfile() {
        let general = GestureBinding(key: GestureKey(taps: 2), steps: [ActionStep(actionId: "copy")])
        let special = GestureBinding(key: GestureKey(taps: 2), steps: [ActionStep(actionId: "undo")])
        let profile = Profile(
            name: "Test",
            bindings: [general],
            appOverrides: [AppOverride(id: "com.apple.Safari", appName: "Safari", bindings: [special])]
        )
        let gesture = RecognizedGesture(taps: 2)
        XCTAssertEqual(profile.resolve(gesture, frontmostBundleID: "com.apple.Safari")?.id, special.id)
        XCTAssertEqual(profile.resolve(gesture, frontmostBundleID: "com.apple.Notes")?.id, general.id)
        XCTAssertEqual(profile.resolve(gesture, frontmostBundleID: nil)?.id, general.id)
    }

    func testOverrideWithoutAMatchFallsBackToTheProfile() {
        let general = GestureBinding(key: GestureKey(taps: 3), steps: [ActionStep(actionId: "paste")])
        let other = GestureBinding(key: GestureKey(taps: 2), steps: [ActionStep(actionId: "undo")])
        let profile = Profile(
            name: "Test",
            bindings: [general],
            appOverrides: [AppOverride(id: "com.apple.Safari", appName: "Safari", bindings: [other])]
        )
        XCTAssertEqual(
            profile.resolve(RecognizedGesture(taps: 3), frontmostBundleID: "com.apple.Safari")?.id,
            general.id
        )
    }

    func testStrengthAndZoneSpecificityOrder() {
        let anyBinding = GestureBinding(key: GestureKey(taps: 1), steps: [ActionStep(actionId: "copy")])
        let hard = GestureBinding(key: GestureKey(taps: 1, strength: .hard), steps: [ActionStep(actionId: "paste")])
        let leftHard = GestureBinding(key: GestureKey(taps: 1, zone: .left, strength: .hard), steps: [ActionStep(actionId: "cut")])
        let gesture = RecognizedGesture(taps: 1, zone: .left, strength: .hard)
        XCTAssertEqual(GestureBinding.best(in: [anyBinding, hard, leftHard], for: gesture)?.id, leftHard.id)
        let soft = RecognizedGesture(taps: 1, zone: .left, strength: .soft)
        XCTAssertEqual(GestureBinding.best(in: [anyBinding, hard, leftHard], for: soft)?.id, anyBinding.id)
    }

    func testRhythmsAreCollectedFromBindingsAndOverrides() {
        let a = RhythmPattern(gaps: [0.2, 0.7])
        let b = RhythmPattern(gaps: [0.5])
        let profile = Profile(
            name: "Test",
            bindings: [GestureBinding(key: GestureKey(taps: 3), rhythm: a, steps: [])],
            appOverrides: [AppOverride(id: "x", appName: "X", bindings: [GestureBinding(key: GestureKey(taps: 2), rhythm: b, steps: [])])]
        )
        XCTAssertEqual(Set(profile.rhythms), Set([a, b]))
    }
}

final class ProfileEditingTests: XCTestCase {
    func testDuplicateKeepsContentButChangesEveryID() {
        let original = Profile(name: "Mine", bindings: [
            GestureBinding(key: GestureKey(taps: 2), steps: [ActionStep(actionId: "shell-command", parameter: "ls")]),
        ], appOverrides: [
            AppOverride(id: "com.apple.Safari", appName: "Safari", bindings: [
                GestureBinding(key: GestureKey(taps: 1), steps: [ActionStep(actionId: "copy")]),
            ]),
        ])
        let copy = original.duplicated()
        XCTAssertEqual(copy.name, "Mine copy")
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertNotEqual(copy.bindings[0].id, original.bindings[0].id)
        XCTAssertNotEqual(copy.bindings[0].steps[0].id, original.bindings[0].steps[0].id)
        XCTAssertNotEqual(copy.appOverrides[0].bindings[0].id, original.appOverrides[0].bindings[0].id)
        // Unlike an import, a duplicate keeps code steps enabled: the user wrote them.
        XCTAssertTrue(copy.bindings[0].steps[0].enabled)
        XCTAssertEqual(copy.bindings[0].steps[0].parameter, "ls")
    }

    func testUpdateActiveProfileChangesOnlyTheActiveOne() {
        var config = AppConfig()
        let others = config.profiles.dropFirst().map { $0.name }
        config.updateActiveProfile { $0.name = "Renamed" }
        XCTAssertEqual(config.activeProfile.name, "Renamed")
        XCTAssertEqual(config.profiles.dropFirst().map { $0.name }, others)
    }
}

final class SafetyTests: XCTestCase {
    private func binding(taps: Int, action: String, acknowledged: Bool = false) -> GestureBinding {
        GestureBinding(
            key: GestureKey(taps: taps),
            steps: [ActionStep(actionId: action)],
            acknowledgedRisk: acknowledged
        )
    }

    func testRiskyActionNeedsFourTaps() {
        XCTAssertTrue(SafetyPolicy.needsAcknowledgement(binding(taps: 2, action: "lock-screen")))
        XCTAssertFalse(SafetyPolicy.needsAcknowledgement(binding(taps: 4, action: "lock-screen")))
    }

    func testAcknowledgementAllowsRiskyAction() {
        XCTAssertFalse(SafetyPolicy.isAllowed(binding(taps: 1, action: "wifi-toggle")))
        XCTAssertTrue(SafetyPolicy.isAllowed(binding(taps: 1, action: "wifi-toggle", acknowledged: true)))
    }

    func testSafeActionNeverNeedsAcknowledgement() {
        XCTAssertTrue(SafetyPolicy.isAllowed(binding(taps: 1, action: "play-pause")))
    }

    func testDisabledRiskyStepIsIgnored() {
        var b = binding(taps: 1, action: "shell-command")
        b.steps[0].enabled = false
        XCTAssertEqual(SafetyPolicy.danger(of: b), .safe)
    }

    func testUnknownActionIsTreatedAsCautious() {
        XCTAssertEqual(SafetyPolicy.danger(of: binding(taps: 1, action: "does-not-exist")), .caution)
    }

    func testChainTakesTheWorstStep() {
        var b = binding(taps: 4, action: "play-pause")
        b.steps.append(ActionStep(actionId: "eject-all"))
        XCTAssertEqual(SafetyPolicy.danger(of: b), .destructive)
    }
}

final class ExchangeTests: XCTestCase {
    func testExportThenImportKeepsSafeActions() throws {
        let profile = Profile(name: "Mine", bindings: [
            GestureBinding(key: GestureKey(taps: 2), steps: [ActionStep(actionId: "copy")]),
        ])
        let data = try ProfileExchange.export(profile)
        let result = try ProfileExchange.importProfile(from: data)
        XCTAssertEqual(result.profile.name, "Mine")
        XCTAssertEqual(result.disabledSteps, 0)
        XCTAssertEqual(result.profile.bindings.first?.steps.first?.enabled, true)
        XCTAssertNotEqual(result.profile.id, profile.id)
    }

    func testImportDisablesShellAndLinkSteps() throws {
        let profile = Profile(name: "Shared", bindings: [
            GestureBinding(key: GestureKey(taps: 4), steps: [
                ActionStep(actionId: "shell-command", parameter: "echo hi"),
                ActionStep(actionId: "open-url", parameter: "https://example.com"),
                ActionStep(actionId: "play-pause"),
            ], acknowledgedRisk: true),
        ])
        let result = try ProfileExchange.importProfile(from: try ProfileExchange.export(profile))
        let steps = result.profile.bindings[0].steps
        XCTAssertEqual(result.disabledSteps, 2)
        XCTAssertFalse(steps[0].enabled)
        XCTAssertFalse(steps[1].enabled)
        XCTAssertTrue(steps[2].enabled)
        XCTAssertFalse(result.profile.bindings[0].acknowledgedRisk)
    }

    func testImportDisablesUnknownActions() throws {
        let profile = Profile(name: "Odd", bindings: [
            GestureBinding(key: GestureKey(taps: 1), steps: [ActionStep(actionId: "made-up")]),
        ])
        let result = try ProfileExchange.importProfile(from: try ProfileExchange.export(profile))
        XCTAssertEqual(result.disabledSteps, 1)
    }

    func testImportRefreshesAllIdentifiers() throws {
        let profile = Profile(name: "Ids", bindings: [
            GestureBinding(key: GestureKey(taps: 1), steps: [ActionStep(actionId: "copy")]),
        ])
        let result = try ProfileExchange.importProfile(from: try ProfileExchange.export(profile))
        XCTAssertNotEqual(result.profile.bindings[0].id, profile.bindings[0].id)
        XCTAssertNotEqual(result.profile.bindings[0].steps[0].id, profile.bindings[0].steps[0].id)
    }

    func testImportRejectsOtherFiles() {
        XCTAssertThrowsError(try ProfileExchange.importProfile(from: Data("{\"hello\":1}".utf8))) {
            XCTAssertEqual($0 as? ExchangeError, .notAProfile)
        }
        XCTAssertThrowsError(try ProfileExchange.importProfile(from: Data("not json".utf8)))
    }
}

final class ConfigTests: XCTestCase {
    func testConfigSurvivesAJSONRoundTrip() throws {
        var config = AppConfig()
        config.detector.threshold = 0.05
        config.hasCompletedOnboarding = true
        config.startDryRun(hours: 24, now: Date(timeIntervalSince1970: 1_000_000))
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        let data = Data("{\"hasCompletedOnboarding\": true}".utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertTrue(config.hasCompletedOnboarding)
        XCTAssertEqual(config.detector, DetectorConfig())
        XCTAssertEqual(config.profiles.count, 5)
        XCTAssertEqual(config.activeProfile.name, "Work")
    }

    func testMalformedFieldFallsBackWithoutLosingTheRest() throws {
        let data = Data("{\"hasCompletedOnboarding\": true, \"detector\": \"oops\", \"showHUD\": false}".utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertTrue(config.hasCompletedOnboarding)
        XCTAssertFalse(config.showHUD)
        XCTAssertEqual(config.detector, DetectorConfig())
    }

    func testUnknownActiveProfileFallsBackToTheFirst() throws {
        let data = Data("{\"activeProfileID\": \"gone\"}".utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(config.activeProfileID, config.profiles[0].id)
    }

    func testDryRunWindow() {
        var config = AppConfig()
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(config.isDryRun(now: start))
        config.startDryRun(hours: 24, now: start)
        XCTAssertTrue(config.isDryRun(now: start.addingTimeInterval(3600)))
        XCTAssertFalse(config.isDryRun(now: start.addingTimeInterval(25 * 3600)))
        config.endDryRun()
        XCTAssertFalse(config.isDryRun(now: start.addingTimeInterval(60)))
    }

    func testNormalizedClampsAbsurdValues() {
        var c = DetectorConfig()
        c.threshold = 5
        c.cooldown = 0
        c.groupingWindow = 100
        c.maxTaps = 40
        c.hardPeak = -1
        let n = c.normalized()
        XCTAssertEqual(n.threshold, 0.2)
        XCTAssertEqual(n.cooldown, 0.07)
        XCTAssertEqual(n.groupingWindow, 1.5)
        XCTAssertEqual(n.maxTaps, 5)
        XCTAssertEqual(n.hardPeak, 0)
    }

    func testPipelineConfigCarriesRhythmsAndZones() {
        var config = AppConfig()
        let rhythm = RhythmPattern(gaps: [0.2, 0.7])
        config.profiles[0].bindings.append(
            GestureBinding(key: GestureKey(taps: 3), rhythm: rhythm, steps: [ActionStep(actionId: "copy")])
        )
        XCTAssertEqual(config.pipelineConfig().rhythms, [rhythm])
        XCTAssertNil(config.pipelineConfig().zones)
    }
}

final class RecordingTests: XCTestCase {
    func testCSVRoundTrip() throws {
        let original = Synth.signal(duration: 0.2, taps: [SynthTap(time: 0.1, gyroDir: Vec3(0, 0, 1))], withGyro: true)
        let decoded = try RecordingCSV.decode(RecordingCSV.encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testCSVRoundTripWithoutGyro() throws {
        let original = Synth.signal(duration: 0.1, inputEvents: [0.02])
        let decoded = try RecordingCSV.decode(RecordingCSV.encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded[0].gyro)
    }

    func testCSVRejectsWrongHeader() {
        XCTAssertThrowsError(try RecordingCSV.decode("a,b,c\n1,2,3\n")) {
            XCTAssertEqual($0 as? RecordingError, .badHeader)
        }
    }

    func testCSVReportsTheBadRow() {
        let text = RecordingCSV.header + "\n0,0,0,-1,,,,1000\n1,oops\n"
        XCTAssertThrowsError(try RecordingCSV.decode(text)) {
            XCTAssertEqual($0 as? RecordingError, .badRow(3))
        }
    }

    func testReplayOfARecordingGivesTheSameGestures() throws {
        let taps = Synth.run(start: 1.5, count: 3, spacing: 0.2)
        let original = Synth.signal(duration: 4, taps: taps)
        let replayed = try RecordingCSV.decode(RecordingCSV.encode(original))
        let a = Replay.run(original, config: PipelineConfig())
        let b = Replay.run(replayed, config: PipelineConfig())
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.first?.taps, 3)
    }
}
