//
//  AskSheet.swift
//  DeckHandiOS – Surfaces
//
//  Ask (UX-022, A1), opened from the Ask circle in the tab bar, the Ask
//  field on wide windows, and ⌘K. Board "Ask: a plan before anything runs":
//  the Ask glyph and "Ask <Mac>", an "On device" pill while Apple
//  Intelligence plans, a field (type, or dictate with the keyboard's mic),
//  then a numbered plan of typed steps with their chords; Run · Save as key
//  · Edit; "Try" chips under an empty field.
//
//  Nothing runs until Run. Steps that are destructive or type on the Mac
//  ask once more (`AskSafety`). While the Mac is locked the plan shows but
//  Run is off, and the Mac's own gate refuses anyway. Ask is Pro: in the
//  free plan the field carries the small Pro lock (`.requiresPro(.ai)`),
//  plans nothing, and a tap on it opens the paywall. No upsell card (OR-03).
//  Thinking = a cyan dot scan over the plan area; the step that is running
//  shows the dot wave. Those are real waits, so they get the loader; no
//  sparkles.
//
//  Every stage keeps a way on (owner testing, build 24, OT-5; the flow is
//  Core's `AskFlow`): the request field is always there to start over;
//  after a run the result line ("Done on Studio.") comes with New request,
//  Run again, Save as key and Edit; Save as key is a short Name · Save ·
//  Cancel flow that returns to the plan or result; Edit returns to the
//  plan with Done. Under an empty field: recent requests, then "Try".
//
//  `AskPanel` is the content, one view for both places Ask runs: the sheet
//  (compact windows, and arrangements without a right column) and the
//  right column's Ask switch (OR-06). Both read `AskModel.shared`, so a
//  request typed in one shows in the other.
//

import PixelHandCore
import SwiftUI

struct AskSheet: View {
    let session: ControlSessionModel
    let macName: String

    @ObservedObject private var model = AskModel.shared
    @Environment(\.entitlements) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AskPanel(session: session, macName: macName, placement: .sheet)
                .background(PixelHandTheme.canvas.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .principal) { AskTitle(macName: macName) }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if entitlements.allows(.ai), model.planner != nil {
                        ToolbarItem(placement: .primaryAction) { OnDevicePill() }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// The sheet's title: the Ask glyph and "Ask", never a truncated "Ask
/// Muhammad’s Mac…" (VQ-050); VoiceOver still hears which Mac.
private struct AskTitle: View {
    let macName: String

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            PHGlyph(glyph: PixelGlyphs.ask, pitch: PixelPitch.header)
                .foregroundStyle(PixelHandTheme.ink)
            Text("Ask")
                .font(.headline)
                .foregroundStyle(PixelHandTheme.ink)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ask \(macName)")
    }
}

/// "On device" while Apple Intelligence plans.
private struct OnDevicePill: View {
    var body: some View {
        Text("On device")
            .font(.caption.weight(.semibold))
            .foregroundStyle(PixelHandTheme.ink2)
            .lineLimit(1)
            .padding(.horizontal, PixelHandTheme.Space.sm)
            .padding(.vertical, 4)
            .background(PixelHandTheme.fill, in: Capsule())
            .accessibilityLabel("Plans on this device with Apple Intelligence")
    }
}

/// Ask's content: the typed request, the plan and the step-by-step run.
struct AskPanel: View {
    enum Placement {
        /// In the Ask sheet: closing it stops a run.
        case sheet
        /// In the right column: the run keeps going while the column shows
        /// the deck, and the column is narrower.
        case column
    }

    let session: ControlSessionModel
    let macName: String
    var placement: Placement = .sheet
    /// Bumped by the shell each time Ask is opened in the column (⌘K, the
    /// Ask field), to focus the field.
    var focusRequest: Int = 0

    @ObservedObject private var model = AskModel.shared
    @Environment(\.entitlements) private var entitlements
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var isFieldFocused: Bool

    @State private var isConfirming = false
    @FocusState private var isNameFocused: Bool

    private var isUnlocked: Bool { entitlements.allows(.ai) }
    private var isMacLocked: Bool { session.macLockState.isLocked }
    private var catalog: AskAppCatalog { AskAppCatalog(installed: session.installedApps) }
    private var padding: CGFloat { placement == .sheet ? PixelHandTheme.Space.lg : PixelHandTheme.Space.md }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.lg) {
                if placement == .column, isUnlocked, model.planner != nil {
                    OnDevicePill()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                field
                if isUnlocked {
                    if let lock = session.macLockState.bannerText(macName: macName) {
                        banner(lock, tint: PixelHandTheme.warningTint)
                    }
                    content
                }
            }
            .padding(padding)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            model.planner = isUnlocked ? OnDeviceAskPlanner.makeIfAvailable() : nil
            // The sheet focuses on open; the column only when Ask was asked
            // for (⌘K, the Ask field), which may be what made it appear.
            let asked = placement == .sheet || focusRequest > 0
            if isUnlocked, model.plan == nil, asked { isFieldFocused = true }
        }
        .onChange(of: focusRequest) { _, _ in
            if isUnlocked, !model.isRunning { isFieldFocused = true }
        }
        // New request: the cleared field takes focus.
        .onChange(of: model.flow.fieldResetRequest) { _, _ in
            if isUnlocked { isFieldFocused = true }
        }
        .onDisappear {
            if placement == .sheet { model.cancelRun() }
        }
        .confirmationDialog("Run this plan on \(macName)?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Run", role: model.confirmationReasons == [.typesText] ? nil : .destructive) { startRun() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AskSafety.confirmationMessage(for: model.confirmationReasons, macName: macName))
        }
    }

    // MARK: Header and field

    private var field: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            // VQ-087: a short placeholder at AX3+ ("What shou…" in the column).
            TextField(AskFieldCopy.placeholder(band: typeSize.typeBand), text: $model.request, axis: .vertical)
                .lineLimit(1...4)
                .focused($isFieldFocused)
                .accessibilityIdentifier("ph.ask.field")
                .submitLabel(.go)
                .onSubmit(submit)
                .font(.body)
                .foregroundStyle(PixelHandTheme.ink)
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canSubmit ? PixelHandTheme.accent : PixelHandTheme.ink3, in: Circle())
            }
            .disabled(!canSubmit)
            .phosphorFocusable(cornerRadius: 18)
            .accessibilityLabel("Plan")
            .accessibilityIdentifier("ph.ask.submit")
        }
        .padding(.leading, PixelHandTheme.Space.lg)
        .padding(.trailing, PixelHandTheme.Space.xs)
        .padding(.vertical, PixelHandTheme.Space.xs)
        .frame(minHeight: PixelHandTheme.ControlHeight.primary)
        .background(PixelHandTheme.raised, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                .strokeBorder(PixelHandTheme.hairline)
        )
        // Free plan: the field is dimmed with the small lock in its corner,
        // and a tap opens the paywall for Ask (OR-03). Unlocked, no change.
        .requiresPro(.ai)
    }

    /// The field plans a new request from every stage but planning; a
    /// run in progress stops for it.
    private var canSubmit: Bool {
        !model.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.flow.canSubmitRequest
    }

    private func submit() {
        guard canSubmit else { return }
        isFieldFocused = false
        model.submit(apps: session.installedApps, frontApp: session.activeBundleID)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.flow.stage {
        case .request:
            examples
        case .planning:
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                label(model.planner == nil ? "Planning…" : "Planning on this device…")
                DotScan(columns: 25, rows: 5, pitch: 7, plateCornerRadius: PixelHandTheme.Radius.card, platePadding: 12)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Planning")
                Button(AskFlow.Action.cancel.title) { model.cancelPlanning() }
                    .buttonStyle(.ph(.secondary, size: .small))
                    .accessibilityIdentifier(AskFlow.Action.cancel.accessibilityID)
            }
        case .plan, .editing, .running, .result, .naming:
            if let plan = model.plan {
                planView(plan)
            } else {
                examples
            }
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            if !model.flow.recent.isEmpty {
                label("Recent")
                FlowChips(items: model.flow.recent, identifier: "ph.ask.recent") { request in
                    model.request = request
                    submit()
                }
                .padding(.bottom, PixelHandTheme.Space.sm)
            }
            label("Try")
            FlowChips(items: AskModel.examples) { example in
                model.request = example
                submit()
            }
            Text("Tap the mic on the keyboard to speak.")
                .font(.footnote)
                .foregroundStyle(PixelHandTheme.ink3)
        }
    }

    private func planView(_ plan: AskPlan) -> some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            label(planLabel(plan))
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                if plan.steps.isEmpty {
                    Text("No steps. Try saying it another way, or add a step.")
                        .font(.subheadline)
                        .foregroundStyle(PixelHandTheme.ink2)
                }
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    stepRow(index: index, step: step, plan: plan)
                }
                if isEditing { addStepMenu }
                if let name = model.flow.namingName {
                    namingRow(name)
                } else {
                    actions(plan)
                }
            }
            .padding(PixelHandTheme.Space.md)
            .background(PixelHandTheme.elevated, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))

            ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .result = model.flow.stage, let outcome = model.outcome {
                banner(outcome.message(macName: macName), tint: outcomeTint(outcome))
                    .accessibilityIdentifier("ph.ask.result")
            } else if case let .naming(_, back) = model.flow.stage, case .result = back, let outcome = model.outcome {
                banner(outcome.message(macName: macName), tint: outcomeTint(outcome))
                    .accessibilityIdentifier("ph.ask.result")
            }
            if let note = model.flow.note {
                banner(note, tint: model.flow.namingName == nil ? PixelHandTheme.accentTint : PixelHandTheme.warningTint)
                    .accessibilityIdentifier("ph.ask.note")
            }
        }
    }

    private func planLabel(_ plan: AskPlan) -> String {
        let count = plan.steps.count
        let steps = count == 1 ? "1 step" : "\(count) steps"
        let source: String
        switch plan.source {
        case .onDevice: source = " · Apple Intelligence"
        case .parser: source = ""
        case .edited: source = " · edited"
        }
        return "Plan · \(steps) on \(macName)\(source)"
    }

    private func stepRow(index: Int, step: AskStep, plan: AskPlan) -> some View {
        let invalid = plan.issues.contains { $0.stepIndex == index }
        let needsConfirm = AskSafety.reason(for: step) != nil
        return HStack(spacing: PixelHandTheme.Space.sm) {
            stepNumber(index)
            VStack(alignment: .leading, spacing: 2) {
                if isEditing, case let .typeText(text) = step {
                    TextField("Text", text: Binding(
                        get: { text },
                        set: { new in model.edit { $0.replace(at: index, with: .typeText(new)) } }
                    ))
                    .textFieldStyle(.roundedBorder)
                } else {
                    Text(step.summary { catalog.name(for: $0) })
                        .font(.subheadline)
                        .foregroundStyle(invalid ? PixelHandTheme.danger : PixelHandTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if needsConfirm, !isEditing {
                    Text("Asks first")
                        .font(.caption2)
                        .foregroundStyle(PixelHandTheme.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let chord = step.chord {
                Text(ChordText.glyphs(chord))
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(PixelHandTheme.ink2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(PixelHandTheme.fill, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous))
            } else if case .action(.menuCommand) = step {
                kbdLabel("menu")
            }
            if isEditing {
                Button { model.edit { $0.move(from: index, by: -1) } } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                    .accessibilityLabel("Move up")
                Button { model.edit { $0.move(from: index, by: 1) } } label: { Image(systemName: "chevron.down") }
                    .disabled(index == plan.steps.count - 1)
                    .accessibilityLabel("Move down")
                Button(role: .destructive) { model.edit { $0.remove(at: index) } } label: { Image(systemName: "minus.circle.fill") }
                    .foregroundStyle(PixelHandTheme.danger)
                    .accessibilityLabel("Remove step")
            } else if model.phase == .running(index: index) {
                // The run waits on the Mac for this step: the real wait the
                // dot-matrix loader is for.
                DotWave(pitch: 3, label: "Running step \(index + 1)")
            } else {
                deliveryMark(index)
            }
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 36)
        .accessibilityElement(children: isEditing ? .contain : .combine)
    }

    private func stepNumber(_ index: Int) -> some View {
        let isCurrent = model.phase == .running(index: index)
        return Text("\(index + 1)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(isCurrent ? .white : PixelHandTheme.ink2)
            .frame(width: 24, height: 24)
            .background(isCurrent ? PixelHandTheme.accent : PixelHandTheme.fill, in: Circle())
    }

    private func kbdLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(PixelHandTheme.ink2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(PixelHandTheme.fill, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous))
    }

    @ViewBuilder
    private func deliveryMark(_ index: Int) -> some View {
        switch model.deliveries[index] {
        case .confirmed, .sent:
            Image(systemName: "checkmark")
                .foregroundStyle(PixelHandTheme.success)
                .accessibilityLabel("Done")
        case .failed, .timedOut:
            Image(systemName: "xmark")
                .foregroundStyle(PixelHandTheme.danger)
                .accessibilityLabel("Didn’t run")
        case nil:
            EmptyView()
        }
    }

    private var addStepMenu: some View {
        Menu {
            Button("Type text") { model.edit { $0.append(.typeText("text")) } }
            Button("Press Return") { model.edit { $0.append(.action(.shortcut(keys: ["return"]))) } }
            Button("Wait 1 second") { model.edit { $0.append(.delay(milliseconds: 1_000)) } }
            Button("Play or pause") { model.edit { $0.append(.action(.media(key: .playPause))) } }
        } label: {
            Label("Add step", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
        }
        .frame(minHeight: 36)
    }

    private var isEditing: Bool { model.flow.isEditing }

    /// The stage's buttons (Core's `AskFlow.actions`): the first is the
    /// primary, the rest secondary; New request sits at the trailing end.
    private func actions(_ plan: AskPlan) -> some View {
        let actions = model.flow.actions
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: PixelHandTheme.Space.sm) {
                actionButtons(actions, plan: plan)
            }
            // The narrow column: two rows.
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                HStack(spacing: PixelHandTheme.Space.sm) {
                    actionButtons(Array(actions.prefix(2)), plan: plan)
                }
                HStack(spacing: PixelHandTheme.Space.sm) {
                    actionButtons(Array(actions.dropFirst(2)), plan: plan)
                }
            }
        }
        .padding(.top, PixelHandTheme.Space.xs)
    }

    @ViewBuilder
    private func actionButtons(_ actions: [AskFlow.Action], plan: AskPlan) -> some View {
        ForEach(Array(actions.enumerated()), id: \.element) { index, action in
            let isPrimary = index == 0 && action != .stop
            Button {
                perform(action)
            } label: {
                if action == .run || action == .runAgain {
                    Label(action.title, systemImage: "play.fill")
                } else {
                    Text(action.title)
                }
            }
            .buttonStyle(.ph(isPrimary ? .primary : .secondary, size: .small))
            .disabled(!isEnabled(action, plan: plan))
            .accessibilityHint(action == .run || action == .runAgain ? (isMacLocked ? "\(macName) is locked" : "") : "")
            .accessibilityIdentifier(action.accessibilityID)
        }
    }

    private func isEnabled(_ action: AskFlow.Action, plan: AskPlan) -> Bool {
        switch action {
        case .run, .runAgain: plan.canRun && !isMacLocked
        case .saveAsKey: !plan.isEmpty
        case .save: model.flow.canSaveName
        default: true
        }
    }

    private func perform(_ action: AskFlow.Action) {
        switch action {
        case .run, .runAgain: requestRun()
        case .stop: model.cancelRun()
        case .newRequest: model.newRequest()
        case .saveAsKey:
            model.beginSave(apps: session.installedApps)
            isNameFocused = true
        case .edit: model.beginEditing()
        case .doneEditing: model.endEditing()
        case .save: save()
        case .cancel:
            if model.flow.namingName != nil { model.cancelSave() } else { model.cancelPlanning() }
        }
    }

    /// Save as key: the key's name, then Save or Cancel.
    private func namingRow(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            label("Save as key")
            TextField("Name", text: Binding(get: { model.flow.namingName ?? name }, set: { model.rename($0) }))
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit { if model.flow.canSaveName { save() } }
                .font(.body)
                .padding(.horizontal, PixelHandTheme.Space.md)
                .frame(minHeight: PixelHandTheme.ControlHeight.standard)
                .background(PixelHandTheme.fill, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
                .accessibilityLabel("Key name")
                .accessibilityIdentifier("ph.ask.name")
            HStack(spacing: PixelHandTheme.Space.sm) {
                ForEach(model.flow.actions, id: \.self) { action in
                    Button(action.title) { perform(action) }
                        .buttonStyle(.ph(action == .save ? .primary : .secondary, size: .small))
                        .disabled(!isEnabledInNaming(action))
                        .accessibilityIdentifier(action.accessibilityID)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, PixelHandTheme.Space.xs)
    }

    private func isEnabledInNaming(_ action: AskFlow.Action) -> Bool {
        action == .save ? model.flow.canSaveName : true
    }

    // MARK: Run and save

    private func requestRun() {
        if model.confirmationReasons.isEmpty {
            startRun()
        } else {
            isConfirming = true
        }
    }

    private func startRun() {
        guard let sender = session.sender else { return }
        GestureHaptic.light.trigger()
        let session = session
        model.run(sender: sender) { session.macLockState.isLocked }
    }

    private func save() {
        isNameFocused = false
        model.saveAsKey(deck: DeckSurfaceModel.shared, apps: session.installedApps)
    }

    // MARK: Pieces

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(PixelHandTheme.ink2)
            .padding(.horizontal, PixelHandTheme.Space.xs)
    }

    private func banner(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(PixelHandTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(PixelHandTheme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
    }

    private func outcomeTint(_ outcome: AskModel.RunOutcome) -> Color {
        if case .done = outcome { return PixelHandTheme.successTint }
        return PixelHandTheme.warningTint
    }
}

/// Example (or recent) requests as chips.
private struct FlowChips: View {
    let items: [String]
    var identifier = "ph.ask.example"
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(PixelHandTheme.ink)
                        .padding(.horizontal, PixelHandTheme.Space.md)
                        .frame(minHeight: 36)
                        .background(PixelHandTheme.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .phosphorFocusable(cornerRadius: 18)
                .accessibilityIdentifier(identifier)
            }
        }
    }
}
