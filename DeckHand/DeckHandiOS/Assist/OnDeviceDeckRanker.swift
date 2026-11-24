//
//  OnDeviceDeckRanker.swift
//  DeckHandiOS – Assist
//
//  The thin Apple Intelligence layer of "Suggest a deck" (UX-021, D7):
//  Foundation Models, on the device, picks which of the deterministic
//  candidates go first. It answers numbers into the candidate list
//  (`DeckProposal`), so it can only reorder keys the Mac's menus really
//  have; Core's `applyingModelPicks` drops anything else. iOS 26+ behind
//  `#available`, and only when the system model reports itself available
//  (Apple Intelligence on, model downloaded, supported device). Otherwise,
//  or on any error or after `timeout`, the deterministic ranking stands.
//  No Private Cloud Compute, no third-party cloud (DECISIONS.md).
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceDeckRanker {
    /// How long the model may take before the deterministic order stays.
    static let timeout: TimeInterval = 8
    /// At most this many candidates go into the prompt.
    static let maxCandidates = 40

    /// A reorderer when the on-device model can run now, else `nil`.
    static func makeIfAvailable() -> (any DeckSuggestionReordering)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceModel.isAvailable {
            return FoundationModelsDeckRanker()
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct DeckProposal {
    @Guide(description: "Numbers of the menu commands to put on the deck, most useful first. Only numbers from the list.")
    var picks: [Int]
}

@available(iOS 26.0, *)
struct FoundationModelsDeckRanker: DeckSuggestionReordering {
    func picks(appName: String, candidates: [String], limit: Int) async -> [Int]? {
        guard OnDeviceModel.isAvailable, !candidates.isEmpty else { return nil }
        let lines = Array(candidates.prefix(OnDeviceDeckRanker.maxCandidates))
        let prompt = """
        App: \(appName)
        Pick up to \(limit) of these menu commands for a deck of keys on a phone that controls the Mac. \
        Prefer what people use often in \(appName) and what is hard to remember. \
        Skip plain text editing like Copy and Paste.

        \(lines.joined(separator: "\n"))
        """
        return await OnDeviceModel.withDeadline(OnDeviceDeckRanker.timeout) {
            let session = LanguageModelSession(
                instructions: "You choose keyboard shortcuts for a deck of keys. Answer only with numbers from the list you are given."
            )
            do {
                let response = try await session.respond(to: prompt, generating: DeckProposal.self)
                return Array(response.content.picks.prefix(limit))
            } catch {
                DeckHandLog.app.info("On-device deck ranking failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }
}
#endif
