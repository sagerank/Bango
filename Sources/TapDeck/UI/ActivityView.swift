import AppKit
import SwiftUI
import TapCore
import UniformTypeIdentifiers

struct ActivityView: View {
    @EnvironmentObject private var engine: Engine
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor

    @State private var recordingSecondsLeft: Int?
    @State private var labMessage: (style: Notice.Style, text: String)?
    @State private var replayResult: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Activity",
                subtitle: "What Bingo saw, and what it did about it. Kept in memory only, cleared when you quit."
            )

            Card(padding: 8) {
                VStack(spacing: 0) {
                    if engine.activity.isEmpty {
                        Text("Nothing yet. Tap your Mac.")
                            .foregroundStyle(Theme.secondary)
                            .padding(16)
                    }
                    ForEach(engine.activity) { entry in
                        row(entry)
                        if entry.id != engine.activity.last?.id {
                            Divider().overlay(Theme.stroke).padding(.horizontal, 8)
                        }
                    }
                }
            }
            if !engine.activity.isEmpty {
                Button("Clear") { engine.clearActivity() }.buttonStyle(.quiet)
            }

            labCard
        }
    }

    private func row(_ entry: ActivityEntry) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: ActivityText.symbol(entry.outcome), tint: ActivityText.tint(entry.outcome), size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.gesture).font(.callout.weight(.medium)).foregroundStyle(Theme.text)
                Text(ActivityText.outcome(entry.outcome)).font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(entry.date.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondary)
        }
        .padding(10)
    }

    // MARK: Lab

    private var labCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Lab")
                Text("Record raw sensor data to a file, or replay a recording through the detector. Useful for bug reports: attach a recording to an issue so the problem can be reproduced without your Mac.")
                    .foregroundStyle(Theme.text)
                Text("A recording holds motion numbers and the time since your last key press or click. It never contains what you typed.")
                    .font(.caption).foregroundStyle(Theme.secondary)

                if let labMessage {
                    Notice(style: labMessage.style, text: labMessage.text)
                }

                HStack {
                    Button(recordingSecondsLeft.map { "Recording… \($0)" } ?? "Record 10 seconds") { record() }
                        .buttonStyle(.pillPrimary)
                        .disabled(recordingSecondsLeft != nil || !monitor.isMonitoring)
                    Button("Replay a recording…") { replay() }.buttonStyle(.pill)
                }

                if let replayResult {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Found \(replayResult.count) gestures").foregroundStyle(Theme.text)
                        ForEach(Array(replayResult.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption.monospaced()).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        }
    }

    private func record() {
        labMessage = nil
        monitor.startRecording()
        recordingSecondsLeft = 10
        Task { @MainActor in
            for remaining in stride(from: 9, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                recordingSecondsLeft = remaining
            }
            recordingSecondsLeft = nil
            let samples = monitor.stopRecording()
            save(samples)
        }
    }

    private func save(_ samples: [SensorSample]) {
        guard !samples.isEmpty else {
            labMessage = (.warning, "No sensor data was recorded. Is monitoring paused?")
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save recording"
        panel.nameFieldStringValue = "bingo-recording.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try RecordingCSV.encode(samples).write(to: url, atomically: true, encoding: .utf8)
            labMessage = (.info, "Saved \(samples.count) samples.")
        } catch {
            labMessage = (.danger, "Could not save: \(error.localizedDescription)")
        }
    }

    private func replay() {
        labMessage = nil
        let panel = NSOpenPanel()
        panel.title = "Choose a recording"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let samples = try RecordingCSV.decode(text)
            let gestures = Replay.run(samples, config: store.config.pipelineConfig())
            replayResult = gestures.map { gesture in
                "\(String(format: "%7.2f", gesture.time)) s  \(Describe.gesture(gesture))"
            }
            labMessage = (.info, "Replayed \(samples.count) samples with your current settings.")
        } catch let error as RecordingError {
            switch error {
            case .badHeader: labMessage = (.danger, "That file is not a Bingo recording.")
            case .badRow(let line): labMessage = (.danger, "Line \(line) of the file could not be read.")
            }
        } catch {
            labMessage = (.danger, "Could not open the file: \(error.localizedDescription)")
        }
    }
}
