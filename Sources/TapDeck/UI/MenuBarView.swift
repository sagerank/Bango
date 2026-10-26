import AppKit
import SwiftUI
import TapCore

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var permissions = PermissionCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            WaveformView(values: monitor.waveform, threshold: monitor.snapshot.threshold)
                .frame(height: 56)

            if permissions.needsAttention {
                Notice(style: .warning, text: "Setup is not finished. Some actions will not work until you allow them.")
                Button("Finish setup") { open() }.buttonStyle(.pillPrimary)
            }
            if store.config.isDryRun() {
                Notice(style: .info, text: "Test mode is on. Gestures are shown but nothing runs.")
            }
            if let last = engine.activity.first {
                lastResult(last)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Profile")
                ForEach(store.config.profiles) { profile in
                    Button {
                        store.update { $0.activeProfileID = profile.id }
                    } label: {
                        HStack {
                            Image(systemName: profile.id == store.config.activeProfileID ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(profile.id == store.config.activeProfileID ? Theme.accent : Theme.secondary)
                            Text(profile.name).foregroundStyle(Theme.text)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(Theme.stroke)

            HStack {
                Button(store.config.monitoringEnabled ? "Pause" : "Resume") {
                    store.update { $0.monitoringEnabled.toggle() }
                }
                .buttonStyle(.pill)
                Button("Open TapDeck") { open() }
                    .buttonStyle(.pillPrimary)
                Spacer()
                Button("Quit") { model.quit() }
                    .buttonStyle(.quiet)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { permissions.refreshQuick() }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "hand.tap", size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("TapDeck").font(.headline).foregroundStyle(Theme.text)
                Text(monitor.statusMessage)
                    .font(.caption)
                    .foregroundStyle(monitor.isSupported ? Theme.secondary : Theme.danger)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private func lastResult(_ entry: ActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.gesture).font(.callout.weight(.medium)).foregroundStyle(Theme.text)
            Text(ActivityText.outcome(entry.outcome))
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
        }
    }

    private func open() {
        if model.mainWindow == nil {
            model.userRequestedWindow = true
            openWindow(id: "main")
        } else {
            model.showMainWindow()
        }
    }
}

enum ActivityText {
    static func outcome(_ outcome: ActivityEntry.Outcome) -> String {
        switch outcome {
        case .ran(let text): return text
        case .testMode(let text): return "Test mode, would run: \(text)"
        case .practice: return "Practice, nothing ran"
        case .noBinding: return "No action assigned"
        case .blocked(let reason): return reason
        case .failed(let message): return "Failed: \(message)"
        }
    }

    static func symbol(_ outcome: ActivityEntry.Outcome) -> String {
        switch outcome {
        case .ran: return "checkmark.circle"
        case .testMode: return "testtube.2"
        case .practice: return "hand.tap"
        case .noBinding: return "minus.circle"
        case .blocked: return "exclamationmark.shield"
        case .failed: return "exclamationmark.triangle"
        }
    }

    static func tint(_ outcome: ActivityEntry.Outcome) -> Color {
        switch outcome {
        case .ran: return Theme.good
        case .testMode, .practice: return Theme.accent
        case .noBinding: return Theme.secondary
        case .blocked: return Theme.warning
        case .failed: return Theme.danger
        }
    }
}
