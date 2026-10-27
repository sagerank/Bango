import SwiftUI
import TapCore

/// First launch: check the hardware, explain permissions, let the user try a tap, start in test mode.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable { case hardware, permissions, tryIt, safeStart }

    @State private var step: Step
    @State private var token = UUID()
    @State private var lastGesture: RecognizedGesture?
    @ObservedObject private var permissions = PermissionCenter.shared
    @State private var startInTestMode = true

    /// `startAtPermissions` is for people who already finished the tour but lost their permissions,
    /// for example after installing a new build.
    init(startAtPermissions: Bool = false) {
        _step = State(initialValue: startAtPermissions ? .permissions : .hardware)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Theme.accent : Theme.surfaceRaised)
                        .frame(height: 4)
                }
            }

            content

            Spacer()
            footer
        }
        .padding(28)
        .frame(minWidth: 540, idealWidth: 580, minHeight: 560, idealHeight: 680)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .onAppear { engine.beginPractice(token) { gesture in lastGesture = gesture } }
        .onDisappear { engine.endPractice(token) }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .hardware:
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Tap your Mac to control it", subtitle: "Bingo turns taps on the body of your MacBook into actions: copy, paste, volume, lock screen, and more.")
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        if monitor.isSupported && monitor.isMonitoring {
                            Label("Motion sensor found.", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                            Text(monitor.hasGyroscope ? "Gyroscope found too, so tap zones can work." : "No gyroscope found. Tap counts still work. Tap zones may be less reliable.")
                                .font(.callout).foregroundStyle(Theme.secondary)
                        } else {
                            Label("No motion sensor found.", systemImage: "xmark.circle.fill").foregroundStyle(Theme.danger)
                            Text(monitor.statusMessage).font(.callout).foregroundStyle(Theme.secondary)
                            Text("Bingo needs the built-in accelerometer of an Apple Silicon MacBook. You can look around, but taps will not be detected on this Mac.")
                                .font(.callout).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "What Bingo needs", subtitle: "Each line shows whether it is allowed. Press Allow on the ones you want. You can skip any of them and come back to Setup later.")
                PermissionsPanel()
            }
        case .tryIt:
            VStack(alignment: .leading, spacing: 10) {
                PageHeader(title: "Learn the taps", subtitle: "Follow the steps. Bingo shows what it heard. Nothing will run yet.")
                ScrollView {
                    TapTrainerView(
                        lessons: TapLessons.basic,
                        finishedDetail: "Taps are working. Left and right taps are optional: set them up later in Zones & rhythm."
                    )
                    .padding(.trailing, 6)
                }
            }
        case .safeStart:
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Start safely", subtitle: "A few starter gestures are ready: one tap plays or pauses, two copy, three paste, four lock the screen.")
                Card {
                    Toggle(isOn: $startInTestMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test mode for the first 24 hours").foregroundStyle(Theme.text)
                            Text("Gestures are recognized and listed in Activity, but nothing runs. Use the Mac as usual, then check Activity for anything unexpected before you switch it off in General.")
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if step != .hardware {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .hardware }.buttonStyle(.pill)
            }
            Spacer()
            if step == .safeStart {
                Button("Finish") { finish() }.buttonStyle(.pillPrimary)
            } else {
                Button(step == .permissions && !permissions.allDone ? "Skip for now" : "Continue") {
                    step = Step(rawValue: step.rawValue + 1) ?? .safeStart
                }
                .buttonStyle(.pillPrimary)
            }
        }
    }

    private func finish() {
        let firstTime = !store.config.hasCompletedOnboarding
        store.update { config in
            config.hasCompletedOnboarding = true
            if firstTime && startInTestMode { config.startDryRun() }
        }
        permissions.markSetupSeen()
        dismiss()
    }
}
