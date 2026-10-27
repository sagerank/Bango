import SwiftUI
import TapCore

/// Saved window layouts: where your windows are, put back with one gesture.
struct DeskView: View {
    @EnvironmentObject private var store: ConfigStore
    @ObservedObject private var permissions = PermissionCenter.shared

    @State private var newName = "Desk"
    @State private var message: String?
    @State private var applying: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Desk",
                subtitle: "Save where your windows are, then put them back with one gesture, for example two knocks after a restart."
            )

            if permissions.state(.accessibility) != .granted {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Notice(style: .warning, text: "Moving windows needs the Accessibility permission. You can save layouts without it, but they will not be applied.")
                        Button("Allow Accessibility") { Task { await permissions.setUp([.accessibility]) } }.buttonStyle(.pillPrimary)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Save my windows")
                    Text("Arrange your apps the way you like them, then save. Every app with a visible window is remembered with its place on its screen.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                    HStack {
                        TextField("Name", text: $newName).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                        Button("Save current windows") { save() }
                            .buttonStyle(.pillPrimary)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            if let message {
                Notice(style: .info, text: message)
            }

            ForEach(store.config.layouts) { layout in
                layoutCard(layout)
            }

            Text("Limits: macOS gives apps no way to switch desktops (Spaces) or change how your screens are arranged, so layouts place windows on the screens you have. Full-screen windows and apps that do not allow moving are skipped, and the result says which.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    private func layoutCard(_ layout: DeskLayout) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Name", text: nameBinding(layout.id)).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    Spacer()
                    Button(applying == layout.id ? "Applying…" : "Apply now") { apply(layout) }
                        .buttonStyle(.pillPrimary)
                        .disabled(applying != nil || permissions.state(.accessibility) != .granted)
                }
                ForEach(layout.entries) { entry in
                    HStack {
                        Text(entry.appName).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(Int(entry.fractions.width * 100))% × \(Int(entry.fractions.height * 100))%\(entry.display > 0 ? " · screen \(entry.display + 1)" : "")")
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                    }
                }
                if layout.entries.isEmpty {
                    Text("No windows were found when this was saved.").font(.caption).foregroundStyle(Theme.warning)
                }
                HStack {
                    Button("Update from current windows") { update(layout) }.buttonStyle(.pill)
                    Button("Delete") { delete(layout) }.buttonStyle(.pillDestructive)
                }
                Text("Use it in a gesture with the action \"Apply a saved window layout\" and the name \"\(layout.name)\".")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func nameBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { store.config.layouts.first { $0.id == id }?.name ?? "" },
            set: { value in
                store.update { config in
                    if let index = config.layouts.firstIndex(where: { $0.id == id }) { config.layouts[index].name = value }
                }
            }
        )
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let layout = DeskService.captureCurrentLayout(name: name)
        store.update { $0.layouts.append(layout) }
        message = layout.entries.isEmpty
            ? "No windows were found. Open some apps and try again."
            : "Saved \"\(name)\" with \(layout.entries.count) windows."
    }

    private func update(_ layout: DeskLayout) {
        let fresh = DeskService.captureCurrentLayout(name: layout.name)
        store.update { config in
            if let index = config.layouts.firstIndex(where: { $0.id == layout.id }) { config.layouts[index].entries = fresh.entries }
        }
        message = "Updated \"\(layout.name)\" with \(fresh.entries.count) windows."
    }

    private func delete(_ layout: DeskLayout) {
        store.update { $0.layouts.removeAll { $0.id == layout.id } }
    }

    private func apply(_ layout: DeskLayout) {
        applying = layout.id
        Task {
            let result = await DeskService.apply(layout)
            message = result
            applying = nil
        }
    }
}
