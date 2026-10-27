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

struct GesturesView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine
    let goToZones: () -> Void

    @State private var target: EditTarget?
    @State private var rhythmFor: RhythmTarget?

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
                            target = EditTarget(binding: binding, isNew: false, overrideID: nil)
                        }
                        if binding.id != sorted(profile.bindings).last?.id {
                            Divider().overlay(Theme.stroke).padding(.horizontal, 8)
                        }
                    }
                }
            }
            addMenu(overrideID: nil)

            overridesSection
        }
        .sheet(item: $target) { item in
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
        }
        .sheet(item: $rhythmFor) { destination in
            RhythmRecorderSheet { pattern in
                // Opening the editor while the recorder is still closing makes macOS drop it, so wait a moment.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    let binding = GestureBinding(
                        key: GestureKey(taps: pattern.taps),
                        rhythm: pattern,
                        steps: [ActionStep(actionId: "none")]
                    )
                    target = EditTarget(binding: binding, isNew: true, overrideID: destination.overrideID)
                }
            }
            .environmentObject(store)
            .environmentObject(monitor)
            .environmentObject(engine)
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
                                target = EditTarget(binding: binding, isNew: false, overrideID: appOverride.id)
                            }
                        }
                        Divider().overlay(Theme.stroke).padding(.horizontal, 8)
                        addMenu(overrideID: appOverride.id).padding(8)
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

    private func addMenu(overrideID: String?) -> some View {
        Menu {
            ForEach(1...5, id: \.self) { count in
                Button(Describe.taps(count)) {
                    let binding = GestureBinding(key: GestureKey(taps: count), steps: [ActionStep(actionId: "none")])
                    target = EditTarget(binding: binding, isNew: true, overrideID: overrideID)
                }
            }
            Divider()
            Button("Tap rhythm…") { rhythmFor = RhythmTarget(overrideID: overrideID) }
            Menu("Workflow from a template") {
                ForEach(WorkflowTemplates.all) { template in
                    Button(template.title) {
                        target = EditTarget(binding: template.make(), isNew: true, overrideID: overrideID)
                    }
                }
            }
        } label: {
            Label("Add a gesture", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
