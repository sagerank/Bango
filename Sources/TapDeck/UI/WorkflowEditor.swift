import AppKit
import SwiftUI
import TapCore
import UniformTypeIdentifiers

/// Picks an installed app and returns its bundle identifier and name.
enum AppChooser {
    @MainActor
    static func pick() -> (bundleID: String, name: String)? {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return (id, name)
    }
}

/// "Choose what runs with if and else": branches of conditions and actions, and a way to check them against right now.
struct WorkflowCard: View {
    @Binding var workflow: Workflow?
    /// The gesture's own actions, which are the "otherwise".
    let otherwise: [ActionStep]

    @State private var checkResult: String?

    private var branches: Binding<[WorkflowBranch]> {
        Binding(get: { workflow?.branches ?? [] }, set: { workflow?.branches = $0 })
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { workflow != nil },
                    set: { on in
                        checkResult = nil
                        workflow = on ? Workflow(branches: [Self.newBranch()]) : nil
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bingo macro: choose what runs with if and else").foregroundStyle(Theme.text)
                        Text("Run different actions depending on the time, the app in front, the battery, whether the Mac just started, and more.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }

                if workflow != nil {
                    ForEach(branches) { $branch in
                        BranchEditor(
                            branch: $branch,
                            number: (branches.wrappedValue.firstIndex(where: { $0.id == branch.id }) ?? 0) + 1,
                            remove: {
                                branches.wrappedValue.removeAll { $0.id == branch.id }
                                checkResult = nil
                            }
                        )
                    }

                    Button {
                        branches.wrappedValue.append(Self.newBranch())
                    } label: {
                        Label("Add another \"if\"", systemImage: "plus")
                    }
                    .buttonStyle(.quiet)

                    if let problems = workflow?.problems, !problems.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(problems, id: \.self) { problem in
                                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warning)
                            }
                        }
                    }

                    Divider().overlay(Theme.stroke)
                    HStack {
                        Button("Check against right now") { check() }.buttonStyle(.pill)
                        Spacer()
                    }
                    if let checkResult {
                        Text(checkResult).font(.callout).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private static func newBranch() -> WorkflowBranch {
        WorkflowBranch(conditions: [WorkflowCondition(kind: .justStarted)], steps: [ActionStep(actionId: "none")])
    }

    /// Shows what this gesture would do at this very moment, and the facts it decided on.
    private func check() {
        let context = SystemSnapshot.capture(frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        let probe = GestureBinding(key: GestureKey(taps: 1), steps: otherwise, workflow: workflow)
        let result = probe.resolvedSteps(in: context)
        let facts = SystemSnapshot.facts(context)
        if let number = result.branchNumber {
            checkResult = "Right now \"if \(number)\" matches (\(result.branchSummary ?? "")). It would run: \(Describe.chain(result.steps.filter { $0.enabled })).\nBecause: \(facts)."
        } else {
            checkResult = "Right now no condition is met, so the otherwise actions would run: \(Describe.chain(otherwise.filter { $0.enabled })).\nBecause: \(facts)."
        }
    }
}

private struct BranchEditor: View {
    @Binding var branch: WorkflowBranch
    let number: Int
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(number == 1 ? "IF" : "ELSE IF")
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                if branch.conditions.count > 1 {
                    Picker("", selection: $branch.match) {
                        ForEach(WorkflowBranch.Match.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Spacer()
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.buttonStyle(.quiet)
            }

            ForEach($branch.conditions) { $condition in
                ConditionRow(condition: $condition) {
                    branch.conditions.removeAll { $0.id == condition.id }
                }
            }
            Menu {
                ForEach(WorkflowCondition.Kind.allCases, id: \.self) { kind in
                    Button(kind.title) { branch.conditions.append(WorkflowCondition(kind: kind)) }
                }
            } label: {
                Label("Add a condition", systemImage: "plus")
            }
            .menuStyle(.borderlessButton).fixedSize()

            Text("THEN").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
            StepsEditor(steps: $branch.steps)
        }
        .padding(12)
        .background(Theme.surfaceRaised.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ConditionRow: View {
    @Binding var condition: WorkflowCondition
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Picker("", selection: $condition.kind) {
                    ForEach(WorkflowCondition.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                .onChange(of: condition.kind) { _, _ in condition.negate = false }
                details
                Spacer(minLength: 0)
                Button(action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.quiet)
            }
            if let problem = condition.problem {
                Text(problem).font(.caption).foregroundStyle(Theme.warning)
            } else {
                Text(condition.summary.prefix(1).uppercased() + condition.summary.dropFirst())
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        switch condition.kind {
        case .justStarted:
            Picker("", selection: $condition.negate) {
                Text("less than").tag(false)
                Text("more than").tag(true)
            }.labelsHidden().fixedSize()
            Stepper(value: $condition.number, in: 1...1440, step: 5) { Text("\(Int(condition.number)) min ago") }.fixedSize()
        case .frontApp, .appRunning:
            Picker("", selection: $condition.negate) {
                Text(condition.kind == .frontApp ? "is" : "is running").tag(false)
                Text(condition.kind == .frontApp ? "is not" : "is not running").tag(true)
            }.labelsHidden().fixedSize()
            Button(condition.label.isEmpty ? "Choose app…" : condition.label) {
                if let picked = AppChooser.pick() {
                    condition.value = picked.bundleID
                    condition.label = picked.name
                }
            }.buttonStyle(.pill)
        case .timeBetween:
            Picker("", selection: $condition.negate) {
                Text("between").tag(false)
                Text("not between").tag(true)
            }.labelsHidden().fixedSize()
            DatePicker("", selection: timeBinding($condition.from), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
            Text("and")
            DatePicker("", selection: timeBinding($condition.to), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
        case .weekday:
            HStack(spacing: 4) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { index, letter in
                    let day = index + 1
                    let on = condition.days.contains(day)
                    Button(letter) {
                        if on { condition.days.removeAll { $0 == day } } else { condition.days.append(day) }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .background(on ? Theme.accent : Theme.surfaceRaised)
                    .foregroundStyle(on ? Color.black : Theme.text)
                    .clipShape(Circle())
                }
            }
        case .onBattery:
            Picker("", selection: $condition.negate) {
                Text("On battery").tag(false)
                Text("Plugged in").tag(true)
            }.labelsHidden().fixedSize()
        case .batteryBelow:
            Picker("", selection: $condition.negate) {
                Text("below").tag(false)
                Text("at or above").tag(true)
            }.labelsHidden().fixedSize()
            Stepper(value: $condition.number, in: 5...95, step: 5) { Text("\(Int(condition.number))%") }.fixedSize()
        case .externalDisplay:
            Picker("", selection: $condition.negate) {
                Text("is connected").tag(false)
                Text("is not connected").tag(true)
            }.labelsHidden().fixedSize()
        }
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
