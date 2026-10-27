import AppKit
import SwiftUI
import TapCore
import UniformTypeIdentifiers

struct ProfilesView: View {
    @EnvironmentObject private var store: ConfigStore
    @State private var message: (style: Notice.Style, text: String)?
    @State private var pendingDelete: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Profiles",
                subtitle: "A profile is a full set of gestures. Switch profiles from the menu bar."
            )

            if let message {
                Notice(style: message.style, text: message.text)
            }

            VStack(spacing: 10) {
                ForEach(store.config.profiles) { profile in
                    row(for: profile)
                }
            }

            HStack(spacing: 10) {
                Button { addProfile() } label: { Label("New profile", systemImage: "plus") }
                    .buttonStyle(.pillPrimary)
                Button { importProfile() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.pill)
                Button { addStarters() } label: { Label("Add starter profiles", systemImage: "sparkles") }
                    .buttonStyle(.pill)
            }

            Notice(
                style: .info,
                text: "Imported profiles never run code on their own. Actions that run commands or open links arrive switched off, and you turn them on yourself."
            )
        }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let profile = pendingDelete { delete(profile) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func row(for profile: Profile) -> some View {
        let isActive = profile.id == store.config.activeProfileID
        return Card {
            HStack(spacing: 12) {
                Button {
                    store.update { $0.activeProfileID = profile.id }
                } label: {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isActive ? Theme.accent : Theme.secondary)
                }
                .buttonStyle(.plain)
                .help(isActive ? "This profile is in use" : "Use this profile")

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: nameBinding(for: profile.id))
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text("\(profile.bindings.count) gestures" + (profile.appOverrides.isEmpty ? "" : ", \(profile.appOverrides.count) apps"))
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("Duplicate") { duplicate(profile) }.buttonStyle(.quiet)
                Button("Export") { export(profile) }.buttonStyle(.quiet)
                Button("Delete") { pendingDelete = profile }
                    .buttonStyle(.quiet)
                    .disabled(store.config.profiles.count <= 1)
            }
        }
    }

    private func nameBinding(for id: String) -> Binding<String> {
        Binding(
            get: { store.config.profiles.first(where: { $0.id == id })?.name ?? "" },
            set: { newName in
                store.update { config in
                    if let index = config.profiles.firstIndex(where: { $0.id == id }) {
                        config.profiles[index].name = newName
                    }
                }
            }
        )
    }

    private func addProfile() {
        let profile = Profile(name: "New profile", bindings: [
            GestureBinding(key: GestureKey(taps: 1), steps: [ActionStep(actionId: "play-pause")]),
        ])
        store.update {
            $0.profiles.append(profile)
            $0.activeProfileID = profile.id
        }
        message = nil
    }

    private func addStarters() {
        var added: [String] = []
        store.update { added = $0.addMissingStarterProfiles() }
        let text = added.isEmpty
            ? "You already have every starter profile."
            : "Added: \(added.joined(separator: ", "))."
        message = (style: .info, text: text)
    }

    private func duplicate(_ profile: Profile) {
        store.update { $0.profiles.append(profile.duplicated()) }
    }

    private func delete(_ profile: Profile) {
        store.update { config in
            guard config.profiles.count > 1 else { return }
            config.profiles.removeAll { $0.id == profile.id }
            if config.activeProfileID == profile.id {
                config.activeProfileID = config.profiles[0].id
            }
        }
    }

    // MARK: Import and export

    private func export(_ profile: Profile) {
        let panel = NSSavePanel()
        panel.title = "Export profile"
        panel.nameFieldStringValue = "\(profile.name).bingo.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProfileExchange.export(profile).write(to: url, options: .atomic)
            message = (.info, "Exported \"\(profile.name)\".")
        } catch {
            message = (.danger, "Could not export: \(error.localizedDescription)")
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import profile"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let result = try ProfileExchange.importProfile(from: data)
            store.update { $0.profiles.append(result.profile) }
            if result.disabledSteps > 0 {
                message = (.warning, "Imported \"\(result.profile.name)\". \(result.disabledSteps) action(s) that can run commands or open links were switched off. Open Gestures and review them before turning them on.")
            } else {
                message = (.info, "Imported \"\(result.profile.name)\".")
            }
        } catch let error as ExchangeError {
            message = (.danger, error.message)
        } catch {
            message = (.danger, "Could not import: \(error.localizedDescription)")
        }
    }
}
