import SwiftUI
import TapCore

struct TuningView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine

    @State private var token = UUID()
    @State private var lastGesture: RecognizedGesture?
    @State private var gestureCount = 0
    @State private var showCalibration = false
    @State private var showStrengthSetup = false

    private var detector: DetectorConfig { store.config.detector }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Tuning",
                subtitle: "Make the taps feel right. Actions are paused on this screen, so you can tap freely."
            )

            signalCard
            practiceCard
            sensitivityCard
            strengthCard
        }
        .onAppear {
            engine.beginPractice(token) { gesture in
                lastGesture = gesture
                gestureCount += 1
            }
        }
        .onDisappear { engine.endPractice(token) }
        .sheet(isPresented: $showCalibration) {
            CalibrationSheet()
                .environmentObject(store)
                .environmentObject(monitor)
                .environmentObject(engine)
        }
        .sheet(isPresented: $showStrengthSetup) {
            CalibrationSheet(teachStrength: true)
                .environmentObject(store)
                .environmentObject(monitor)
                .environmentObject(engine)
        }
    }

    // MARK: Cards

    private var signalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Live signal")
                WaveformView(values: monitor.waveform, threshold: monitor.snapshot.threshold)
                    .frame(height: 110)
                HStack {
                    Text(monitor.statusMessage)
                    Spacer()
                    Text("Threshold \(monitor.snapshot.threshold.formatted(.number.precision(.fractionLength(3)))) g")
                    Text("\(Int(monitor.snapshot.sampleRate)) Hz")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(monitor.isSupported ? Theme.secondary : Theme.danger)
                ignoredBumps
                if monitor.snapshot.guarded {
                    Text("Typing guard active: taps are ignored while you type or click.")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
            }
        }
    }

    /// Shows why bumps that crossed the threshold were not counted as taps, so a missed tap can be explained.
    @ViewBuilder
    private var ignoredBumps: some View {
        let rejections = monitor.snapshot.rejections
        if rejections.total > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text(rejections.last.map { "Last ignored bump: \($0.label)" } ?? "")
                    .font(.caption).foregroundStyle(Theme.warning)
                Text(
                    Rejection.allCases
                        .filter { rejections.count($0) > 0 }
                        .map { "\($0.label): \(rejections.count($0))" }
                        .joined(separator: "   ")
                )
                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var practiceCard: some View {
        Card {
            HStack(spacing: 14) {
                IconBadge(symbol: "hand.tap", size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Try it")
                    if let lastGesture {
                        Text(Describe.gesture(lastGesture))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text("\(gestureCount) gestures seen")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    } else {
                        Text("Tap the palm rest or the lid")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text("Nothing seen yet")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private var sensitivityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(text: "Detection")

                labeled("Sensitivity", detail: "Higher picks up lighter taps, and also more false ones.") {
                    Slider(value: sensitivity, in: 0...1)
                }

                labeled("Time between taps", detail: "How long Bango waits for another tap before it decides. Shorter feels faster.") {
                    Slider(value: binding(\.groupingWindow), in: 0.25...0.8)
                }

                Stepper(value: intBinding(\.maxTaps), in: 1...5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Most taps in a gesture: \(detector.maxTaps)").foregroundStyle(Theme.text)
                        Text("Extra taps are counted as this many.").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }

                Toggle(isOn: boolBinding(\.guardEnabled)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Typing guard").foregroundStyle(Theme.text)
                        Text("Ignore taps that happen while you type or click. Strongly recommended.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }

                HStack {
                    Button("Calibrate…") { showCalibration = true }.buttonStyle(.pillPrimary)
                    Button("Reset to defaults") {
                        store.update { $0.detector = DetectorConfig() }
                    }
                    .buttonStyle(.pill)
                }
            }
        }
    }

    private var strengthCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Soft and hard taps")
                Toggle(isOn: Binding(
                    get: { detector.hardPeak > 0 },
                    set: { on in
                        if on {
                            // A guess would be wrong: taps differ a lot between Macs and people. Measure instead.
                            showStrengthSetup = true
                        } else {
                            store.update { $0.detector.hardPeak = 0 }
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tell soft and hard taps apart").foregroundStyle(Theme.text)
                        Text("Lets one gesture do two things, for example a soft double tap and a hard double tap.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }

                if detector.hardPeak > 0 {
                    labeled("Hard tap level", detail: "Taps stronger than this count as hard.") {
                        Slider(value: binding(\.hardPeak), in: 0.05...0.8)
                    }
                    Button("Teach it again…") { showStrengthSetup = true }.buttonStyle(.pill)
                }

                // What the last gesture measured, so the level can be set by eye.
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg").foregroundStyle(Theme.accent)
                    if let gesture = lastGesture {
                        let label = StrengthCalibration.label(peak: gesture.peak, hardPeak: detector.hardPeak)
                        Text("Last tap strength \(gesture.peak.formatted(.number.precision(.fractionLength(2)))) g"
                             + (label.map { " · \($0.title.lowercased())" } ?? " · soft and hard are off"))
                            .font(.callout.monospacedDigit()).foregroundStyle(Theme.text)
                    } else {
                        Text("Tap to see how strong it measures").font(.callout).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    // MARK: Binding helpers

    private func labeled<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(Theme.text)
            content()
            Text(detail).font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<DetectorConfig, Double>) -> Binding<Double> {
        Binding(
            get: { store.config.detector[keyPath: keyPath] },
            set: { value in store.update { $0.detector[keyPath: keyPath] = value } }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<DetectorConfig, Int>) -> Binding<Int> {
        Binding(
            get: { store.config.detector[keyPath: keyPath] },
            set: { value in store.update { $0.detector[keyPath: keyPath] = value } }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<DetectorConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.config.detector[keyPath: keyPath] },
            set: { value in store.update { $0.detector[keyPath: keyPath] = value } }
        )
    }

    /// 0 is least sensitive (threshold 0.12 g), 1 is most sensitive (0.01 g), on a log scale.
    private var sensitivity: Binding<Double> {
        let high = 0.12, low = 0.01
        return Binding(
            get: {
                let t = min(max(store.config.detector.threshold, low), high)
                return log(t / high) / log(low / high)
            },
            set: { s in
                let threshold = high * pow(low / high, s)
                store.update { $0.detector.threshold = threshold }
            }
        )
    }
}

// MARK: - Calibration

/// Measures a few normal and hard taps and picks settings that fit them.
struct CalibrationSheet: View {
    /// True when the sheet only teaches soft and hard taps and leaves sensitivity alone.
    var teachStrength = false

    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine
    @Environment(\.dismiss) private var dismiss

    private enum Stage { case normal, hard, done }

    @State private var token = UUID()
    @State private var stage = Stage.normal
    @State private var normalPeaks: [Double] = []
    @State private var hardPeaks: [Double] = []
    @State private var lastTapTime = -10.0
    @State private var result: String?

    private let needed = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: teachStrength ? "Teach soft and hard taps" : "Calibrate", subtitle: subtitle)

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(0..<needed, id: \.self) { index in
                            Circle()
                                .fill(index < currentCount ? Theme.accent : Theme.surfaceRaised)
                                .frame(width: 14, height: 14)
                        }
                    }
                    Text(instruction).foregroundStyle(Theme.text)
                    if let result {
                        Notice(style: .info, text: result)
                    }
                }
            }

            Spacer()
            HStack {
                Spacer()
                if stage == .done {
                    Button("Done") { dismiss() }.buttonStyle(.pillPrimary)
                } else {
                    Button("Cancel") { dismiss() }.buttonStyle(.pill)
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            engine.beginPractice(token)
            monitor.onImpact = { impact in collect(impact) }
        }
        .onDisappear {
            monitor.onImpact = nil
            engine.endPractice(token)
        }
    }

    private var currentCount: Int {
        switch stage {
        case .normal: return normalPeaks.count
        case .hard: return hardPeaks.count
        case .done: return needed
        }
    }

    private var subtitle: String {
        "Tap one at a time, about a second apart. Nothing will run during this."
    }

    private var instruction: String {
        switch stage {
        case .normal:
            return teachStrength
                ? "Tap as lightly as you can while Bango still notices, \(needed) times."
                : "Tap your Mac the way you normally would, \(needed) times."
        case .hard:
            return teachStrength
                ? "Now tap firmly, the way you would for a hard tap, \(needed) times."
                : "Now tap noticeably harder, \(needed) times."
        case .done: return "Finished."
        }
    }

    private func collect(_ impact: Impact) {
        // One tap per second at most, so a bounce is not counted twice.
        guard impact.time - lastTapTime > 0.6 else { return }
        lastTapTime = impact.time

        switch stage {
        case .normal:
            normalPeaks.append(impact.peak)
            if normalPeaks.count >= needed { stage = .hard }
        case .hard:
            hardPeaks.append(impact.peak)
            if hardPeaks.count >= needed { finish() }
        case .done:
            break
        }
    }

    private func finish() {
        func g(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
        let soft = StrengthCalibration.median(normalPeaks)
        let hard = StrengthCalibration.median(hardPeaks)
        var text = "Measured about \(g(soft)) g for \(teachStrength ? "soft" : "normal") taps and \(g(hard)) g for hard taps. "

        switch StrengthCalibration.fit(soft: normalPeaks, hard: hardPeaks) {
        case .success(let fit):
            store.update {
                $0.detector.hardPeak = fit.hardPeak
                $0.detector.threshold = StrengthCalibration.suggestedThreshold(lightestMedian: fit.softMedian, current: $0.detector.threshold)
            }
            text += "The line between soft and hard is \(g(fit.hardPeak)) g. Soft and hard are on."
        case .failure(.notDifferentEnough(let ratio)):
            store.update {
                $0.detector.hardPeak = 0
                $0.detector.threshold = StrengthCalibration.suggestedThreshold(lightestMedian: soft, current: $0.detector.threshold)
            }
            text += "The hard taps were only \(g(ratio)) times stronger and Bango needs \(g(StrengthCalibration.minimumRatio)) times, so soft and hard stay off. Try a clearly lighter and a clearly firmer tap."
        case .failure(.tooFewTaps):
            text += "Too few taps were measured. Try again."
        }
        result = text
        stage = .done
    }
}
