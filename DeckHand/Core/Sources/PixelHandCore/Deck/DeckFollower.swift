//
//  DeckFollower.swift
//  PixelHandCore
//
//  "Follow front app" (product spec §3.3): the deck opens the frontmost
//  app's page when it changes and returns to the page the user had when
//  that app goes away. Changes are debounced (400 ms) so Cmd-Tab cycling
//  doesn't flicker the deck, and a pinned page stops all switching. Pure
//  state for the Deck 2 UI (UX-020) to drive from `activeAppUpdate`.
//

import Foundation

public struct DeckFollower: Sendable, Equatable {
    public static let debounce: TimeInterval = 0.4

    /// The page on screen.
    public private(set) var shownPageID: String?
    /// The page the user chose, shown again when no app page applies.
    public private(set) var userPageID: String?
    /// The frontmost app the shown page follows, for the title's badge.
    public private(set) var followedBundleID: String?
    private var pending: Pending?

    private struct Pending: Sendable, Equatable {
        var bundleID: String?
        var since: Date
    }

    public init(shownPageID: String? = nil) {
        self.shownPageID = shownPageID
        self.userPageID = shownPageID
    }

    /// The user picked a page (swipe, page dots, a tap).
    public mutating func userSelected(pageID: String) {
        shownPageID = pageID
        userPageID = pageID
        followedBundleID = nil
        pending = nil
    }

    /// The Mac's frontmost app changed.
    public mutating func frontAppChanged(to bundleID: String?, at now: Date) {
        pending = Pending(bundleID: bundleID, since: now)
    }

    /// When a pending change will apply, so the UI can call `update` then.
    public var nextDeadline: Date? {
        pending.map { $0.since.addingTimeInterval(Self.debounce) }
    }

    /// Applies a change that has held for `debounce`. Returns `true` when
    /// the shown page changed.
    @discardableResult
    public mutating func update(document: DeckDocument, now: Date) -> Bool {
        // A millisecond of slack, so a call at `nextDeadline` itself applies.
        guard let pending, now.timeIntervalSince(pending.since) >= Self.debounce - 0.001 else { return false }
        self.pending = nil
        guard document.followFrontApp, document.pinnedPageID == nil else { return false }
        let before = shownPageID
        if let bundleID = pending.bundleID, let page = document.appPage(for: bundleID) {
            if followedBundleID == nil, let shown = shownPageID, document.page(id: shown)?.appBundleID == nil {
                userPageID = shown
            }
            shownPageID = page.id
            followedBundleID = bundleID
        } else if followedBundleID != nil {
            // The followed app went away: back to the user's page, or Home.
            followedBundleID = nil
            if let user = userPageID, document.page(id: user) != nil {
                shownPageID = user
            } else {
                shownPageID = document.page(forFrontmostApp: nil)?.id
            }
        }
        return shownPageID != before
    }

    /// The page to show right now, given a pin and pages that may have been
    /// deleted since.
    public func effectivePageID(in document: DeckDocument) -> String? {
        if let pinned = document.pinnedPageID, document.page(id: pinned) != nil { return pinned }
        if let shown = shownPageID, document.page(id: shown) != nil { return shown }
        return document.page(forFrontmostApp: nil)?.id ?? document.pages.first?.id
    }
}
