import AppKit
import SwiftUI
import TapCore

enum DashboardSection: String, CaseIterable, Identifiable {
    case setup, gestures, profiles, desk, tuning, zones, activity, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: return "Setup"
        case .gestures: return "Gestures"
        case .profiles: return "Profiles"
        case .desk: return "Desk"
        case .tuning: return "Tuning"
        case .zones: return "Zones & rhythm"
        case .activity: return "Activity"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .setup: return "checkmark.shield"
        case .gestures: return "hand.tap"
        case .profiles: return "person.2"
        case .desk: return "macwindow.on.rectangle"
        case .tuning: return "slider.horizontal.3"
        case .zones: return "square.split.2x2"
        case .activity: return "list.bullet.rectangle"
        case .general: return "gearshape"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ConfigStore
    @State private var selection: DashboardSection = .gestures
    @State private var showOnboarding = false
    @State private var onboardingStartsAtPermissions = false
    @ObservedObject private var permissions = PermissionCenter.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.stroke)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detail
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
        }
        .frame(minWidth: 860, minHeight: 720)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .background(
            WindowObserver { window in
                model.mainWindow = window
                let done = store.config.hasCompletedOnboarding
                let needsSetup = permissions.needsSetupAtLaunch(onboardingDone: done)
                if !needsSetup, done, !model.userRequestedWindow {
                    // Started at login with nothing to set up: stay out of the way until the user opens the window.
                    window.orderOut(nil)
                } else {
                    if needsSetup {
                        // First run gets the welcome tour. Anyone else is only taken to the Setup page,
                        // once per build, and nothing is requested until they press a button.
                        selection = .setup
                        if !done { showOnboarding = true }
                        permissions.markSetupSeen()
                    }
                    model.showMainWindow()
                }
            }
        )
        .task {
            // Keeps the Setup badge honest while the window is open.
            while !Task.isCancelled {
                permissions.refreshQuick()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(startAtPermissions: onboardingStartsAtPermissions)
                .environmentObject(model)
                .environmentObject(store)
                .environmentObject(model.monitor)
                .environmentObject(model.engine)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BANGO.")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Theme.text)
                Text("Tweak with the banger.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.bottom, 22)

            ForEach(DashboardSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.symbol).frame(width: 18)
                        Text(section.title)
                        Spacer()
                        if section == .setup && permissions.needsAttention {
                            Circle().fill(Theme.warning).frame(width: 8, height: 8)
                        }
                    }
                    .font(.callout.weight(selection == section ? .semibold : .regular))
                    .foregroundStyle(selection == section ? Theme.text : Theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(selection == section ? Theme.surfaceRaised : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            statusFooter
        }
        .padding(16)
        .frame(width: 200)
        .background(Theme.surface)
    }

    private var statusFooter: some View {
        StatusFooter()
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .setup: SetupView(showTour: { onboardingStartsAtPermissions = false; showOnboarding = true })
        case .gestures: GesturesView(goToZones: { selection = .zones })
        case .profiles: ProfilesView()
        case .desk: DeskView()
        case .tuning: TuningView()
        case .zones: ZonesRhythmView()
        case .activity: ActivityView()
        case .general: GeneralView(showOnboarding: { showOnboarding = true })
        }
    }
}

private struct StatusFooter: View {
    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var store: ConfigStore

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
        }
    }

    private var color: Color {
        if !monitor.isSupported { return Theme.danger }
        if !monitor.isMonitoring { return Theme.warning }
        return store.config.isDryRun() ? Theme.accent : Theme.good
    }

    private var label: String {
        if !monitor.isSupported { return "Sensor unavailable" }
        if !monitor.isMonitoring { return "Paused" }
        return store.config.isDryRun() ? "Listening, test mode" : "Listening"
    }
}
