import AppKit
import SwiftUI
import TapCore

struct GeneralView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var updater: AppUpdater

    let showOnboarding: () -> Void

    @State private var loginRefresh = 0
    @State private var loginError: String?
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "General")

            startupCard
            testModeCard
            permissionsCard
            hardwareCard
            if updater.isAvailable { updatesCard }
            aboutCard
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) { store.resetEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Gestures, profiles, calibration and zones go back to how they were on first launch.")
        }
    }

    // MARK: Cards

    private var startupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Startup and feedback")

                Toggle(isOn: Binding(
                    get: { _ = loginRefresh; return LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval },
                    set: { setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open TapDeck at login").foregroundStyle(Theme.text)
                        Text(LaunchAtLogin.isAvailable ? "Runs quietly in the menu bar." : "Available in the installed app, not when run from the command line.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                .disabled(!LaunchAtLogin.isAvailable)

                if LaunchAtLogin.needsApproval {
                    Notice(style: .warning, text: "macOS needs you to approve TapDeck in System Settings, Login Items.")
                    Button("Open Login Items") { LaunchAtLogin.openLoginItemsSettings() }.buttonStyle(.pill)
                }
                if let loginError {
                    Notice(style: .danger, text: loginError)
                }

                Toggle(isOn: Binding(
                    get: { store.config.showHUD },
                    set: { value in store.update { $0.showHUD = value } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show a small confirmation").foregroundStyle(Theme.text)
                        Text("A brief message near the bottom of the screen after each gesture.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private var testModeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Test mode")
                if let end = store.config.dryRunEndsAt, store.config.isDryRun() {
                    Text("On until \(end.formatted(date: .abbreviated, time: .shortened)). Gestures are recognized and listed in Activity, but no action runs.")
                        .foregroundStyle(Theme.text)
                    Button("Turn off test mode") { store.update { $0.endDryRun() } }
                        .buttonStyle(.pillPrimary)
                } else {
                    Text("Try a new setup safely. For 24 hours, gestures are recognized and listed in Activity, but nothing runs. Handy for checking that normal typing and typing on the couch do not trigger anything.")
                        .foregroundStyle(Theme.text)
                    Button("Start test mode for 24 hours") { store.update { $0.startDryRun() } }
                        .buttonStyle(.pill)
                }
            }
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Permissions")
            PermissionsPanel()
        }
    }

    private var hardwareCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "This Mac")
                statusLine("Accelerometer", ok: monitor.isSupported && monitor.isMonitoring, note: monitor.isSupported ? nil : monitor.statusMessage)
                statusLine("Gyroscope", ok: monitor.hasGyroscope, note: monitor.hasGyroscope ? nil : "Not found. Tap zones may be less reliable.")
                Text("TapDeck reads the motion sensors inside Apple Silicon MacBooks. Macs with Intel chips, desktop Macs and some base models may not expose them.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func statusLine(_ title: String, ok: Bool, note: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Theme.good : Theme.warning)
            Text(title).foregroundStyle(Theme.text)
            if let note {
                Text(note).font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var updatesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Updates")
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                ))
                Button(updater.availableVersion.map { "Update available: v\($0)" } ?? "Check now") {
                    updater.checkForUpdates()
                }
                .buttonStyle(.pill)
                .disabled(!updater.canCheckForUpdates)
            }
        }
    }

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "About")
                Text("TapDeck \(AppInfo.version)").foregroundStyle(Theme.text)
                Text("Free and open source under the MIT license. TapDeck sends nothing anywhere: no analytics, no accounts, no network use apart from update checks when enabled.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                if let url = URL(string: AppInfo.repositoryURL) {
                    Link("Source code, license and issues", destination: url)
                }
                HStack {
                    Button("Show the welcome tour") { showOnboarding() }.buttonStyle(.pill)
                    Button("Reset all settings") { confirmReset = true }.buttonStyle(.pillDestructive)
                }
            }
        }
    }

    // MARK: Actions

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription)"
        }
        loginRefresh += 1
    }
}
