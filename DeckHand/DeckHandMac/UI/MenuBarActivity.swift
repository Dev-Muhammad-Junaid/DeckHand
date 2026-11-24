//
//  MenuBarActivity.swift
//  DeckHandMac – UI
//
//  When a remote last drove the pointer or keys, and when text or a file
//  last arrived, for the menu-bar hand's "being controlled" and
//  "receiving" states (`StatusItemIcon.swift`). The handlers call the
//  `note` methods; they are cheap enough for every pointer move.
//

import Foundation

@MainActor
final class MenuBarActivity {
    static let shared = MenuBarActivity()

    private(set) var lastInput: Date?
    private(set) var lastReceive: Date?

    /// Called when the hand may need to change (the status item's controller).
    var onChange: (() -> Void)?

    /// A remote moved the pointer, clicked, scrolled or typed.
    func noteInput() {
        let now = Date()
        // Only a change of state needs a redraw: the first input after a
        // quiet spell. The controller's tick ends the hold.
        let wasQuiet = lastInput.map { now.timeIntervalSince($0) >= MenuBarHandState.activeHold } ?? true
        lastInput = now
        if wasQuiet { onChange?() }
    }

    /// Text or a file arrived from a remote.
    func noteReceive() {
        lastReceive = Date()
        onChange?()
    }
}
