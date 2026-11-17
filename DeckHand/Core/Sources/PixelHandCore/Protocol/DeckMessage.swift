//
//  DeckMessage.swift
//  PixelHandCore
//
//  Domain: chips and deck. Menu-shortcut import, and actions run with a
//  delivery receipt. Both ways. Owned by the deck lane (remote chips and
//  deck) and the Mac's `DeckHandler`.
//

import Foundation

public enum DeckMessage: Codable, Sendable, Equatable {
    // MARK: Remote → Mac

    /// Read every shortcut in `bundleID`'s menu bar through Accessibility.
    /// Reply: `appMenuShortcutsResponse`.
    case requestAppMenuShortcuts(bundleID: String)
    /// Run `action`, then answer with `receipt` carrying the same
    /// `requestID`. Replaces version 1's `tracked(requestID:command:)`:
    /// an `Action` is not a message, so runs can't nest.
    case run(requestID: String, action: Action)

    // MARK: Mac → remote

    /// Reply to `requestAppMenuShortcuts`. Empty when the app wasn't
    /// running or had no menu shortcuts the Mac could read.
    case appMenuShortcutsResponse(bundleID: String, shortcuts: [AppShortcutBinding])
    /// What became of the `run` with this `requestID`.
    case receipt(requestID: String, outcome: ActionOutcome)
}
