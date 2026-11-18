//
//  MirrorMessage.swift
//  PixelHandCore
//
//  Domain: mirror and displays. The live mirror's control messages and the
//  display list. Both ways. Owned by the mirror lane (`MirrorHandler`,
//  `MirrorStreamService`, the remote's mirror views).
//
//  Frames don't travel here. After `start`, the Mac opens the Loom stream
//  `PixelHandStream.mirror` towards the remote and sends video and the
//  cursor on it, framed by `BinaryFrameHeader` (protocol 3 removed the JSON
//  `frame`). The host announces this with
//  `ProtocolFeature.binaryMirrorStream`.
//

import Foundation

public enum MirrorMessage: Codable, Sendable, Equatable {
    // MARK: Remote → Mac

    /// Start streaming frames on `PixelHandStream.mirror`. `fps` caps the
    /// capture rate, `maxWidth` bounds the frame's width, and `displayID`
    /// picks a monitor (`nil` or unknown: the main display). Sent again to
    /// change any of them; the Mac reuses the stream.
    case start(fps: Int, maxWidth: Int, displayID: UInt32?)
    /// Stop the stream. Also implied by disconnecting.
    case stop

    // MARK: Mac → remote

    /// The displays the Mac can mirror and the one the stream shows. Sent
    /// when a mirror starts and when screens change.
    case displayList(displays: [DisplayInfo], selectedDisplayID: UInt32)
    /// The mirror couldn't start or stopped (Screen Recording off, capture
    /// failed). Version 1 sent this as a `screenshotError` with the request
    /// id "mirror".
    case error(message: String)
}
