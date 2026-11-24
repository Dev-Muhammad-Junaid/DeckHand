//
//  MacSwitchCommands.swift
//  DeckHandiOS – Macs
//
//  Hardware-keyboard Mac switching (`03-Layout-Strategy.md`): ⌘1–⌘4 go to
//  the Macs in those places of My Macs, ⌘` to the next Mac in reach. Zero-
//  size buttons, so the shortcuts work on every surface and show in the
//  iPad's ⌘ overlay under the Macs' names.
//

import SwiftUI

struct MacSwitchCommands: View {
    private let switcher = MacSwitcher.shared

    var body: some View {
        let listings = switcher.listings
        ZStack {
            ForEach(listings.filter { $0.slot != nil }) { listing in
                if let slot = listing.slot {
                    Button(listing.isActive ? listing.name : "Switch to \(listing.name)") {
                        switcher.switchToSlot(slot)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(slot))), modifiers: .command)
                }
            }
            if listings.count > 1 {
                Button("Next Mac") {
                    switcher.step(by: 1)
                }
                .keyboardShortcut("`", modifiers: .command)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
