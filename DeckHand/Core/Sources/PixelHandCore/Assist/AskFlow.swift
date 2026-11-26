//
//  AskFlow.swift
//  PixelHandCore
//
//  Where Ask is, and where each button takes it (owner testing, build 24,
//  OT-5: after one run the column was left on a Name field with no way
//  back). Every stage keeps the request field, so a new request can always
//  start over, and every stage that isn't a wait offers a way out:
//
//    request ──submit──▶ planning ──planReady──▶ plan ◀──done── editing
//       ▲                   │ cancel              │  ▲ edit ─────▲
//       │                   ▼                     │  │           │
//       ├──── newRequest ◀─ request          run  │  │ cancel    │ edit
//       │                                         ▼  │           │
//       │                                     running ──ended──▶ result
//       │                                       │ stop                │
//       │                                       ▼                     │
//       │                                     plan                    │
//       └────────── newRequest ◀──── result ── runAgain ──▶ running ──┘
//
//    plan / result ──saveAsKey──▶ naming ──save / cancel──▶ back where it came from
//
//  The app's `AskModel` feeds it the planner's and the run's events; the
//  panel draws `stage` and `actions`. No SwiftUI: tested on Linux.
//

import Foundation

public struct AskFlow: Sendable, Hashable {
    /// Where Ask is.
    public enum Stage: Sendable, Hashable {
        /// The field, with "Try" examples and recent requests.
        case request
        /// The plan is being made (a real wait: the dot scan).
        case planning
        /// The plan shows: Run, Save as key, Edit.
        case plan
        /// The plan's steps can be changed: Done.
        case editing
        /// Running step `step`: Stop.
        case running(step: Int)
        /// The run ended ("Done on Studio"): New request, Run again, Save
        /// as key, Edit.
        case result(succeeded: Bool)
        /// Save as key's short flow: a name, Save and Cancel.
        /// `returnTo` is the stage it came from (plan or result).
        indirect case naming(name: String, returnTo: Stage)
    }

    /// The buttons a stage offers, in the order they're drawn.
    public enum Action: String, Sendable, Hashable, CaseIterable {
        case run, stop, runAgain, newRequest, saveAsKey, edit, doneEditing, save, cancel

        public var title: String {
            switch self {
            case .run: "Run"
            case .stop: "Stop"
            case .runAgain: "Run again"
            case .newRequest: "New request"
            case .saveAsKey: "Save as key"
            case .edit: "Edit"
            case .doneEditing: "Done"
            case .save: "Save"
            case .cancel: "Cancel"
            }
        }

        /// The UI test identifier (`ph.ask.<raw value>`).
        public var accessibilityID: String { "ph.ask.\(rawValue)" }
    }

    public enum Event: Sendable, Hashable {
        /// The field was submitted.
        case submit(String)
        case planReady
        /// Planning was cancelled (a new empty request, or Cancel).
        case cancelPlanning
        case edit
        case doneEditing
        /// A run started (Run, or Run again).
        case runStarted
        case stepStarted(Int)
        case runEnded(succeeded: Bool)
        /// Stop during a run: back to the plan.
        case stopped
        /// Clear the field and start over.
        case newRequest
        /// Opens naming, with the plan's own label as the suggestion.
        case saveAsKey(suggestedName: String)
        case rename(String)
        /// The key was saved: back where naming came from, with a note.
        case saved(note: String)
        /// Saving failed: naming stays, with the reason.
        case saveFailed(String)
        case cancelNaming
    }

    public private(set) var stage: Stage = .request
    /// Recent requests, newest first, without repeats.
    public private(set) var recent: [String] = []
    /// A line under the plan after Save as key, or why it couldn't save.
    public private(set) var note: String?
    /// Bumped when the field should clear and take focus (New request).
    public private(set) var fieldResetRequest = 0

    public static let maximumRecent = 5

    public init(recent: [String] = []) {
        self.recent = Array(recent.prefix(Self.maximumRecent))
    }

    // MARK: Reading

    /// The buttons this stage offers. Empty while the request is typed and
    /// while planning (the field's own button plans).
    public var actions: [Action] {
        switch stage {
        case .request: []
        case .planning: [.cancel]
        case .plan: [.run, .saveAsKey, .edit, .newRequest]
        case .editing: [.doneEditing]
        case .running: [.stop]
        case .result: [.newRequest, .runAgain, .saveAsKey, .edit]
        case .naming: [.save, .cancel]
        }
    }

    /// The request field is always there to start over; it only stops
    /// taking a new plan while the current one is being made.
    public var canSubmitRequest: Bool { stage != .planning }

    /// Whether focusing the field selects its text, so what's typed next
    /// replaces the last request instead of joining it (build 25 bug: after
    /// Save as key › Cancel, typing made "nowTake a screenshot"). True
    /// whenever a plan or result shows: the field still holds the request
    /// that made it. While composing a request, focus leaves the caret.
    public var selectsFieldOnFocus: Bool {
        switch stage {
        case .request, .planning: false
        case .plan, .editing, .running, .result, .naming: true
        }
    }

    /// Whether the plan shows (with its steps) in this stage.
    public var showsPlan: Bool {
        switch stage {
        case .request, .planning: false
        case .plan, .editing, .running, .result, .naming: true
        }
    }

    public var isEditing: Bool { stage == .editing }

    public var isRunning: Bool {
        if case .running = stage { return true }
        return false
    }

    /// The name being typed in Save as key, if that's showing.
    public var namingName: String? {
        if case let .naming(name, _) = stage { return name }
        return nil
    }

    /// Whether Save is enabled in naming.
    public var canSaveName: Bool {
        guard let name = namingName else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Moving

    /// Applies `event`. Events that make no sense in the current stage are
    /// ignored, so a late planner or run callback can't strand the flow.
    public mutating func apply(_ event: Event) {
        switch event {
        case let .submit(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, canSubmitRequest else { return }
            remember(trimmed)
            note = nil
            stage = .planning

        case .planReady:
            guard stage == .planning else { return }
            stage = .plan

        case .cancelPlanning:
            guard stage == .planning else { return }
            stage = .request

        case .edit:
            switch stage {
            case .plan, .result: stage = .editing
            default: return
            }
            note = nil

        case .doneEditing:
            guard stage == .editing else { return }
            stage = .plan

        case .runStarted:
            switch stage {
            case .plan, .result: stage = .running(step: 0)
            default: return
            }
            note = nil

        case let .stepStarted(index):
            guard isRunning else { return }
            stage = .running(step: index)

        case let .runEnded(succeeded):
            guard isRunning else { return }
            stage = .result(succeeded: succeeded)

        case .stopped:
            guard isRunning else { return }
            stage = .plan

        case .newRequest:
            stage = .request
            note = nil
            fieldResetRequest += 1

        case let .saveAsKey(suggestedName):
            switch stage {
            case .plan, .result: stage = .naming(name: suggestedName, returnTo: stage)
            default: return
            }
            note = nil

        case let .rename(name):
            guard case let .naming(_, back) = stage else { return }
            stage = .naming(name: name, returnTo: back)

        case let .saved(text):
            guard case let .naming(_, back) = stage else { return }
            stage = back
            note = text

        case let .saveFailed(reason):
            guard case .naming = stage else { return }
            note = reason

        case .cancelNaming:
            guard case let .naming(_, back) = stage else { return }
            stage = back
            note = nil
        }
    }

    private mutating func remember(_ request: String) {
        recent.removeAll { $0.caseInsensitiveCompare(request) == .orderedSame }
        recent.insert(request, at: 0)
        if recent.count > Self.maximumRecent { recent.removeLast(recent.count - Self.maximumRecent) }
    }

    /// Clears the recent requests list.
    public mutating func forgetRecent() { recent = [] }
}

extension AskPlan {
    /// The name Save as key suggests: the plan's own key label.
    public func suggestedKeyName(appName: (String) -> String? = { _ in nil }) -> String {
        keyLabel(appName: appName)
    }
}
