//
//  AskPlan.swift
//  PixelHandCore
//
//  What Ask (UX-022, backlog A1) turns a request into: a numbered plan of
//  typed steps the person reviews, edits, runs or saves as a deck key.
//  Every step is an existing `Action` (Deck 2 cases included), typed text,
//  or a pause. A plan never runs on its own: the remote shows it first,
//  and steps that are destructive or type on the Mac ask again
//  (`AskSafety`). The Mac never trusts a plan either: each step reaches it
//  as an ordinary message, through `RemoteInputValidation` and the
//  locked-Mac gate.
//

import Foundation

/// One step of an Ask plan.
public enum AskStep: Codable, Sendable, Equatable, Hashable {
    /// Run an action. Never a `sequence` (a plan is already one) and never
    /// a dialog press (`AskPlanValidation`).
    case action(Action)
    /// Type `text` into the front app (`input.typeText`).
    case typeText(String)
    /// Wait before the next step.
    case delay(milliseconds: Int)

    public var action: Action? {
        if case let .action(action) = self { return action }
        return nil
    }

    /// One line for the plan view, in plain words.
    public func summary(appName: (String) -> String? = { _ in nil }) -> String {
        switch self {
        case let .action(action):
            return action.summary(appName: appName)
        case let .typeText(text):
            let shown = text.count > 60 ? String(text.prefix(57)) + "…" : text
            return "Type “\(shown)”"
        case let .delay(ms):
            let seconds = Double(ms) / 1000
            let text = seconds == seconds.rounded() ? String(Int(seconds)) : String(format: "%.1f", seconds)
            return "Wait \(text) s"
        }
    }

    /// The chord the step presses, for the plan view's chord chip.
    public var chord: [String]? {
        switch self {
        case let .action(.shortcut(keys)), let .action(.appShortcut(_, keys)): keys
        default: nil
        }
    }
}

/// Who wrote a plan, for the plan view's subtitle.
public enum AskPlanSource: String, Codable, Sendable, Equatable {
    /// Apple's on-device Foundation Models.
    case onDevice
    /// The deterministic keyword parser (`AskCommandParser`).
    case parser
    /// The person edited it after it was planned.
    case edited
}

/// A plan: the steps, plus quiet notes about what wasn't understood or
/// can't be done.
public struct AskPlan: Codable, Sendable, Equatable {
    public var request: String
    public var steps: [AskStep]
    public var notes: [String]
    public var source: AskPlanSource

    public init(request: String, steps: [AskStep], notes: [String] = [], source: AskPlanSource) {
        self.request = request
        self.steps = steps
        self.notes = notes
        self.source = source
    }

    public var isEmpty: Bool { steps.isEmpty }

    /// Problems that stop the plan running; empty when it can run.
    public var issues: [AskPlanValidation.Issue] { AskPlanValidation.issues(in: self) }
    public var canRun: Bool { issues.isEmpty }

    /// Why the plan can't be saved as a key, or `nil` when it can.
    public var saveBlocker: AskPlanValidation.SaveBlocker? { AskPlanValidation.saveBlocker(for: self) }

    /// The one action a deck key stores for this plan: the single action,
    /// or a `sequence` of every step. `nil` when `saveBlocker` isn't.
    public var savedAction: Action? {
        guard saveBlocker == nil else { return nil }
        if steps.count == 1, let only = steps.first?.action { return only }
        let sequence: [SequenceStep] = steps.compactMap { step in
            switch step {
            case let .action(action): .run(action: action)
            case let .delay(ms): .delay(milliseconds: ms)
            case .typeText: nil
            }
        }
        let action = Action.sequence(steps: sequence)
        return ActionValidation.isValid(action, storable: true) ? action : nil
    }

    /// A label for the saved key: the request, trimmed, or the single
    /// step's own name.
    public func keyLabel(appName: (String) -> String? = { _ in nil }) -> String {
        if steps.count == 1, let action = steps.first?.action {
            return DeckKey.draft(for: action, appName: appName).label
        }
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        let label = String(first.prefix(DeckValidation.maxLabelLength))
        return label.isEmpty ? "Macro" : label
    }

    // MARK: Editing

    public mutating func remove(at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps.remove(at: index)
        source = .edited
    }

    public mutating func move(from index: Int, by offset: Int) {
        let target = index + offset
        guard steps.indices.contains(index), steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
        source = .edited
    }

    public mutating func replace(at index: Int, with step: AskStep) {
        guard steps.indices.contains(index) else { return }
        steps[index] = step
        source = .edited
    }

    public mutating func append(_ step: AskStep) {
        steps.append(step)
        source = .edited
    }
}

// MARK: - Validation

public enum AskPlanValidation {
    /// Most steps in a plan: what a saved `sequence` may hold.
    public static let maxSteps = ActionLimits.maxSequenceSteps
    /// Longest typed text in one step.
    public static let maxTextBytes = TypingPolicy.maxMessageBytes

    public enum Issue: Equatable, Sendable {
        case empty
        case tooManySteps
        case badAction(index: Int, ActionValidation.Issue)
        case nestedSequence(index: Int)
        case dialogPress(index: Int)
        case badText(index: Int)
        case badDelay(index: Int)
        case totalDelayTooLong
    }

    public enum SaveBlocker: Equatable, Sendable {
        case cannotRun
        case typesText

        public var message: String {
            switch self {
            case .cannotRun: "Fix the plan before saving it."
            case .typesText: "Keys can’t type text yet. Remove the Type step to save this plan as a key."
            }
        }
    }

    public static func issues(in plan: AskPlan) -> [Issue] {
        var issues: [Issue] = []
        if plan.steps.isEmpty { issues.append(.empty) }
        if plan.steps.count > maxSteps { issues.append(.tooManySteps) }
        var totalDelay = 0
        for (index, step) in plan.steps.enumerated() {
            switch step {
            case let .action(action):
                if case .sequence = action { issues.append(.nestedSequence(index: index)); continue }
                if case .contextAction = action { issues.append(.dialogPress(index: index)); continue }
                for issue in ActionValidation.issues(in: action, storable: true) {
                    issues.append(.badAction(index: index, issue))
                }
            case let .typeText(text):
                if text.isEmpty || text.utf8.count > maxTextBytes { issues.append(.badText(index: index)) }
            case let .delay(ms):
                if ms < 0 || ms > ActionLimits.maxDelayMilliseconds {
                    issues.append(.badDelay(index: index))
                } else {
                    totalDelay += ms
                }
            }
        }
        if totalDelay > ActionLimits.maxTotalDelayMilliseconds { issues.append(.totalDelayTooLong) }
        return issues
    }

    public static func saveBlocker(for plan: AskPlan) -> SaveBlocker? {
        guard issues(in: plan).isEmpty else { return .cannotRun }
        if plan.steps.contains(where: { if case .typeText = $0 { true } else { false } }) { return .typesText }
        return nil
    }
}

// MARK: - Safety

/// Which steps ask again before running (`04-Interaction-Model.md`:
/// "destructive or multi-Mac always asks"; remote typing too).
public enum AskSafety {
    public enum Reason: String, Sendable, Equatable, CaseIterable {
        case typesText
        case quits
        case closes
        case deletes
        case locks
        case logsOut
        case forceQuit
        case runsShortcut

        /// One line in the confirmation.
        public var message: String {
            switch self {
            case .typesText: "types on the Mac"
            case .quits: "quits an app"
            case .closes: "closes a window or tab"
            case .deletes: "deletes something"
            case .locks: "locks the Mac"
            case .logsOut: "logs out"
            case .forceQuit: "opens Force Quit"
            case .runsShortcut: "runs a Shortcut"
            }
        }
    }

    /// Why `step` must be confirmed, or `nil` when tapping Run is enough.
    public static func reason(for step: AskStep) -> Reason? {
        switch step {
        case .typeText: return .typesText
        case .delay: return nil
        case let .action(action): return reason(for: action)
        }
    }

    public static func reason(for action: Action) -> Reason? {
        switch action {
        case let .shortcut(keys), let .appShortcut(_, keys):
            return reason(forChord: keys)
        case let .menuCommand(_, path):
            return reason(forMenuTitle: path.last ?? "")
        case .macShortcut:
            return .runsShortcut
        case let .sequence(steps):
            return steps.lazy.compactMap { $0.action.flatMap(reason(for:)) }.first
        case .launchApp, .system, .media, .contextAction:
            return nil
        }
    }

    /// Every distinct reason in the plan, in step order.
    public static func reasons(in plan: AskPlan) -> [Reason] {
        var seen: [Reason] = []
        for step in plan.steps {
            if let reason = reason(for: step), !seen.contains(reason) { seen.append(reason) }
        }
        return seen
    }

    /// The confirmation's message: "This plan quits an app and types on
    /// the Mac."
    public static func confirmationMessage(for reasons: [Reason], macName: String) -> String {
        let parts = reasons.map { $0.message.replacingOccurrences(of: "the Mac", with: macName) }
        let list: String
        switch parts.count {
        case 0: return ""
        case 1: list = parts[0]
        case 2: list = parts[0] + " and " + parts[1]
        default: list = parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        }
        return "This plan \(list)."
    }

    static func reason(forChord keys: [String]) -> Reason? {
        let names = Set(keys.map { ChordParser.canonical($0) })
        let cmd = names.contains("cmd")
        let ctrl = names.contains("ctrl")
        let shift = names.contains("shift")
        let option = names.contains("option")
        if cmd && ctrl && names.contains("q") { return .locks }
        if cmd && shift && names.contains("q") { return .logsOut }
        if cmd && option && names.contains("escape") { return .forceQuit }
        if cmd && names.contains("q") { return .quits }
        if cmd && names.contains("w") { return .closes }
        if cmd && names.contains("delete") { return .deletes }
        return nil
    }

    static func reason(forMenuTitle title: String) -> Reason? {
        let t = title.lowercased()
        if t.hasPrefix("quit") || t.hasPrefix("force quit") { return .quits }
        if t.hasPrefix("close") { return .closes }
        if t.hasPrefix("log out") || t.hasPrefix("shut down") || t.hasPrefix("restart") { return .logsOut }
        if t.hasPrefix("lock") { return .locks }
        for word in ["delete", "trash", "erase", "discard", "revert", "remove"] where t.contains(word) {
            return .deletes
        }
        return nil
    }
}
