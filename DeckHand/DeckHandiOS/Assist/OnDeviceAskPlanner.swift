//
//  OnDeviceAskPlanner.swift
//  DeckHandiOS – Assist
//
//  Ask's Apple Intelligence layer (UX-022, A1): Foundation Models, on the
//  device, fills a typed plan by guided generation (`AskProposal`). Its
//  steps are flat strings, never actions: Core's `AskPlanResolver` turns
//  them into real `AskStep`s with the parser's vocabulary and drops
//  anything that doesn't resolve or validate. The person sees the plan
//  before anything runs, and the Mac validates every message as usual.
//
//  iOS 26+ behind `#available`, only while the system model is available
//  (`OnDeviceModel`). Otherwise, on an error, an empty answer or after
//  `timeout`, Ask uses the deterministic `AskCommandParser`.
//  No Private Cloud Compute, no third-party cloud (DECISIONS.md).
//

import Foundation
import PixelHandCore
#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceAskPlanner {
    /// How long the model may take before the parser's plan is used.
    static let timeout: TimeInterval = 10
    /// At most this many app names go into the prompt.
    static let maxAppNames = 60

    /// A planner when the on-device model can run now, else `nil`.
    static func makeIfAvailable() -> (any AskPlanning)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceModel.isAvailable {
            return FoundationModelsAskPlanner()
        }
        #endif
        return nil
    }

    static let instructions = """
    You turn a person's request into steps that control their Mac from a phone. \
    Use only these step kinds: \
    openApp (app), quitApp (app), shortcut (keys like "cmd+t", optional app), \
    menu (menuPath like ["File", "Export"], app), media (text: "play/pause", "next track" or "previous track"), \
    system (text: "mission control", "show desktop", "app windows", "launchpad", "find pointer", "lock screen", "screenshot", "spotlight"), \
    typeText (text to type), wait (seconds), runShortcut (text: the name of a Shortcuts shortcut). \
    Use the fewest steps. Never invent apps that aren't listed. \
    If something can't be done with these steps, leave it out.
    """
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AskProposal {
    @Guide(description: "The steps, in the order to run them.")
    var steps: [AskProposalStep]
}

@available(iOS 26.0, *)
@Generable
struct AskProposalStep {
    @Guide(description: "One of: openApp, quitApp, shortcut, menu, media, system, typeText, wait, runShortcut.")
    var kind: String
    @Guide(description: "The app's name, from the list, when the step needs one.")
    var app: String?
    @Guide(description: "A keyboard shortcut such as cmd+shift+t, for shortcut steps.")
    var keys: String?
    @Guide(description: "Text to type, a media or system action's name, or a Shortcut's name.")
    var text: String?
    @Guide(description: "Menu titles from the top menu down, for menu steps.")
    var menuPath: [String]?
    @Guide(description: "Seconds to wait, for wait steps.")
    var seconds: Double?
}

@available(iOS 26.0, *)
struct FoundationModelsAskPlanner: AskPlanning {
    func draft(request: String, appNames: [String], frontApp: String?) async -> [AskDraftStep]? {
        guard OnDeviceModel.isAvailable else { return nil }
        let apps = appNames.prefix(OnDeviceAskPlanner.maxAppNames).joined(separator: ", ")
        let prompt = """
        Apps on the Mac: \(apps)
        App in front: \(frontApp ?? "unknown")
        Request: \(request)
        """
        return await OnDeviceModel.withDeadline(OnDeviceAskPlanner.timeout) {
            let session = LanguageModelSession(instructions: OnDeviceAskPlanner.instructions)
            do {
                let response = try await session.respond(to: prompt, generating: AskProposal.self)
                return response.content.steps.map { step in
                    AskDraftStep(
                        kind: step.kind,
                        app: step.app,
                        keys: step.keys,
                        text: step.text,
                        menuPath: step.menuPath,
                        seconds: step.seconds
                    )
                }
            } catch {
                DeckHandLog.app.info("On-device Ask planning failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }
}
#endif
