import SwiftUI
import TapCore

struct ZonesRhythmView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine

    @State private var showZoneWizard = false
    @State private var showRhythmRecorder = false
    @State private var newRhythmBinding: GestureBinding?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Zones & rhythm",
                subtitle: "Two extra ways to tell gestures apart: where you tap, and the timing of your taps."
            )

            zonesCard
            rhythmCard
        }
        .sheet(isPresented: $showZoneWizard) {
            ZoneWizard()
                .environmentObject(store)
                .environmentObject(monitor)
                .environmentObject(engine)
        }
        .sheet(isPresented: $showRhythmRecorder) {
            RhythmRecorderSheet { pattern in
                // Opening the editor while the recorder is still closing makes macOS drop it, so wait a moment.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    newRhythmBinding = GestureBinding(
                        key: GestureKey(taps: pattern.taps),
                        rhythm: pattern,
                        steps: [ActionStep(actionId: "none")]
                    )
                }
            }
            .environmentObject(store)
            .environmentObject(monitor)
            .environmentObject(engine)
        }
        .sheet(item: $newRhythmBinding) { binding in
            BindingEditor(
                binding: binding,
                isNew: true,
                siblings: store.config.activeProfile.bindings,
                onSave: { saved in
                    store.update { config in
                        config.updateActiveProfile { $0.bindings.append(saved) }
                    }
                },
                onDelete: nil
            )
            .environmentObject(store)
            .environmentObject(monitor)
            .environmentObject(engine)
        }
    }

    // MARK: Zones

    private var zonesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Tap zones")
                    Text("Experimental")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.warningSoft)
                        .foregroundStyle(Theme.warning)
                        .clipShape(Capsule())
                }

                Text("Teach Bango what a tap on the left, the right and the top of your Mac feels like. Then a double tap on the left can do something different from a double tap on the right.")
                    .foregroundStyle(Theme.text)

                if monitor.hasGyroscope {
                    Label("Gyroscope found. Zones use both the gyroscope and the accelerometer.", systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(Theme.good)
                } else {
                    Notice(style: .warning, text: "No gyroscope was found on this Mac, so zones rely on the accelerometer alone. They may be less reliable. Tap counts, rhythm and strength are not affected.")
                }

                if store.config.zoneModel != nil {
                    Label("Zones are set up.", systemImage: "checkmark.seal")
                        .foregroundStyle(Theme.good)
                }

                HStack {
                    Button(store.config.zoneModel == nil ? "Set up zones" : "Set up again") { showZoneWizard = true }
                        .buttonStyle(.pillPrimary)
                        .disabled(!monitor.isMonitoring)
                    if store.config.zoneModel != nil {
                        Button("Forget zones") { store.update { $0.zoneModel = nil } }
                            .buttonStyle(.pillDestructive)
                    }
                }
                if !monitor.isMonitoring {
                    Text("Resume monitoring to set up zones.").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    // MARK: Rhythm

    private var rhythmCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Tap rhythm")
                Text("Record a pattern such as tap, tap, pause, tap, and give it its own action. Good for things you want to be hard to trigger by accident.")
                    .foregroundStyle(Theme.text)
                Button("Record a rhythm") { showRhythmRecorder = true }
                    .buttonStyle(.pillPrimary)
                    .disabled(!monitor.isMonitoring)
                Text("This adds the rhythm to the current profile. To use a rhythm only in one app, open Gestures, and under that app choose Add a gesture, then Tap rhythm.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                Text("Rhythms use up to \(store.config.detector.maxTaps) taps. Long pauses make Bango wait a little longer before it decides.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}

// MARK: - Zone wizard

struct ZoneWizard: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine
    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case collecting(TapZone)
        case testing
        case failed(String)
    }

    @State private var token = UUID()
    @State private var stage = Stage.collecting(.left)
    @State private var samples: [TapZone: [ImpactFeatures]] = [:]
    @State private var model: ZoneModel?
    @State private var lastTapTime = -10.0
    @State private var liveZone: TapZone?

    private let needed = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Set up zones", subtitle: "Nothing will run during setup.")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    switch stage {
                    case .collecting(let zone):
                        progress(for: zone)
                    case .testing:
                        testing
                    case .failed(let message):
                        Notice(style: .danger, text: message)
                    }
                }
            }

            Spacer()
            footer
        }
        .padding(24)
        .frame(width: 520, height: 560)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            engine.beginPractice(token)
            monitor.onImpact = { impact in handle(impact) }
        }
        .onDisappear {
            monitor.onImpact = nil
            engine.endPractice(token)
        }
    }

    private func progress(for zone: TapZone) -> some View {
        let count = samples[zone]?.count ?? 0
        let spot: TapLesson.Spot = zone == .left ? .left : (zone == .right ? .right : .top)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Spot \(stepNumber(zone)) of 3").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            Text(prompt(for: zone)).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
            HStack {
                Spacer()
                LaptopGuide(spot: spot, mood: count > 0 ? .heard : .waiting)
                Spacer()
            }
            HStack(spacing: 10) {
                ForEach(0..<needed, id: \.self) { index in
                    Circle()
                        .fill(index < count ? Theme.good : Theme.surfaceRaised)
                        .frame(width: 14, height: 14)
                }
                Text("\(count) of \(needed) taps")
                    .font(.callout.monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            Text("Tap this same spot \(needed) times, about a second apart, with one fingertip. A light knock is enough.")
                .font(.callout).foregroundStyle(Theme.secondary)
        }
    }

    private func stepNumber(_ zone: TapZone) -> Int {
        switch zone {
        case .left: return 1
        case .right: return 2
        default: return 3
        }
    }

    private func prompt(for zone: TapZone) -> String {
        switch zone {
        case .left: return "Tap the left side, next to the trackpad"
        case .right: return "Tap the right side, next to the trackpad"
        case .top: return "Tap just above the keyboard, near the hinge"
        case .any: return ""
        }
    }

    private var testing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Learned. Try a few taps to check.", systemImage: "checkmark.circle")
                .foregroundStyle(Theme.good)
            Text(liveZone.map { "That felt like: \($0.title)" } ?? "That felt like: not sure")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text("If it often says the wrong side or \"not sure\", zones will not be reliable on this Mac. You can leave them off and still use everything else.")
                .font(.callout).foregroundStyle(Theme.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            switch stage {
            case .collecting:
                Button("Cancel") { dismiss() }.buttonStyle(.pill)
            case .testing:
                Button("Discard") { dismiss() }.buttonStyle(.pill)
                Button("Use these zones") {
                    store.update { $0.zoneModel = model }
                    dismiss()
                }
                .buttonStyle(.pillPrimary)
            case .failed:
                Button("Close") { dismiss() }.buttonStyle(.pill)
                Button("Try again") { restart() }.buttonStyle(.pillPrimary)
            }
        }
    }

    private func restart() {
        samples = [:]
        model = nil
        liveZone = nil
        stage = .collecting(.left)
    }

    private func handle(_ impact: Impact) {
        guard impact.time - lastTapTime > 0.6 else { return }
        lastTapTime = impact.time

        switch stage {
        case .collecting(let zone):
            samples[zone, default: []].append(impact.features)
            if (samples[zone]?.count ?? 0) >= needed { advance(from: zone) }
        case .testing:
            liveZone = model.flatMap { m -> TapZone? in
                let zone = m.classify(impact.features)
                return zone == .any ? nil : zone
            }
        case .failed:
            break
        }
    }

    private func advance(from zone: TapZone) {
        switch zone {
        case .left: stage = .collecting(.right)
        case .right: stage = .collecting(.top)
        case .top, .any: learn()
        }
    }

    private func learn() {
        do {
            model = try ZoneModel.learn(
                left: samples[.left] ?? [],
                right: samples[.right] ?? [],
                top: samples[.top] ?? []
            )
            stage = .testing
        } catch let error as ZoneError {
            stage = .failed(error.message)
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Rhythm recorder

struct RhythmRecorderSheet: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine
    @Environment(\.dismiss) private var dismiss

    let onDone: (RhythmPattern) -> Void

    @State private var token = UUID()
    @State private var currentTimes: [Double] = []
    @State private var repeats: [[Double]] = []
    @State private var error: String?
    @State private var finishTask: Task<Void, Never>?

    private let needed = 3
    private let silenceToFinish = 1.4

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Record a rhythm", subtitle: "Nothing will run during recording.")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(0..<needed, id: \.self) { index in
                            Circle()
                                .fill(index < repeats.count ? Theme.accent : Theme.surfaceRaised)
                                .frame(width: 14, height: 14)
                        }
                    }
                    Text("Tap your rhythm, then stop. Repeat it \(needed) times, with a short wait in between.")
                        .foregroundStyle(Theme.text)
                    if !currentTimes.isEmpty {
                        Text("\(currentTimes.count) taps so far")
                            .font(.callout).foregroundStyle(Theme.secondary)
                    }
                    if let error {
                        Notice(style: .danger, text: error)
                    }
                }
            }

            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.pill)
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            engine.beginPractice(token)
            monitor.onImpact = { impact in handle(impact) }
        }
        .onDisappear {
            finishTask?.cancel()
            monitor.onImpact = nil
            engine.endPractice(token)
        }
    }

    private func handle(_ impact: Impact) {
        currentTimes.append(impact.time)
        finishTask?.cancel()
        finishTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(silenceToFinish * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { finishRepeat() }
        }
    }

    private func finishRepeat() {
        let times = currentTimes
        currentTimes = []
        guard times.count >= 2 else {
            error = "A rhythm needs at least 2 taps."
            return
        }
        guard times.count <= store.config.detector.maxTaps else {
            error = "That was \(times.count) taps. Rhythms can use at most \(store.config.detector.maxTaps)."
            repeats = []
            return
        }
        error = nil

        var gaps: [Double] = []
        for index in 1..<times.count { gaps.append(times[index] - times[index - 1]) }
        repeats.append(gaps)

        guard repeats.count >= needed else { return }
        do {
            let pattern = try RhythmLearner.learn(repeats: repeats)
            onDone(pattern)
            dismiss()
        } catch let learnError as RhythmError {
            error = learnError.message
            repeats = []
        } catch {
            self.error = error.localizedDescription
            repeats = []
        }
    }
}
