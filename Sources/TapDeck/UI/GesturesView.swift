import AppKit
import SwiftUI
import TapCore
import UniformTypeIdentifiers

/// Where a newly recorded rhythm goes: the profile itself, or one app's override.
private struct RhythmTarget: Identifiable {
    let id = UUID()
    var overrideID: String?
}

private struct EditTarget: Identifiable {
    let id = UUID()
    var binding: GestureBinding
    var isNew: Bool
    /// Bundle id of the app override being edited, or nil for the profile itself.
    var overrideID: String?
}

/// One sheet at a time. Two separate sheet modifiers on one view can leave a menu choice doing nothing.
private enum ActiveSheet: Identifiable {
    case edit(EditTarget)
    case rhythm(RhythmTarget)

    var id: UUID {
        switch self {
        case .edit(let target): return target.id
        case .rhythm(let target): return target.id
        }
    }
}

struct GesturesView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine
    let goToZones: () -> Void

    @State private var sheet: ActiveSheet?

    private var profile: Profile { store.config.activeProfile }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Gestures",
                subtitle: "Profile: \(profile.name). Tap your Mac, and the matching action runs."
            )

            if store.config.isDryRun() {
                Notice(style: .info, text: "Test mode is on. Gestures show up in Activity, but nothing runs yet. You can end it in General.")
            }

            Card(padding: 8) {
                VStack(spacing: 0) {
                    if profile.bindings.isEmpty {
                        Text("No gestures yet. Add one below.")
                            .foregroundStyle(Theme.secondary)
                            .padding(16)
                    }
                    ForEach(sorted(profile.bindings)) { binding in
                        BindingRow(binding: binding) {
                            sheet = .edit(EditTarget(binding: binding, isNew: false, overrideID: nil))
                        }
                        if binding.id != sorted(profile.bindings).last?.id {
                            Divider().overlay(Theme.stroke).padding(.horizontal, 8)
                        }
                    }
                }
            }
            addRow(overrideID: nil)

            macrosSection

            overridesSection
        }
        .sheet(item: $sheet) { active in
            switch active {
            case .edit(let item):
                BindingEditor(
                    binding: item.binding,
                    isNew: item.isNew,
                    siblings: siblings(for: item.overrideID),
                    onSave: { save($0, overrideID: item.overrideID) },
                    onDelete: item.isNew ? nil : { delete(item.binding.id, overrideID: item.overrideID) }
                )
                .environmentObject(store)
                .environmentObject(monitor)
                .environmentObject(engine)
            case .rhythm(let destination):
                RhythmRecorderSheet { pattern in
                    // Opening the editor while the recorder is still closing makes macOS drop it, so wait a moment.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        let binding = GestureBinding(
                            key: GestureKey(taps: pattern.taps),
                            rhythm: pattern,
                            steps: [ActionStep(actionId: "none")]
                        )
                        sheet = .edit(EditTarget(binding: binding, isNew: true, overrideID: destination.overrideID))
                    }
                }
                .environmentObject(store)
                .environmentObject(monitor)
                .environmentObject(engine)
            }
        }
    }

    // MARK: Per-app section

    private var overridesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "App-specific gestures")
            Text("In these apps, the gestures below replace the ones above. Anything you do not set here falls back to the profile.")
                .font(.callout)
                .foregroundStyle(Theme.secondary)

            ForEach(profile.appOverrides) { appOverride in
                Card(padding: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(appOverride.appName).font(.headline).foregroundStyle(Theme.text)
                            Spacer()
                            Button("Remove app") { removeOverride(appOverride.id) }
                                .buttonStyle(.quiet)
                        }
                        .padding(8)
                        ForEach(sorted(appOverride.bindings)) { binding in
                            Divider().overlay(Theme.stroke).padding(.horizontal, 8)
                            BindingRow(binding: binding) {
                                sheet = .edit(EditTarget(binding: binding, isNew: false, overrideID: appOverride.id))
                            }
                        }
                        Divider().overlay(Theme.stroke).padding(.horizontal, 8)
                        addRow(overrideID: appOverride.id).padding(8)
                    }
                }
            }

            Button {
                chooseApp()
            } label: {
                Label("Add an app", systemImage: "plus.app")
            }
            .buttonStyle(.pill)
        }
    }

    // MARK: Adding

    /// Plain tap counts in a menu, and the two special kinds of gesture as buttons of their own,
    /// so nothing important hides inside a submenu.
    private func addRow(overrideID: String?) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(1...5, id: \.self) { count in
                    Button(Describe.taps(count)) {
                        let binding = GestureBinding(key: GestureKey(taps: count), steps: [ActionStep(actionId: "none")])
                        sheet = .edit(EditTarget(binding: binding, isNew: true, overrideID: overrideID))
                    }
                }
            } label: {
                Label("Add a gesture", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                sheet = .rhythm(RhythmTarget(overrideID: overrideID))
            } label: {
                Label("Record a tap rhythm", systemImage: "waveform.path")
            }
            .buttonStyle(.pill)
            .disabled(!monitor.isMonitoring)
            .help(monitor.isMonitoring ? "Tap a pattern three times and give it its own action" : "Resume monitoring to record a rhythm")

            if overrideID != nil {
                Menu {
                    ForEach(WorkflowTemplates.all) { template in
                        Button(template.title) {
                            sheet = .edit(EditTarget(binding: template.make(), isNew: true, overrideID: overrideID))
                        }
                    }
                } label: {
                    Label("Bango macro", systemImage: "wand.and.stars")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: Bango macros

    private var macrosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionLabel(text: "Bango macros")
                Text("Smart gestures")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.18))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }
            Text("A Bango macro is a gesture that does different things depending on the situation: the time of day, the app in front, the battery, or whether the Mac just started. Start from a ready-made one and change it to yours.")
                .font(.callout)
                .foregroundStyle(Theme.secondary)

            ForEach(WorkflowTemplates.all) { template in
                Card(padding: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(symbol: "wand.and.stars")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(template.detail).font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Use this") {
                            sheet = .edit(EditTarget(binding: template.make(), isNew: true, overrideID: nil))
                        }
                        .buttonStyle(.pill)
                    }
                }
            }

            Button {
                let blank = GestureBinding(
                    key: GestureKey(taps: 2),
                    steps: [ActionStep(actionId: "none")],
                    workflow: Workflow(branches: [
                        WorkflowBranch(conditions: [WorkflowCondition(kind: .justStarted)], steps: [ActionStep(actionId: "none")]),
                    ])
                )
                sheet = .edit(EditTarget(binding: blank, isNew: true, overrideID: nil))
            } label: {
                Label("Build your own Bango macro", systemImage: "plus")
            }
            .buttonStyle(.pillPrimary)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }

        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        store.update { config in
            config.updateActiveProfile { profile in
                guard !profile.appOverrides.contains(where: { $0.id == bundleID }) else { return }
                profile.appOverrides.append(AppOverride(id: bundleID, appName: name))
            }
        }
    }

    // MARK: Saving

    private func sorted(_ bindings: [GestureBinding]) -> [GestureBinding] {
        bindings.sorted { a, b in
            if a.taps != b.taps { return a.taps < b.taps }
            return (a.rhythm == nil ? 0 : 1) < (b.rhythm == nil ? 0 : 1)
        }
    }

    private func siblings(for overrideID: String?) -> [GestureBinding] {
        if let overrideID, let found = profile.appOverrides.first(where: { $0.id == overrideID }) {
            return found.bindings
        }
        return profile.bindings
    }

    private func save(_ binding: GestureBinding, overrideID: String?) {
        store.update { config in
            config.updateActiveProfile { profile in
                if let overrideID, let index = profile.appOverrides.firstIndex(where: { $0.id == overrideID }) {
                    Self.upsert(&profile.appOverrides[index].bindings, binding)
                } else {
                    Self.upsert(&profile.bindings, binding)
                }
            }
        }
    }

    private func delete(_ id: String, overrideID: String?) {
        store.update { config in
            config.updateActiveProfile { profile in
                if let overrideID, let index = profile.appOverrides.firstIndex(where: { $0.id == overrideID }) {
                    profile.appOverrides[index].bindings.removeAll { $0.id == id }
                } else {
                    profile.bindings.removeAll { $0.id == id }
                }
            }
        }
    }

    private func removeOverride(_ id: String) {
        store.update { config in
            config.updateActiveProfile { $0.appOverrides.removeAll { $0.id == id } }
        }
    }

    private static func upsert(_ list: inout [GestureBinding], _ binding: GestureBinding) {
        if let index = list.firstIndex(where: { $0.id == binding.id }) {
            list[index] = binding
        } else {
            list.append(binding)
        }
    }
}

private struct BindingRow: View {
    let binding: GestureBinding
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 12) {
                IconBadge(symbol: Describe.symbol(for: binding))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Describe.key(binding.key, rhythm: binding.rhythm))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.text)
                    Text(Describe.summary(of: binding))
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !SafetyPolicy.isAllowed(binding) {
                    Label("Needs confirmation", systemImage: "exclamationmark.shield")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
