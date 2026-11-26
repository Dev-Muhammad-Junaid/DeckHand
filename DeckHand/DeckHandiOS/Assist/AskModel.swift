//
//  AskModel.swift
//  DeckHandiOS – Assist
//
//  Ask (UX-022, A1): a request → a plan → Run or Save as key. Where Ask is
//  and what each button does is Core's `AskFlow` (owner testing, build 24,
//  OT-5: after one run the column was stuck on a Name field); this model
//  feeds it the planner's and the run's events. Plans come
//  from the on-device model when Apple Intelligence can run
//  (`OnDeviceAskPlanner`, resolved and validated by Core's
//  `AskPlanResolver`), else from Core's deterministic `AskCommandParser`.
//  Nothing runs until the person taps Run on the plan; destructive and
//  typing steps ask once more (the sheet's confirmation, `AskSafety`).
//
//  Running sends each step as the ordinary message it is (`deck.run` with a
//  receipt, or `input.typeText`), so the Mac checks every one with
//  `RemoteInputValidation` and its locked-Mac gate; this side also stops
//  before a step while the Mac reports itself locked. Ask is Pro (AI).
//  No SwiftUI here: Linux type-checks it.
//

import Combine
import Foundation
import PixelHandCore

/// Something that drafts a plan on the device. Answers the model's raw
/// steps, or `nil` when it can't (no model, an error, too slow).
protocol AskPlanning: Sendable {
    func draft(request: String, appNames: [String], frontApp: String?) async -> [AskDraftStep]?
}

@MainActor
final class AskModel: ObservableObject {
    static let shared = AskModel()

    enum Phase: Equatable {
        /// Waiting for a request.
        case idle
        /// The plan is being made.
        case planning
        /// `plan` is showing.
        case ready
        /// Running step `index` of `plan`.
        case running(index: Int)
        /// The run ended.
        case finished(RunOutcome)
    }

    enum RunOutcome: Equatable {
        /// Every step was sent (and confirmed where the Mac sends receipts).
        case done(steps: Int)
        /// Step `index` failed or wasn't confirmed in time; later steps
        /// didn't run.
        case stopped(index: Int, delivery: CommandDelivery)
        /// The Mac is locked; nothing more was sent.
        case locked(index: Int)
        /// The plan didn't validate (it changed under the run).
        case invalid
    }

    /// Requests offered under an empty field.
    static let examples = [
        "Open Safari and make a new tab",
        "Pause the music and lock the screen",
        "Take a screenshot",
        "Press ⌘⇧P",
        "Show Mission Control",
    ]

    /// The pause after opening an app, so it's in front before the next
    /// step types or presses into it.
    static let afterLaunchPause: Duration = .milliseconds(700)
    /// The pause between other steps (the Mac's own sequence gap, doubled
    /// for the network).
    static let stepGap: Duration = .milliseconds(ActionLimits.sequenceStepGapMilliseconds * 2)

    @Published var request = ""
    @Published private(set) var phase: Phase = .idle
    /// Where Ask is and what it offers (Core). The panel draws this.
    @Published private(set) var flow: AskFlow
    @Published var plan: AskPlan?
    /// What became of each step of the last run, by index.
    @Published private(set) var deliveries: [Int: CommandDelivery] = [:]
    /// Whether the plan showing came from Apple Intelligence.
    var isOnDevicePlan: Bool { plan?.source == .onDevice }

    /// The on-device planner, set by the sheet when the user has Pro and
    /// the model is available; `nil` uses the parser alone.
    @Published var planner: (any AskPlanning)?

    private var planTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var planGeneration = 0
    private var runGeneration = 0

    static let recentKey = "pixelhand.ask.recent"

    init() {
        flow = AskFlow(recent: UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? [])
    }

    private func apply(_ event: AskFlow.Event) {
        let before = flow.recent
        flow.apply(event)
        if flow.recent != before {
            UserDefaults.standard.set(flow.recent, forKey: Self.recentKey)
        }
    }

    // MARK: Planning

    /// Plans `request` (or the field's text). Shows the plan when ready.
    func submit(_ text: String? = nil, apps: [InstalledAppInfo], frontApp: String?) {
        let text = (text ?? request).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, flow.canSubmitRequest else { return }
        request = text
        stopRunQuietly()
        if case .naming = flow.stage { apply(.cancelNaming) }
        if flow.isEditing { apply(.doneEditing) }
        apply(.submit(text))
        planTask?.cancel()
        planGeneration += 1
        let generation = planGeneration
        let catalog = AskAppCatalog(installed: apps)
        let frontName = frontApp.flatMap { catalog.name(for: $0) }
        let planner = self.planner
        phase = .planning
        deliveries = [:]
        planTask = Task { [weak self] in
            let plan = await Self.makePlan(text, catalog: catalog, frontApp: frontName, planner: planner)
            guard let self, !Task.isCancelled, generation == self.planGeneration else { return }
            self.plan = plan
            self.phase = .ready
            self.apply(.planReady)
        }
    }

    /// The on-device plan when it has steps, else the parser's.
    nonisolated static func makePlan(
        _ text: String,
        catalog: AskAppCatalog,
        frontApp: String?,
        planner: (any AskPlanning)?
    ) async -> AskPlan {
        let parsed = AskCommandParser(catalog: catalog).plan(text)
        guard let planner else { return parsed }
        let names = catalog.apps.map(\.name)
        guard let drafts = await planner.draft(request: text, appNames: names, frontApp: frontApp) else { return parsed }
        let resolved = AskPlanResolver.resolve(drafts, request: text, catalog: catalog)
        return resolved.isEmpty ? parsed : resolved
    }

    /// New request: an empty field, focused, ready to start over. Stops
    /// planning or a run first.
    func newRequest() {
        planTask?.cancel()
        planGeneration += 1
        stopRunQuietly()
        request = ""
        plan = nil
        deliveries = [:]
        phase = .idle
        apply(.newRequest)
    }

    /// Cancel while the plan is being made: back to the request, text kept.
    func cancelPlanning() {
        planTask?.cancel()
        planGeneration += 1
        phase = .idle
        apply(.cancelPlanning)
    }

    // MARK: Editing

    func edit(_ change: (inout AskPlan) -> Void) {
        guard var plan, !isRunning else { return }
        change(&plan)
        self.plan = plan
        deliveries = [:]
        phase = .ready
    }

    /// Edit: the plan's steps can be changed (from the plan or a result).
    func beginEditing() {
        guard !isRunning else { return }
        deliveries = [:]
        phase = plan == nil ? .idle : .ready
        apply(.edit)
    }

    /// Done editing: back to the plan.
    func endEditing() {
        apply(.doneEditing)
    }

    var isEditing: Bool { flow.isEditing }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    // MARK: Running

    /// The reasons the plan must be confirmed before it runs; empty when
    /// tapping Run is enough.
    var confirmationReasons: [AskSafety.Reason] {
        plan.map(AskSafety.reasons(in:)) ?? []
    }

    /// Runs the plan in order, stopping at the first step the Mac refuses
    /// or doesn't confirm, or while it's locked. `isMacLocked` is read
    /// before every step.
    func run(sender: TrackpadSender, isMacLocked: @escaping @MainActor () -> Bool) {
        guard let plan, plan.canRun, !isRunning else {
            if plan?.canRun == false {
                phase = .finished(.invalid)
                apply(.runStarted)
                apply(.runEnded(succeeded: false))
            }
            return
        }
        deliveries = [:]
        apply(.runStarted)
        runGeneration += 1
        let generation = runGeneration
        runTask = Task { [weak self] in
            for (index, step) in plan.steps.enumerated() {
                guard let self, !Task.isCancelled, generation == self.runGeneration else { return }
                if isMacLocked() {
                    self.finish(.locked(index: index))
                    return
                }
                self.phase = .running(index: index)
                self.apply(.stepStarted(index))
                let delivery = await Self.send(step, sender: sender)
                guard !Task.isCancelled, generation == self.runGeneration else { return }
                self.deliveries[index] = delivery
                if delivery == .failed || delivery == .timedOut {
                    self.finish(.stopped(index: index, delivery: delivery))
                    return
                }
                if index < plan.steps.count - 1 {
                    let pause = step.action.map { if case .launchApp = $0 { true } else { false } } == true
                        ? Self.afterLaunchPause : Self.stepGap
                    try? await Task.sleep(for: pause)
                }
            }
            guard let self, generation == self.runGeneration else { return }
            self.finish(.done(steps: plan.steps.count))
        }
    }

    private func finish(_ outcome: RunOutcome) {
        phase = .finished(outcome)
        if case .done = outcome {
            apply(.runEnded(succeeded: true))
        } else {
            apply(.runEnded(succeeded: false))
        }
    }

    /// Stop: the run ends where it is, back to the plan.
    func cancelRun() {
        let wasRunning = isRunning
        stopRunQuietly()
        if wasRunning { apply(.stopped) }
    }

    /// Ends a run without moving the flow (a new request replaces it).
    private func stopRunQuietly() {
        runTask?.cancel()
        runTask = nil
        runGeneration += 1
        if isRunning { phase = .ready }
    }

    /// The result's outcome, while the flow shows one.
    var outcome: RunOutcome? {
        if case let .finished(outcome) = phase { return outcome }
        return nil
    }

    nonisolated static func send(_ step: AskStep, sender: TrackpadSender) async -> CommandDelivery {
        switch step {
        case let .action(action):
            return await sender.sendConfirmed(action)
        case let .typeText(text):
            await sender.typeText(text)
            return .sent
        case let .delay(ms):
            try? await Task.sleep(for: .milliseconds(ms))
            return .sent
        }
    }

    // MARK: Save as key

    enum SaveOutcome: Equatable {
        case saved(pageTitle: String)
        case blocked(String)
    }

    /// Save as key, step 1: the short naming flow, with the plan's own
    /// label suggested.
    func beginSave(apps: [InstalledAppInfo]) {
        guard let plan, !isRunning else { return }
        let catalog = AskAppCatalog(installed: apps)
        apply(.saveAsKey(suggestedName: plan.suggestedKeyName { catalog.name(for: $0) }))
    }

    /// The name being typed in Save as key.
    func rename(_ name: String) {
        apply(.rename(name))
    }

    /// Cancel: back to the plan or result naming came from.
    func cancelSave() {
        apply(.cancelNaming)
    }

    /// Save as key, step 2: saves the plan as one key with the given name
    /// (Core's `saveAskPlan`), as one undo step in the deck editor, and
    /// goes back to the plan or result with a note. A failure keeps the
    /// name field with the reason.
    @discardableResult
    func saveAsKey(deck: DeckSurfaceModel, apps: [InstalledAppInfo]) -> SaveOutcome {
        let outcome = save(deck: deck, apps: apps, label: flow.namingName)
        switch outcome {
        case let .saved(pageTitle): apply(.saved(note: "Saved as a key on \(pageTitle)."))
        case let .blocked(message): apply(.saveFailed(message))
        }
        return outcome
    }

    private func save(deck: DeckSurfaceModel, apps: [InstalledAppInfo], label: String?) -> SaveOutcome {
        guard let plan else { return .blocked("Nothing to save.") }
        if let blocker = plan.saveBlocker { return .blocked(blocker.message) }
        let catalog = AskAppCatalog(installed: apps)
        let name: (String) -> String? = { catalog.name(for: $0) }
        var result: DeckDocument.AskSaveResult?
        deck.edit { document in
            result = document.saveAskPlan(plan, appName: name, label: label)
        }
        guard let result, let page = deck.document.page(id: result.pageID) else {
            return .blocked("The deck is full. Remove a key or add a page, then try again.")
        }
        return .saved(pageTitle: page.displayTitle(appName: name))
    }
}

extension AskModel.RunOutcome {
    /// One line under the plan after a run.
    func message(macName: String) -> String {
        switch self {
        case let .done(steps):
            steps == 1 ? "Done on \(macName)." : "Done on \(macName): \(steps) steps."
        case let .stopped(index, delivery):
            delivery == .timedOut
                ? "Step \(index + 1) wasn’t confirmed by \(macName). The rest didn’t run."
                : "\(macName) couldn’t run step \(index + 1). Check Accessibility in Pixel Hand on the Mac."
        case let .locked(index):
            index == 0
                ? "\(macName) is locked. Unlock it, then run the plan."
                : "\(macName) locked at step \(index + 1). The rest didn’t run."
        case .invalid:
            "This plan can’t run. Remove the steps marked in red."
        }
    }
}
