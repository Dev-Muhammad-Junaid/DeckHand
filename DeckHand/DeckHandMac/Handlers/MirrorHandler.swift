//
//  MirrorHandler.swift
//  DeckHandMac
//
//  Domain: mirror and displays. Starts and stops the live mirror for a
//  connection. Owned by the mirror lane (`MirrorStreamService`, S3, S5, S6,
//  the display picker, S14, S16).
//

import Foundation
import LoomKit

@MainActor
final class MirrorHandler: DomainHandler {
    func handle(_ message: MirrorMessage, from connection: LoomConnectionHandle) async {
        switch message {
        case let .start(fps, maxWidth, displayID):
            // SCShareableContent inside — the #1 hang candidate. Own task.
            let subscriberID = connection.id
            Task {
                await MirrorStreamService.shared.start(
                    subscriberID: subscriberID,
                    handle: connection,
                    fps: fps,
                    maxWidth: maxWidth,
                    displayID: displayID
                )
            }

        case .stop:
            let subscriberID = connection.id
            Task { await MirrorStreamService.shared.stop(subscriberID: subscriberID) }

        case .frame, .displayList, .error:
            break // Mac → remote only
        }
    }
}
