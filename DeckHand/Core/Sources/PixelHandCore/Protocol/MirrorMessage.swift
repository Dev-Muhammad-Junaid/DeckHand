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
    /// capture rate, `maxWidth` bounds the frame's width, `displayID`
    /// picks a monitor (`nil` or unknown: the main display) and `codec`
    /// picks JPEG images or an HEVC stream (S5; see `Mirror/MirrorVideo.swift`).
    /// `windowID` (S14) streams that one window (a `CGWindowID` from
    /// `capture.windowListResponse`) instead of a display; `maxWidth` then
    /// bounds the window's frame, whose size follows the window. `nil`: a
    /// display. A window that is gone, or a Mac that is locked, falls back
    /// to a display (see `error`).
    /// Sent again to change any of them; the Mac reuses the stream.
    case start(fps: Int, maxWidth: Int, displayID: UInt32?, codec: MirrorCodec, windowID: UInt32?)
    /// Stop the stream. Also implied by disconnecting.
    case stop
    /// Move the Mac's pointer to the centre of `displayID` (the mirror's
    /// "Cursor is on …" badge brings the pointer to the mirrored display).
    /// Ignored for a display the Mac doesn't have.
    case moveCursor(displayID: UInt32)
    /// The HEVC picture broke on the remote (decode error, a delta it can't
    /// use, no picture for a while): send a key frame, with its parameter
    /// sets, soon. The Mac spaces forced key frames out
    /// (`MirrorKeyFramePolicy`). Ignored for a JPEG mirror.
    case requestKeyFrame

    // MARK: Mac → remote

    /// The displays the Mac can mirror and what the stream shows: the
    /// display `selectedDisplayID`, or, when `window` is set (S14), that
    /// window (`selectedDisplayID` is then the display it sits on, where the
    /// mirror falls back to). Sent when a mirror starts, when screens
    /// change, and when a mirrored window is resized.
    case displayList(displays: [DisplayInfo], selectedDisplayID: UInt32, window: MirroredWindow?)
    /// The mirror couldn't start or stopped (Screen Recording off, capture
    /// failed). Version 1 sent this as a `screenshotError` with the request
    /// id "mirror".
    ///
    /// With `fallbackDisplayID` (S14) the mirror did *not* stop: the window
    /// it showed closed, was minimised, or the Mac locked, and the stream
    /// now shows that display. The remote shows `message` as a notice and
    /// keeps the mirror open; a `displayList` follows.
    case error(message: String, fallbackDisplayID: UInt32? = nil)
}
