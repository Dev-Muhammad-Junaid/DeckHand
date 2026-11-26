//
//  AskPlan+Deck.swift
//  PixelHandCore
//
//  Ask's "Save as key": the plan becomes one deck key (its single action,
//  or a `sequence`). A plan that only talks to one app goes on that app's
//  page (created if missing); anything else goes on Home. A plan with a
//  destructive step saves with "Ask before running" on, so the key asks
//  the way the plan did.
//

import Foundation

extension AskPlan {
    /// The one app every step goes to, when there is exactly one and no
    /// step opens an app or reaches past it.
    public var singleApp: String? {
        var app: String?
        for step in steps {
            switch step {
            case let .action(.appShortcut(bundleID, _)), let .action(.menuCommand(bundleID, _)):
                if let app, app != bundleID { return nil }
                app = bundleID
            case .delay:
                continue
            default:
                return nil
            }
        }
        return app
    }

    /// The key Save as key stores, or `nil` when the plan can't be saved.
    /// `label` is the name the person gave it in Save as key (OT-5); blank
    /// or `nil` keeps the plan's own label. Cut to the deck's label length.
    public func deckKey(appName: (String) -> String? = { _ in nil }, label: String? = nil) -> DeckKey? {
        guard let action = savedAction else { return nil }
        let named = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chosen = named.isEmpty ? keyLabel(appName: appName) : String(named.prefix(DeckValidation.maxLabelLength))
        var key = DeckKey.draft(for: action, label: chosen, appName: appName)
        key.confirm = !AskSafety.reasons(in: self).isEmpty
        guard DeckValidation.keyIssues(key).isEmpty else { return nil }
        return key
    }
}

extension DeckDocument {
    /// Where a saved Ask key landed.
    public struct AskSaveResult: Equatable, Sendable {
        public var pageID: String
        public var keyID: String
    }

    /// Saves `plan` as a key: on its one app's page, else Home, else the
    /// first custom page with room. `nil` when the plan can't be saved or
    /// every candidate page is full.
    public mutating func saveAskPlan(
        _ plan: AskPlan,
        appName: (String) -> String? = { _ in nil },
        label: String? = nil
    ) -> AskSaveResult? {
        guard let key = plan.deckKey(appName: appName, label: label) else { return nil }
        var candidates: [Int] = []
        if let app = plan.singleApp {
            var trial = self
            if let index = trial.ensureAppPage(for: app, title: appName(app)),
               trial.pages[index].keys.count < DeckValidation.maxKeysPerPage {
                self = trial
                candidates.append(index)
            }
        }
        candidates += pages.indices.filter { pages[$0].kind == .home }
        candidates += pages.indices.filter { pages[$0].kind == .custom }
        for index in candidates where pages[index].keys.count < DeckValidation.maxKeysPerPage {
            var stored = key
            if pages.contains(where: { $0.keys.contains { $0.id == stored.id } }) { stored.id = DeckIDs.newKeyID() }
            pages[index].keys.append(stored)
            return AskSaveResult(pageID: pages[index].id, keyID: stored.id)
        }
        return nil
    }
}
