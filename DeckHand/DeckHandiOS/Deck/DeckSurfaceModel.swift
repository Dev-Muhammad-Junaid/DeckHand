//
//  DeckSurfaceModel.swift
//  DeckHandiOS – Deck
//
//  The Deck surface's state (UX-020): which page shows (Follow front app,
//  debounced by Core's `DeckFollower`, and the pin), edit mode, and Undo /
//  Redo over `DeckStore`. Shared, so the page and the undo history survive
//  switching surfaces and rotating (the shell rebuilds the surface view).
//  No SwiftUI here: Linux type-checks it (`Scripts/linux-typecheck`).
//

import Combine
import Foundation

@MainActor
final class DeckSurfaceModel: ObservableObject {
    static let shared = DeckSurfaceModel(store: .shared)

    let store: DeckStore
    @Published private(set) var follower = DeckFollower()
    @Published private(set) var history = DeckUndoHistory<DeckDocument>()
    @Published var isEditing = false {
        didSet { if !isEditing { history.reset() } }
    }

    private var lastFrontBundleID: String?
    private var followTask: Task<Void, Never>?

    init(store: DeckStore) {
        self.store = store
    }

    var document: DeckDocument { store.document }

    /// The page on screen: the pin, else the followed or chosen page, else
    /// Home.
    var shownPageID: String? { follower.effectivePageID(in: store.document) }

    /// The app the shown page follows, for the header badge.
    var followedBundleID: String? {
        guard store.document.pinnedPageID == nil else { return nil }
        return follower.followedBundleID
    }

    /// Adds the standard pages a deck is missing (a Context page), once,
    /// outside Undo.
    func ensureStandardPages() {
        guard let fixed = store.document.addingStandardPages() else { return }
        store.replace(with: fixed)
    }

    // MARK: Paging and following

    /// The user paged (swipe, dots, a new page).
    func select(pageID: String) {
        guard pageID != shownPageID else { return }
        follower.userSelected(pageID: pageID)
    }

    /// The Mac's frontmost app; feeds the follower and applies the change
    /// once it has held for `DeckFollower.debounce`. Paused while editing,
    /// so the page being edited doesn't change under the user.
    func frontAppChanged(to bundleID: String?) {
        guard bundleID != lastFrontBundleID else { return }
        lastFrontBundleID = bundleID
        follower.frontAppChanged(to: bundleID, at: Date())
        scheduleFollow()
    }

    private func scheduleFollow() {
        followTask?.cancel()
        guard let deadline = follower.nextDeadline else { return }
        let delay = max(0, deadline.timeIntervalSinceNow)
        followTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.applyFollow()
        }
    }

    private func applyFollow() {
        guard !isEditing else {
            // Try again after editing; the change stays pending.
            followTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self else { return }
                self.applyFollow()
            }
            return
        }
        follower.update(document: store.document, now: Date())
    }

    /// Follow front app on or off.
    func setFollowsFrontApp(_ on: Bool) {
        edit(recordsUndo: false) { $0.followFrontApp = on }
    }

    /// Pins the shown page (stops following), or unpins it.
    func togglePin() {
        guard let id = shownPageID else { return }
        let wasPinned = store.document.pinnedPageID == id
        edit(recordsUndo: false) { $0.togglePin(pageID: id) }
        if wasPinned {
            // Unpinned: stay on this page until the front app changes.
            follower.userSelected(pageID: id)
        }
    }

    // MARK: Editing

    /// Applies an editor change and records it for Undo when it changed
    /// anything.
    func edit(recordsUndo: Bool = true, _ change: (inout DeckDocument) -> Void) {
        let before = store.document
        store.update(change)
        if recordsUndo, store.document != before { history.record(before) }
    }

    func undo() {
        guard let previous = history.undo(current: store.document) else { return }
        store.replace(with: previous)
    }

    func redo() {
        guard let next = history.redo(current: store.document) else { return }
        store.replace(with: next)
    }

    /// Adds a page, shows it and returns its ID.
    @discardableResult
    func addPage(title: String, kind: DeckPageKind) -> String? {
        var newID: String?
        edit { newID = $0.addPage(title: title, kind: kind) }
        if let newID { follower.userSelected(pageID: newID) }
        return newID
    }

    /// Deletes the shown page and shows Home.
    func deleteShownPage() {
        guard let id = shownPageID else { return }
        edit { $0.deletePage(id: id) }
        if let home = store.document.page(forFrontmostApp: nil)?.id { follower.userSelected(pageID: home) }
    }
}
