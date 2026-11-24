//
//  SharingHandler.swift
//  DeckHandMac
//
//  Domain: sharing. Clipboard text sync (S10), through `MacClipboardSync`
//  (iOS interaction lane), and transfer status (S1, Sharing lane), through
//  `MacTransferService`.
//

import LoomKit

@MainActor
final class SharingHandler: DomainHandler {
    func handle(_ message: SharingMessage, from connection: LoomConnectionHandle) async {
        switch message {
        case let .clipboardSync(enabled):
            MacClipboardSync.shared.setSync(enabled, for: connection, id: connection.id)

        case let .setClipboard(text, paste):
            MacClipboardSync.shared.setClipboard(text, paste: paste, from: connection.id)
            MenuBarActivity.shared.noteReceive() // UX Mac lane: the menu-bar hand's receive beam

        case .macClipboard:
            break // Mac → remote only

        case let .transferStatus(transferID, status):
            // S1: the device's answer about something this Mac sent.
            MacTransferService.shared.receivedStatus(status, for: transferID, from: connection.id)
        }
    }
}
