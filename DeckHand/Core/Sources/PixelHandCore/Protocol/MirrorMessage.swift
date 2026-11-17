//
//  MirrorMessage.swift
//  PixelHandCore
//
//  Domain: mirror and displays. The live mirror's control messages and the
//  display list. Both ways. Owned by the mirror lane (`MirrorHandler`,
//  `MirrorStreamService`, the remote's mirror views).
//
//  Frames ride this control stream as JPEG for now (`frame`). The binary
//  mirror stream (S5) will carry frames on their own Loom stream framed by
//  `BinaryFrameHeader`; when it lands, `frame` goes and a negotiation
//  message (and the `ProtocolFeature.binaryMirrorStream` flag) takes its
//  place.
//

import Foundation

public enum MirrorMessage: Codable, Sendable, Equatable {
    // MARK: Remote → Mac

    /// Start streaming frames. `fps` caps the capture rate, `maxWidth`
    /// bounds the longest frame edge, and `displayID` picks a monitor
    /// (`nil` or unknown: the main display).
    case start(fps: Int, maxWidth: Int, displayID: UInt32?)
    /// Stop the stream. Also implied by disconnecting.
    case stop

    // MARK: Mac → remote

    /// One JPEG frame. `seq` increases within a stream; frames are
    /// independent, so any may be dropped.
    case frame(seq: UInt64, data: Data)
    /// The displays the Mac can mirror and the one the stream shows. Sent
    /// when a mirror starts and when screens change.
    case displayList(displays: [DisplayInfo], selectedDisplayID: UInt32)
    /// The mirror couldn't start or stopped (Screen Recording off, capture
    /// failed). Version 1 sent this as a `screenshotError` with the request
    /// id "mirror".
    case error(message: String)
}
