//
//  MirrorHandler.swift
//  DeckHandMac
//
//  Domain: mirror and displays. Starts and stops the live mirror for a
//  connection; frames and the cursor go out on the binary mirror stream
//  (`MirrorStreamService`, `DeckHandMac/Mirror/`). Owned by the mirror lane (`MirrorStreamService`, S3, S5, S6,
//  the display picker, S14, S16).
//

import CoreGraphics
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

        case let .moveCursor(displayID):
            // Only displays the Mac has: CGDisplayBounds of an unknown id
            // is empty and would park the pointer at the origin.
            guard Self.activeDisplayIDs().contains(displayID) else { return }
            InputInjector.shared.moveCursorToCenter(ofDisplay: CGDirectDisplayID(displayID))

        case .displayList, .error:
            break // Mac → remote only
        }
    }

    private static func activeDisplayIDs() -> [UInt32] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
