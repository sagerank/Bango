import AppKit
import SwiftUI
import TapCore

/// A permanent home for setup: what works, what is missing, and one button to fix it.
struct SetupView: View {
    @EnvironmentObject private var monitor: MotionMonitor
    @ObservedObject private var center = PermissionCenter.shared
    let showTour: () -> Void
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var engine: Engine
    @State private var showPractice = false
    @State private var typingTest: String?

    var body: some View {
        content
            .onAppear { center.markSetupSeen() }
            .sheet(isPresented: $showPractice) {
                PracticeSheet()
                    .environmentObject(store)
                    .environmentObject(monitor)
                    .environmentObject(engine)
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Setup",
                subtitle: "Everything TapDeck needs from macOS, in one place. If a tap does nothing, look here first."
            )

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "This Mac")
                    line("Motion sensor", ok: monitor.isSupported && monitor.isMonitoring,
                         note: monitor.isSupported ? nil : monitor.statusMessage)
                    line("Gyroscope", ok: monitor.hasGyroscope,
                         note: monitor.hasGyroscope ? nil : "Not found. Tap zones may be less reliable.")
                    if monitor.snapshot.sampleRate > 0 {
                        Text(String(format: "Sensor rate: %.0f Hz", monitor.snapshot.sampleRate))
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Check that taps work")
                    Text("A guided practice: it shows where to tap and tells you what it heard.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                    Button("Start practice") { showPractice = true }.buttonStyle(.pillPrimary)
                        .disabled(!(monitor.isSupported && monitor.isMonitoring))
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Check that dictation can type")
                    Text("Press the button, then click into a text box in any app within 3 seconds. TapDeck types a short sentence there, the same way dictation does.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                    Button("Type a test sentence in 3 seconds") { runTypingTest() }.buttonStyle(.pill)
                    if let typingTest {
                        Text(typingTest).font(.callout).foregroundStyle(Theme.text)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Permissions")
                PermissionsPanel()
            }

            HStack {
                Button("Show the welcome tour") { showTour() }.buttonStyle(.pill)
                Spacer()
            }
        }
    }

    private func runTypingTest() {
        guard AccessibilityPermission.isTrusted(promptIfNeeded: false) else {
            typingTest = "Allow Accessibility below first. Without it nothing can type."
            return
        }
        typingTest = "Click into a text box in another app now…"
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
                typingTest = "TapDeck was still in front, so nothing was typed. Try again and click into another app."
                return
            }
            let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "the app in front"
            KeyTyper.enqueue(LiveTypist.Edit(insert: "TapDeck typing works. "))
            typingTest = "Typed a test sentence into \(app). If you do not see it there, typing does not work in that app. Tell me which app."
        }
    }

    private func line(_ title: String, ok: Bool, note: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Theme.good : Theme.danger)
            Text(title).foregroundStyle(Theme.text)
            if let note {
                Text(note).font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
    }
}
