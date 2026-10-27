import SwiftUI
import TapCore

/// Edits one gesture: what it looks like, and the chain of actions it runs.
struct BindingEditor: View {
    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var monitor: MotionMonitor
    @EnvironmentObject private var engine: Engine
    @State private var draft: GestureBinding
    @State private var showStrengthSetup = false
    private let isNew: Bool
    /// Other bindings in the same list, used to warn about clashes.
    private let siblings: [GestureBinding]
    private let onSave: (GestureBinding) -> Void
    private let onDelete: (() -> Void)?

    init(
        binding: GestureBinding,
        isNew: Bool,
        siblings: [GestureBinding],
        onSave: @escaping (GestureBinding) -> Void,
        onDelete: (() -> Void)?
    ) {
        _draft = State(initialValue: binding)
        self.isNew = isNew
        self.siblings = siblings.filter { $0.id != binding.id }
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var hasZones: Bool { store.config.zoneModel != nil }
    private var hasStrength: Bool { store.config.detector.hardPeak > 0 }

    private var clash: Bool {
        siblings.contains { other in
            other.key == draft.key
                && ((other.rhythm == nil && draft.rhythm == nil) || other.rhythm == draft.rhythm)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(title: isNew ? "New gesture" : "Edit gesture")
                    gestureCard
                    WorkflowCard(workflow: $draft.workflow, otherwise: draft.steps)
                    stepsCard
                    safetyNotice
                    if clash {
                        Notice(style: .warning, text: "Another gesture already uses this exact combination. Only the first one will run.")
                    }
                }
                .padding(24)
            }
            Divider().overlay(Theme.stroke)
            footer
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 640, minHeight: 440, idealHeight: 600, maxHeight: 760)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: Gesture

    private var gestureCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "When I")
                if let rhythm = draft.rhythm {
                    HStack {
                        IconBadge(symbol: "metronome")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tap a rhythm").foregroundStyle(Theme.text)
                            Text(rhythm.summary).font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                } else {
                    Picker("Taps", selection: tapsBinding) {
                        ForEach(1...5, id: \.self) { n in Text("\(n)").tag(n) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Picker("Where", selection: zoneBinding) {
                    ForEach(TapZone.allCases, id: \.self) { zone in Text(zone.title).tag(zone) }
                }
                .pickerStyle(.segmented)
                .disabled(!hasZones && draft.key.zone == .any)
                if !hasZones {
                    Text("Left, right and top taps need a one-time setup in Zones & rhythm.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }

                Picker("How hard", selection: strengthBinding) {
                    ForEach(TapStrength.allCases, id: \.self) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.segmented)
                if !hasStrength {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(draft.key.strength == .any
                             ? "Soft and hard taps need a one-time teach-in: a few light taps and a few firm ones."
                             : "This gesture will not fire until TapDeck has learned your soft and hard taps.")
                            .font(.caption).foregroundStyle(draft.key.strength == .any ? Theme.secondary : Theme.warning)
                        Button("Teach soft and hard taps…") { showStrengthSetup = true }.buttonStyle(.pill)
                    }
                }
            }
        }
        .sheet(isPresented: $showStrengthSetup) {
            CalibrationSheet(teachStrength: true)
                .environmentObject(store)
                .environmentObject(monitor)
                .environmentObject(engine)
        }
    }

    private var tapsBinding: Binding<Int> {
        Binding(get: { draft.key.taps }, set: { draft.key.taps = $0 })
    }

    private var zoneBinding: Binding<TapZone> {
        Binding(get: { draft.key.zone }, set: { draft.key.zone = $0 })
    }

    private var strengthBinding: Binding<TapStrength> {
        Binding(get: { draft.key.strength }, set: { draft.key.strength = $0 })
    }

    // MARK: Steps

    private var stepsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: draft.workflow == nil ? "Do" : "Otherwise, when no condition above is met")
                StepsEditor(steps: $draft.steps)
            }
        }
    }

    // MARK: Safety

    @ViewBuilder
    private var safetyNotice: some View {
        if SafetyPolicy.needsAcknowledgement(draft) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Notice(
                        style: .warning,
                        text: "This changes something that is hard to undo, and \(draft.taps) taps can happen by accident. Use \(SafetyPolicy.minTapsForRisky) or more taps, or confirm below."
                    )
                    Toggle("I understand, allow it on \(draft.taps) \(draft.taps == 1 ? "tap" : "taps")", isOn: $draft.acknowledgedRisk)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let onDelete {
                Button("Delete") {
                    onDelete()
                    dismiss()
                }
                .buttonStyle(.pillDestructive)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.pill)
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                onSave(draft)
                dismiss()
            }
            .buttonStyle(.pillPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(draft.allSteps.isEmpty)
        }
        .padding(16)
    }
}

/// A list of actions with add, move and remove. Used for a gesture's own actions and for each branch of a workflow.
struct StepsEditor: View {
    @Binding var steps: [ActionStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach($steps) { $step in
                StepRow(
                    step: $step,
                    canMoveUp: steps.first?.id != step.id,
                    canMoveDown: steps.last?.id != step.id,
                    move: { delta in move(step.id, by: delta) },
                    remove: { steps.removeAll { $0.id == step.id } }
                )
                if steps.last?.id != step.id {
                    Divider().overlay(Theme.stroke)
                }
            }
            Button {
                steps.append(ActionStep(actionId: "none"))
            } label: {
                Label("Add another action", systemImage: "plus")
            }
            .buttonStyle(.quiet)
        }
    }

    private func move(_ id: String, by delta: Int) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
    }
}

// MARK: - One step

private struct StepRow: View {
    @Binding var step: ActionStep
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    private var definition: ActionDefinition? { ActionCatalog.definition(for: step.actionId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ActionMenu(actionId: $step.actionId, parameter: $step.parameter)
                Spacer()
                Toggle("", isOn: $step.enabled).labelsHidden().toggleStyle(.switch)
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.quiet).disabled(!canMoveUp)
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.quiet).disabled(!canMoveDown)
                Button(role: .destructive) { remove() } label: { Image(systemName: "trash") }
                    .buttonStyle(.quiet)
            }

            if let spec = definition?.parameter {
                if spec.choices.isEmpty {
                    TextField(spec.label, text: $step.parameter, prompt: Text(spec.placeholder))
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker(spec.label, selection: $step.parameter) {
                        Text("Choose…").tag("")
                        ForEach(spec.choices, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            HStack(spacing: 12) {
                Stepper(value: $step.delayAfter, in: 0...10, step: 0.5) {
                    Text(step.delayAfter == 0 ? "No pause before the next action" : "Pause \(step.delayAfter.formatted(.number.precision(.fractionLength(1)))) s before the next action")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }

            ForEach(hints, id: \.self) { hint in
                Text(hint).font(.caption).foregroundStyle(Theme.secondary)
            }
            if !step.enabled {
                Text("This action is switched off and will be skipped.")
                    .font(.caption).foregroundStyle(Theme.warning)
            }
        }
    }

    private var hints: [String] {
        guard let definition else { return ["This action is not known to this version of TapDeck."] }
        var out: [String] = []
        switch definition.permission {
        case .accessibility: out.append("Needs the Accessibility permission.")
        case .automation: out.append("Needs the Automation permission.")
        case .screenRecording: out.append("Needs the Screen Recording permission. Pictures are saved to your screenshot folder.")
        case .dictation: out.append("Needs Microphone and Speech Recognition (allow them in Setup). Typing the words into other apps needs Accessibility; without it the words are copied instead.")
        case .none: break
        }
        if let tool = definition.tool { out.append("Needs \(tool), installed with Homebrew.") }
        if definition.runsCode { out.append("Runs on your Mac with your permissions. Only use what you trust.") }
        return out
    }
}

/// Every action in the catalog, in a searchable list. A popover rather than nested menus, because nested
/// menus inside a sheet could not be clicked on some Macs.
struct ActionMenu: View {
    @Binding var actionId: String
    @Binding var parameter: String
    @State private var open = false

    private var current: ActionDefinition? { ActionCatalog.definition(for: actionId) }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: current?.symbol ?? "questionmark")
                Text(current?.name ?? "Unknown action")
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ActionPicker(selected: actionId) { definition in
                if definition.parameter == nil { parameter = "" }
                actionId = definition.id
                open = false
            }
        }
    }
}

private struct ActionPicker: View {
    let selected: String
    let choose: (ActionDefinition) -> Void
    @State private var query = ""

    private func matches(_ definition: ActionDefinition) -> Bool {
        query.isEmpty
            || definition.name.localizedCaseInsensitiveContains(query)
            || definition.category.title.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search actions", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    ForEach(ActionCategory.allCases, id: \.self) { category in
                        let items = ActionCatalog.actions(in: category).filter(matches)
                        if !items.isEmpty {
                            Text(category.title.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                            ForEach(items) { definition in
                                Button { choose(definition) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: definition.symbol).frame(width: 20)
                                        Text(definition.name)
                                        Spacer()
                                        if definition.id == selected {
                                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.text)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .frame(width: 360, height: 420)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }
}
