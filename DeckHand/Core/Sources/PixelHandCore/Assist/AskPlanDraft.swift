//
//  AskPlanDraft.swift
//  PixelHandCore
//
//  What the on-device model hands back, before anyone trusts it. Apple's
//  Foundation Models fill a flat, string-typed step (`AskDraftStep`) by
//  guided generation; `AskPlanResolver` turns each one into a real
//  `AskStep` with the same vocabulary the parser uses (app names to bundle
//  IDs, written chords to wire names), drops anything that doesn't
//  resolve or validate, and says so in a note. A model can only describe
//  steps Ask already knows how to run.
//

import Foundation

/// One step as a model wrote it. Every field is optional text, so a
/// partial or odd answer still decodes and is judged here.
public struct AskDraftStep: Sendable, Equatable, Codable {
    /// `openApp`, `quitApp`, `shortcut`, `menu`, `media`, `system`,
    /// `typeText`, `wait` or `runShortcut`.
    public var kind: String
    /// An app's name (or bundle ID) for `openApp`, `quitApp`, and for a
    /// `shortcut` or `menu` that goes to one app.
    public var app: String?
    /// A chord, written any way ("cmd+t", "⌘T", "Command Shift N").
    public var keys: String?
    /// Text to type, a media or system action's name, or a Shortcut's name.
    public var text: String?
    /// Menu titles, top menu first.
    public var menuPath: [String]?
    /// Seconds to wait.
    public var seconds: Double?

    public init(kind: String, app: String? = nil, keys: String? = nil, text: String? = nil, menuPath: [String]? = nil, seconds: Double? = nil) {
        self.kind = kind
        self.app = app
        self.keys = keys
        self.text = text
        self.menuPath = menuPath
        self.seconds = seconds
    }
}

public enum AskPlanResolver {
    /// The kinds the model is told about, for its instructions.
    public static let kinds = ["openApp", "quitApp", "shortcut", "menu", "media", "system", "typeText", "wait", "runShortcut"]
    /// Most draft steps read.
    public static let maxDraftSteps = 30

    /// A validated plan from the model's steps. Steps that don't resolve
    /// are left out with a note; the result can be empty.
    public static func resolve(_ drafts: [AskDraftStep], request: String, catalog: AskAppCatalog) -> AskPlan {
        var steps: [AskStep] = []
        var notes: [String] = []
        var context: String?
        for draft in drafts.prefix(maxDraftSteps) {
            switch resolve(draft, catalog: catalog, context: context) {
            case let .success(resolved):
                for step in resolved {
                    steps.append(step)
                    if case let .action(.launchApp(id)) = step { context = id }
                }
            case let .failure(note):
                notes.append(note.message)
            }
        }
        if steps.count > AskPlanValidation.maxSteps {
            steps = Array(steps.prefix(AskPlanValidation.maxSteps))
            notes.append("Kept the first \(AskPlanValidation.maxSteps) steps.")
        }
        var plan = AskPlan(request: request, steps: steps, notes: notes, source: .onDevice)
        // Drop anything that still fails validation, one step at a time.
        let bad = Set(plan.issues.compactMap(\.stepIndex)).sorted(by: >)
        for index in bad where plan.steps.indices.contains(index) {
            plan.steps.remove(at: index)
            plan.notes.append("Left out a step that can’t run.")
        }
        plan.source = .onDevice
        return plan
    }

    public struct Note: Error, Equatable {
        public var message: String
    }

    static func resolve(_ draft: AskDraftStep, catalog: AskAppCatalog, context: String?) -> Result<[AskStep], Note> {
        let kind = draft.kind.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "")
        let named = draft.app.flatMap { catalog.app(named: $0) }
        switch kind {
        case "openapp", "launchapp", "open", "launch":
            guard let app = named ?? draft.text.flatMap({ catalog.app(named: $0) }) else {
                return .failure(Note(message: "Couldn’t find the app “\(draft.app ?? draft.text ?? "")” on the Mac."))
            }
            return .success([.action(.launchApp(bundleID: app.bundleID))])
        case "quitapp", "quit":
            guard let app = named else {
                return .failure(Note(message: "Couldn’t find the app “\(draft.app ?? "")” to quit."))
            }
            return .success([.action(.appShortcut(bundleID: app.bundleID, keys: ["cmd", "q"]))])
        case "shortcut", "keyboardshortcut", "chord", "keys", "press":
            guard let written = draft.keys ?? draft.text, let keys = ChordParser.parse(written) else {
                return .failure(Note(message: "Left out a shortcut that isn’t a real key chord."))
            }
            if let target = named?.bundleID ?? context {
                return .success([.action(.appShortcut(bundleID: target, keys: keys))])
            }
            return .success([.action(.shortcut(keys: keys))])
        case "menu", "menucommand":
            let path = (draft.menuPath ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let target = named?.bundleID ?? context else {
                return .failure(Note(message: "Left out a menu command with no app."))
            }
            let action = Action.menuCommand(bundleID: target, path: path)
            guard ActionValidation.isValid(action, storable: true) else {
                return .failure(Note(message: "Left out a menu command that isn’t a valid menu path."))
            }
            return .success([.action(action)])
        case "media":
            let name = (draft.text ?? draft.keys ?? "").lowercased()
            if let command = AskCommandParser.command(for: name), case let .global(action) = command, case .media = action {
                return .success([.action(action)])
            }
            return .failure(Note(message: "Pixel Hand can only play, pause and skip tracks."))
        case "system":
            let name = AskCommandParser.clean(draft.text ?? draft.keys ?? "")
            if let command = AskCommandParser.command(for: name), case let .global(action) = command {
                return .success([.action(action)])
            }
            if let note = AskCommandParser.unsupported(name) { return .failure(Note(message: note)) }
            return .failure(Note(message: "Left out “\(draft.text ?? "")”, which isn’t a system action Pixel Hand knows."))
        case "typetext", "type", "text":
            guard let text = draft.text, !text.isEmpty, text.utf8.count <= AskPlanValidation.maxTextBytes else {
                return .failure(Note(message: "Left out an empty Type step."))
            }
            return .success([.typeText(text)])
        case "wait", "delay", "pause":
            let ms = Int(((draft.seconds ?? 1) * 1000).rounded())
            return .success([.delay(milliseconds: min(max(0, ms), ActionLimits.maxDelayMilliseconds))])
        case "runshortcut", "macshortcut", "shortcutsapp":
            guard let name = (draft.text ?? draft.app).flatMap(AskCommandParser.cleanName) else {
                return .failure(Note(message: "Left out a Shortcut with no valid name."))
            }
            return .success([.action(.macShortcut(name: name))])
        default:
            return .failure(Note(message: "Left out a step Pixel Hand can’t run (“\(draft.kind)”)."))
        }
    }
}

extension AskPlanValidation.Issue {
    /// The step the issue is about, if it's about one.
    public var stepIndex: Int? {
        switch self {
        case let .badAction(index, _), let .nestedSequence(index), let .dialogPress(index), let .badText(index), let .badDelay(index):
            index
        case .empty, .tooManySteps, .totalDelayTooLong:
            nil
        }
    }
}
