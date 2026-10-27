import SwiftUI
import TapCore

/// Permissions one screen at a time: what it is for, one button, and it moves on by itself once macOS says yes.
/// The full list in Setup stays for people who want to see everything at once.
struct PermissionWizard: View {
    @ObservedObject private var center = PermissionCenter.shared
    let onFinish: () -> Void

    private enum Page: Int, CaseIterable {
        case accessibility, screenRecording, dictation, loginItem, done

        var items: [SetupItem] {
            switch self {
            case .accessibility: return [.accessibility]
            case .screenRecording: return [.screenRecording]
            case .dictation: return [.microphone, .speechRecognition]
            case .loginItem: return [.loginItem]
            case .done: return []
            }
        }

        var symbol: String {
            switch self {
            case .accessibility: return "hand.tap.fill"
            case .screenRecording: return "camera.viewfinder"
            case .dictation: return "mic.fill"
            case .loginItem: return "power.circle.fill"
            case .done: return "checkmark.seal.fill"
            }
        }

        var title: String {
            switch self {
            case .accessibility: return "Let Bango press keys for you"
            case .screenRecording: return "Let Bango take screenshots"
            case .dictation: return "Let Bango hear you"
            case .loginItem: return "Start Bango with your Mac"
            case .done: return "You are all set"
            }
        }

        var why: String {
            switch self {
            case .accessibility:
                return "This is what turns a tap into copy, paste, volume, media keys, lock screen and more. Without it most actions cannot run."
            case .screenRecording:
                return "Needed only for the screenshot actions. macOS applies it after Bango restarts once, and Bango will offer that for you."
            case .dictation:
                return "Double tap, talk, and the words are typed for you. The microphone is on only between the two double taps, and speech is recognised on this Mac."
            case .loginItem:
                return "So your taps keep working after a restart, without opening Bango yourself."
            case .done:
                return "Anything you skipped can be allowed later in Setup."
            }
        }

        var buttonTitle: String {
            switch self {
            case .accessibility: return "Allow Accessibility"
            case .screenRecording: return "Allow Screen Recording"
            case .dictation: return "Allow Microphone and Speech"
            case .loginItem: return "Open at login"
            case .done: return "Finish"
            }
        }

        var settingsHint: String? {
            switch self {
            case .accessibility:
                return "System Settings opens next. Switch Bango on in the list."
            case .screenRecording:
                return "System Settings opens next. Switch Bango on in the list."
            case .dictation:
                return "macOS asks twice, once for the microphone and once for speech."
            case .loginItem:
                return nil
            case .done:
                return nil
            }
        }
    }

    @State private var page: Page = .accessibility
    @State private var advancing = false
    @State private var waitingSince: Date?
    @State private var positioned = false

    private let steps: [Page] = [.accessibility, .screenRecording, .dictation, .loginItem]

    var body: some View {
        VStack(spacing: 22) {
            progress
            Spacer(minLength: 0)
            pageBody
                .id(page)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
        .animation(.easeInOut(duration: 0.3), value: page)
        .task {
            center.refreshQuick()
            if !positioned {
                positioned = true
                page = firstUnfinished()
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                center.refreshQuick()
                await advanceIfDone()
            }
        }
    }

    // MARK: - Pieces

    private var progress: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(steps, id: \.rawValue) { step in
                    Capsule()
                        .fill(color(for: step))
                        .frame(width: 34, height: 4)
                }
            }
            if page != .done {
                Text("Step \(page.rawValue + 1) of \(steps.count)")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func color(for step: Page) -> Color {
        if step == page { return Theme.accent }
        return isDone(step) ? Theme.good : Theme.surfaceRaised
    }

    @ViewBuilder
    private var pageBody: some View {
        if page == .done {
            donePage
        } else {
            stepPage(page)
        }
    }

    private func stepPage(_ p: Page) -> some View {
        let finished = isDone(p)
        return VStack(spacing: 18) {
            icon(p.symbol, finished: finished)

            VStack(spacing: 8) {
                Text(p.title).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                Text(p.why)
                    .font(.callout).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            statusArea(p, finished: finished)

            HStack(spacing: 10) {
                if !finished {
                    Button("Not now") { move(to: next(after: p)) }.buttonStyle(.pill)
                    Button(p.buttonTitle) { allow(p) }
                        .buttonStyle(.pillPrimary)
                        .disabled(center.isRunning)
                } else {
                    Button("Continue") { move(to: next(after: p)) }.buttonStyle(.pillPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func statusArea(_ p: Page, finished: Bool) -> some View {
        if finished {
            Label(p == .screenRecording && center.state(.screenRecording) == .needsRestart ? "Allowed. Restart needed" : "Allowed",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.good)
                .font(.callout.weight(.medium))
        } else if center.isRunning, center.current.map({ p.items.contains($0) }) ?? false {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you in System Settings…").font(.callout).foregroundStyle(Theme.secondary)
                }
                if let since = waitingSince, Date().timeIntervalSince(since) > 15, p == .accessibility {
                    Text("Switched on but nothing changes? Select Bango in the list, press the minus button to remove it, then add it again with the plus button.")
                        .font(.caption).foregroundStyle(Theme.warning)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
        } else if let hint = p.settingsHint {
            Text(hint).font(.caption).foregroundStyle(Theme.secondary)
        }
        if let note = center.note, !finished {
            Text(note).font(.caption).foregroundStyle(Theme.warning)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    private var donePage: some View {
        VStack(spacing: 18) {
            icon(Page.done.symbol, finished: true)
            Text(Page.done.title).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
            Text(Page.done.why).font(.callout).foregroundStyle(Theme.secondary)

            Card {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.rawValue) { index, step in
                        if index > 0 { Divider().overlay(Theme.stroke) }
                        HStack(spacing: 10) {
                            Image(systemName: isDone(step) ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(isDone(step) ? Theme.good : Theme.secondary)
                            Text(step.title).foregroundStyle(Theme.text)
                            Spacer()
                            if !isDone(step) {
                                Button("Allow") { page = step }.buttonStyle(.pill)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .frame(maxWidth: 440)

            HStack(spacing: 10) {
                if center.needsRestart {
                    Button("Restart Bango") { center.restartApp() }.buttonStyle(.pillPrimary)
                } else {
                    Button(Page.done.buttonTitle) { onFinish() }.buttonStyle(.pillPrimary)
                }
            }
        }
    }

    private func icon(_ symbol: String, finished: Bool) -> some View {
        ZStack {
            Circle()
                .fill(finished ? Theme.good.opacity(0.14) : Theme.accentSoft)
                .frame(width: 96, height: 96)
            Image(systemName: finished && symbol != Page.done.symbol ? "checkmark" : symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(finished ? Theme.good : Theme.accent)
        }
    }

    // MARK: - Flow

    private func isDone(_ p: Page) -> Bool {
        switch p {
        case .accessibility:
            return center.state(.accessibility) == .granted
        case .screenRecording:
            let state = center.state(.screenRecording)
            return state == .granted || state == .needsRestart
        case .dictation:
            return center.state(.microphone) == .granted && center.state(.speechRecognition) == .granted
        case .loginItem:
            let state = center.state(.loginItem)
            return state == .granted || state == .unavailable
        case .done:
            return false
        }
    }

    private func firstUnfinished() -> Page {
        steps.first { !isDone($0) } ?? .done
    }

    private func next(after p: Page) -> Page {
        Page(rawValue: p.rawValue + 1) ?? .done
    }

    private func move(to target: Page) {
        waitingSince = nil
        page = target
    }

    private func allow(_ p: Page) {
        waitingSince = Date()
        Task {
            await center.setUp(p.items)
            await advanceIfDone()
        }
    }

    /// Once the current permission is allowed, show the check for a moment and move on by itself.
    private func advanceIfDone() async {
        guard page != .done, isDone(page), !advancing else { return }
        advancing = true
        try? await Task.sleep(nanoseconds: 900_000_000)
        if page != .done, isDone(page) { move(to: next(after: page)) }
        advancing = false
    }
}
