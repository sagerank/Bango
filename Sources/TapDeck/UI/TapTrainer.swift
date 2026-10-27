import SwiftUI
import TapCore

/// Guided practice. Shows what to do, reacts the moment a tap is heard, and says what went wrong.
struct TapTrainerView: View {
    let lessons: [TapLesson]
    var finishedTitle = "You are ready"
    var finishedDetail = "Taps are working. Your gestures will run once you leave test mode."

    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine

    @State private var token = UUID()
    @State private var index = 0
    @State private var mood = LaptopGuide.Mood.waiting
    @State private var message: String?
    @State private var attempts = 0
    @State private var showZoneSetup = false

    private var finished: Bool { index >= lessons.count }
    private var lesson: TapLesson? { finished ? nil : lessons[index] }
    private var zonesReady: Bool { store.config.zoneModel != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            progress

            if let lesson {
                if lesson.needsZones && !zonesReady {
                    zoneGate(lesson)
                } else {
                    lessonCard(lesson)
                }
            } else {
                doneCard
            }
        }
        .onAppear(perform: listen)
        .onDisappear {
            monitor.onImpact = nil
            engine.endPractice(token)
        }
        .sheet(isPresented: $showZoneSetup, onDismiss: listen) {
            ZoneWizard()
                .environmentObject(store)
                .environmentObject(monitor)
                .environmentObject(engine)
        }
    }

    // MARK: Pieces

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<lessons.count, id: \.self) { i in
                Capsule()
                    .fill(i < index ? Theme.good : (i == index ? Theme.accent : Theme.surfaceRaised))
                    .frame(height: 4)
            }
        }
    }

    private func lessonCard(_ lesson: TapLesson) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step \(index + 1) of \(lessons.count)")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            Text(lesson.title).font(.title2.weight(.bold)).foregroundStyle(Theme.text)
            Text(lesson.instruction)
                .font(.callout).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                VStack(spacing: 10) {
                    LaptopGuide(spot: lesson.spot, taps: lesson.taps, mood: mood)
                    TapBeats(count: lesson.taps, done: mood == .success)
                }
                Spacer()
            }

            status

            HStack(spacing: 8) {
                Image(systemName: "checkmark").foregroundStyle(Theme.good)
                Text("One fingertip, a light knock").font(.caption).foregroundStyle(Theme.secondary)
                Image(systemName: "xmark").foregroundStyle(Theme.danger)
                Text("Not while typing, not hard, not on the screen").font(.caption).foregroundStyle(Theme.secondary)
            }

            HStack {
                if index > 0 {
                    Button("Back") { go(to: index - 1) }.buttonStyle(.quiet)
                }
                Spacer()
                Button("Skip this step") { go(to: index + 1) }.buttonStyle(.quiet)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch mood {
        case .success:
            Label(message ?? "Got it", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
        case .heard:
            Label("Heard a tap…", systemImage: "waveform").foregroundStyle(Theme.accent)
        case .waiting:
            if let message {
                VStack(alignment: .leading, spacing: 4) {
                    Label(message, systemImage: "arrow.counterclockwise").foregroundStyle(Theme.warning)
                    if attempts >= 3 {
                        Text("Still not working? Open Tuning and raise the sensitivity, or check that the sensor is found in Setup.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            } else {
                Label("Waiting for your tap", systemImage: "hand.tap").foregroundStyle(Theme.secondary)
            }
        }
    }

    private func zoneGate(_ lesson: TapLesson) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lesson.title).font(.title2.weight(.bold)).foregroundStyle(Theme.text)
            Text("Telling the left side from the right side needs a one-time teach-in: you tap each spot a few times so Bingo learns how it feels on your Mac. It is experimental and may not work on every Mac.")
                .font(.callout).foregroundStyle(Theme.secondary)
            HStack {
                Button("Teach left and right…") { showZoneSetup = true }.buttonStyle(.pillPrimary)
                Button("Skip") { go(to: lessons.count) }.buttonStyle(.pill)
            }
        }
    }

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40)).foregroundStyle(Theme.good)
                .symbolEffect(.bounce, value: finished)
            Text(finishedTitle).font(.title2.weight(.bold)).foregroundStyle(Theme.text)
            Text(finishedDetail).font(.callout).foregroundStyle(Theme.secondary)
            Button("Practice again") { go(to: 0) }.buttonStyle(.pill)
        }
    }

    // MARK: Behaviour

    private func listen() {
        engine.beginPractice(token) { gesture in handle(gesture) }
        monitor.onImpact = { _ in heard() }
    }

    private func heard() {
        guard mood == .waiting, lesson != nil else { return }
        mood = .heard
        // Back to waiting if no full gesture follows, so the picture never gets stuck.
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if mood == .heard { mood = .waiting }
        }
    }

    private func handle(_ gesture: RecognizedGesture) {
        guard let lesson, !(lesson.needsZones && !zonesReady), mood != .success else { return }
        switch TapLessons.evaluate(lesson, gesture: gesture) {
        case .success(let text):
            message = text
            mood = .success
            let current = index
            Task {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                if index == current { go(to: index + 1) }
            }
        case .tryAgain(let text):
            message = text
            attempts += 1
            mood = .waiting
        }
    }

    private func go(to newIndex: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            index = max(0, newIndex)
            mood = .waiting
            message = nil
            attempts = 0
        }
    }
}

/// The practice as its own window, for the Setup page.
struct PracticeSheet: View {
    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Practice taps", subtitle: "Nothing will run while you practice.")
            ScrollView {
                TapTrainerView(
                    lessons: TapLessons.basic + TapLessons.zones,
                    finishedDetail: "Taps are working."
                )
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.pillPrimary)
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 520, idealHeight: 620)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}
