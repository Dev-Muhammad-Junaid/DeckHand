//
//  SharingHandler.swift
//  DeckHandMac
//
//  Domain: sharing. Clipboard text sync (S10), through `MacClipboardSync`.
//  Owned by the iOS interaction lane.
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

        case .macClipboard:
            break // Mac → remote only
        }
    }
}
