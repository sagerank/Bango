import SwiftUI
import TapCore

/// Every permission TapDeck can use, in one list with one button. Used by the welcome tour and General.
struct PermissionsPanel: View {
    @EnvironmentObject private var store: ConfigStore
    @ObservedObject private var center = PermissionCenter.shared
    @State private var confirmReset = false

    private var usage: [SetupItem: [String]] { PermissionPlan.usage(in: store.config) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card(padding: 4) {
                VStack(spacing: 0) {
                    ForEach(Array(PermissionPlan.order.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.stroke) }
                        row(item)
                    }
                }
            }

            HStack(spacing: 10) {
                if center.needsRestart {
                    Button("Restart TapDeck") { center.restartApp() }.buttonStyle(.pillPrimary)
                } else if center.isRunning {
                    ProgressView().controlSize(.small)
                    Text(center.current.map { "Waiting for \($0.title)…" } ?? "Working…")
                        .font(.callout).foregroundStyle(Theme.secondary)
                    Button("Skip this one") { center.skipCurrent() }.buttonStyle(.pill)
                } else if center.allDone {
                    Label("Everything is allowed", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.good)
                } else {
                    Button("Set up everything") { Task { await center.setUp() } }.buttonStyle(.pillPrimary)
                }
                Spacer()
                Menu("More") {
                    Button("Check again") { Task { await center.refreshAll() } }
                    Button("Clear TapDeck's permissions…") { confirmReset = true }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }

            if let note = center.note {
                Text(note).font(.callout).foregroundStyle(Theme.warning)
            }
            Text("macOS never lets an app switch these on by itself, so each opens its own prompt or Settings page. TapDeck asks in the order that needs the fewest trips and notices the moment you allow each one.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
        .task {
            await center.refreshAll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                center.refreshQuick()
            }
        }
        .confirmationDialog("Clear every permission TapDeck was given?", isPresented: $confirmReset) {
            Button("Clear permissions", role: .destructive) { Task { await center.resetAll() } }
        } message: {
            Text("Use this after installing a new build if a permission looks on but does not work.")
        }
    }

    private func row(_ item: SetupItem) -> some View {
        let state = center.state(item)
        let active = center.current == item
        return HStack(alignment: .top, spacing: 12) {
            statusIcon(state, active: active)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).foregroundStyle(Theme.text)
                Text(item.why).font(.caption).foregroundStyle(Theme.secondary)
                if let names = usage[item], !names.isEmpty {
                    Text("Used by: " + names.prefix(4).joined(separator: ", ") + (names.count > 4 ? " and \(names.count - 4) more" : ""))
                        .font(.caption2).foregroundStyle(Theme.accent)
                }
                if state == .needsRestart {
                    Text("Allowed. Restart TapDeck to finish.").font(.caption2).foregroundStyle(Theme.warning)
                } else if state == .needsApproval {
                    Text("Switch TapDeck on in System Settings, Login Items.").font(.caption2).foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            if state == .missing, !center.isRunning {
                Button("Allow") { Task { await center.setUp([item]) } }.buttonStyle(.pill)
            }
        }
        .padding(12)
        .background(active ? Theme.accentSoft : Color.clear)
        .animation(.easeInOut(duration: 0.25), value: active)
        .animation(.easeInOut(duration: 0.25), value: state)
    }

    @ViewBuilder
    private func statusIcon(_ state: PermissionCenter.Status, active: Bool) -> some View {
        if active {
            ProgressView().controlSize(.small)
        } else {
            switch state {
            case .granted:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                    .transition(.scale.combined(with: .opacity))
            case .needsRestart, .needsApproval:
                Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(Theme.warning)
            case .unavailable:
                Image(systemName: "minus.circle").foregroundStyle(Theme.secondary)
            case .missing:
                Image(systemName: "circle.dashed").foregroundStyle(Theme.secondary)
            }
        }
    }
}
