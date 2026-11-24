//
//  ControlSessionModel+Input.swift
//  DeckHandiOS
//
//  The iOS interaction lane's part of the session model: clipboard sync
//  (S10). Typing, drags, gestures and Pencil hover need no session state;
//  they go straight through `TrackpadSender` from the trackpad.
//

import Combine
import SwiftUI

extension ControlSessionModel {
    /// Mac → remote sharing messages.
    func handleSharingMessage(_ message: SharingMessage) {
        switch message {
        case let .macClipboard(text):
            clipboard.receivedFromMac(text, syncEnabled: interactionSettings?.clipboardSync ?? false)
        case .clipboardSync, .setClipboard:
            break // remote → Mac only
        case let .transferStatus(transferID, status):
            TransferCenter.shared.receivedStatus(status, for: transferID) // Sharing lane (S1)
        }
    }

    /// Tells the Mac whether to send its clipboard: once access is granted
    /// (the Mac drops anything sent before), and whenever Share Clipboard
    /// changes. Runs for the session, cancelled with it.
    func runInteraction(sender: TrackpadSender, settings: DeckHandSettings) async {
        interactionSettings = settings
        while lastAuthStatus != "granted" {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }
        for await enabled in settings.$clipboardSync.removeDuplicates().values {
            if Task.isCancelled { return }
            await sender.setClipboardSync(enabled: enabled)
        }
    }
}
