//
//  DeckSuggestionsModel.swift
//  DeckHandiOS – Deck
//
//  "Suggest a deck" (UX-021, D7): asks the Mac for an app's menu shortcuts
//  (`deck.requestAppMenuShortcuts`, the S9-hardened menu walk), ranks them
//  with Core's deterministic `DeckSuggestionRanker`, and, where Apple
//  Intelligence is on, lets the on-device model reorder them
//  (`DeckSuggestionReordering`, `Assist/OnDeviceDeckRanker.swift`). The
//  deterministic ranking shows at once; the model's order replaces it when
//  it answers. No cloud.
//
//  A reply this model asked for is claimed here (`claim`), so it isn't
//  imported into the deck the way the shortcut sheet's import is.
//  Shared, so the panel keeps its state when the shell rebuilds the
//  surface. No SwiftUI here: Linux type-checks it.
//

import Combine
import Foundation
import PixelHandCore

/// Something that reorders suggestions on the device. Gets one line per
/// candidate ("0. Product › Build (⌘B)") and answers the numbers to show
/// first, best first, or `nil` when it can't (no model, an error, too
/// slow). Core's `applyingModelPicks` drops numbers that don't exist.
protocol DeckSuggestionReordering: Sendable {
    func picks(appName: String, candidates: [String], limit: Int) async -> [Int]?
}

@MainActor
final class DeckSuggestionsModel: ObservableObject {
    static let shared = DeckSuggestionsModel()

    enum Phase: Equatable {
        /// Nothing asked for this app yet.
        case idle
        /// Waiting for the Mac's menu walk.
        case reading
        /// `ordered` holds the ranking (possibly empty).
        case ready
        /// The Mac didn't answer in time.
        case failed
    }

    enum Ranking: Equatable {
        /// Core's deterministic ranking.
        case fallback
        /// The deterministic ranking shows; the on-device model is working.
        case refining
        /// The on-device model's order.
        case onDevice
    }

    /// What "Keep" did last, for the panel's Undo.
    struct KeptNote: Equatable {
        let bundleID: String
        let count: Int
        /// The editor's undo depth right after the keep. Undo shows only
        /// while nothing else was recorded since.
        let undoCount: Int
    }

    /// How long a menu walk stays fresh before it's asked again.
    static let cacheLifetime: TimeInterval = 10 * 60
    /// How long to wait for the Mac's reply.
    static let replyTimeout: TimeInterval = 15
    /// How many candidates the ranking keeps before filtering, so keys the
    /// user removes come back and the model has some to choose from.
    static let poolSize = 48

    /// One app's suggestions.
    struct AppState: Equatable {
        var phase: Phase = .idle
        var ranking: Ranking = .fallback
        /// The full order, before filtering out what the page already has.
        var ordered: [DeckSuggestion] = []
    }

    /// Per app, so two pages (an app page and the Context page) can each
    /// show their own panel.
    @Published private(set) var states: [String: AppState] = [:]
    /// Apps whose panel the user closed this session.
    @Published private(set) var closedBundleIDs: Set<String> = []
    /// Suggestions the user hid one by one, by ID.
    @Published private(set) var hiddenIDs: Set<String> = []
    @Published var keptNote: KeptNote?

    /// Set by the surface when on-device AI is available; `nil` uses the
    /// deterministic ranking only.
    var reorderer: (any DeckSuggestionReordering)?

    private var cache: [String: (bindings: [AppShortcutBinding], at: Date)] = [:]
    private var pending: Set<String> = []
    private var appNames: [String: String] = [:]
    private var existingAtLoad: [String: [DeckKey]] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    private var refineTasks: [String: Task<Void, Never>] = [:]
    /// Bumped on every new ranking of an app, so a late model answer for
    /// an older one is dropped.
    private var generations: [String: Int] = [:]

    // MARK: Reads

    func state(for bundleID: String) -> AppState { states[bundleID] ?? AppState() }

    /// What the panel shows for `bundleID`: the order, minus what the page
    /// already has (`existing`) and what the user hid, capped.
    func visible(for bundleID: String, existing: [DeckKey]) -> [DeckSuggestion] {
        let state = state(for: bundleID)
        guard state.phase == .ready else { return [] }
        let pool = state.ordered.filter { !hiddenIDs.contains($0.id) }
        let allowed = Set(DeckSuggestionRanker.candidates(pool.map(\.binding), bundleID: bundleID, existing: existing).map(\.id))
        return Array(pool.filter { allowed.contains($0.id) }.prefix(DeckSuggestionRanker.maxSuggestions))
    }

    func isClosed(_ bundleID: String) -> Bool { closedBundleIDs.contains(bundleID) }

    /// Whether the menus for `bundleID` are fresh in the cache.
    func hasFreshMenus(for bundleID: String, now: Date = Date()) -> Bool {
        guard let entry = cache[bundleID] else { return false }
        return now.timeIntervalSince(entry.at) < Self.cacheLifetime
    }

    // MARK: Loading

    /// Shows suggestions for `bundleID`: from the cache when fresh,
    /// otherwise asks the Mac. `force` asks again. The Mac brings the app
    /// forward to read its menus, so callers ask on their own only for the
    /// app already in front.
    func load(bundleID: String, appName: String, existing: [DeckKey], sender: TrackpadSender, force: Bool = false) {
        appNames[bundleID] = appName
        existingAtLoad[bundleID] = existing
        if !force, hasFreshMenus(for: bundleID), let entry = cache[bundleID] {
            if state(for: bundleID).phase != .ready { publish(entry.bindings, for: bundleID) }
            return
        }
        guard !pending.contains(bundleID) else { return }
        pending.insert(bundleID)
        states[bundleID, default: AppState()].phase = .reading
        timeoutTasks[bundleID]?.cancel()
        timeoutTasks[bundleID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.replyTimeout * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.replyTimedOut(bundleID: bundleID)
        }
        Task { await sender.requestMenuShortcuts(bundleID: bundleID) }
    }

    /// The Mac's `appMenuShortcutsResponse`. Returns `true` when this model
    /// asked for it (the caller then doesn't import it into the deck).
    func claim(bundleID: String, shortcuts: [AppShortcutBinding]) -> Bool {
        guard pending.remove(bundleID) != nil else { return false }
        cache[bundleID] = (shortcuts, Date())
        timeoutTasks.removeValue(forKey: bundleID)?.cancel()
        publish(shortcuts, for: bundleID)
        return true
    }

    private func replyTimedOut(bundleID: String) {
        guard pending.remove(bundleID) != nil else { return }
        timeoutTasks[bundleID] = nil
        states[bundleID, default: AppState()].phase = .failed
    }

    private func publish(_ bindings: [AppShortcutBinding], for bundleID: String) {
        let generation = (generations[bundleID] ?? 0) + 1
        generations[bundleID] = generation
        let ranked = DeckSuggestionRanker.rank(
            bindings,
            bundleID: bundleID,
            existing: existingAtLoad[bundleID] ?? [],
            limit: Self.poolSize
        )
        states[bundleID] = AppState(phase: .ready, ranking: .fallback, ordered: ranked)
        refine(ranked, bundleID: bundleID, generation: generation)
    }

    /// Lets the on-device model reorder the deterministic ranking.
    private func refine(_ ranked: [DeckSuggestion], bundleID: String, generation: Int) {
        refineTasks.removeValue(forKey: bundleID)?.cancel()
        guard let reorderer, ranked.count > 1 else { return }
        states[bundleID]?.ranking = .refining
        let appName = appNames[bundleID] ?? bundleID
        let lines = DeckSuggestionRanker.promptLines(for: ranked)
        refineTasks[bundleID] = Task { [weak self] in
            let picks = await reorderer.picks(appName: appName, candidates: lines, limit: DeckSuggestionRanker.maxSuggestions)
            guard !Task.isCancelled, let self, self.generations[bundleID] == generation else { return }
            if let picks, !picks.isEmpty {
                self.states[bundleID]?.ordered = DeckSuggestionRanker.applyingModelPicks(picks, to: ranked, limit: ranked.count)
                self.states[bundleID]?.ranking = .onDevice
            } else {
                self.states[bundleID]?.ranking = .fallback
            }
            self.refineTasks[bundleID] = nil
        }
    }

    // MARK: User actions

    /// Closes the panel for `bundleID` until the app restarts.
    func close(_ bundleID: String) {
        closedBundleIDs.insert(bundleID)
    }

    func reopen(_ bundleID: String) {
        closedBundleIDs.remove(bundleID)
    }

    /// Hides one suggestion.
    func hide(_ suggestionID: String) {
        hiddenIDs.insert(suggestionID)
    }

    /// Records a Keep for the panel's "Kept 3 keys · Undo".
    func noteKept(count: Int, bundleID: String, undoCount: Int) {
        keptNote = count > 0 ? KeptNote(bundleID: bundleID, count: count, undoCount: undoCount) : nil
    }
}
