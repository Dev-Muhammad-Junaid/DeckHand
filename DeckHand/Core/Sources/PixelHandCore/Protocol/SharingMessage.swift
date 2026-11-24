//
//  SharingMessage.swift
//  PixelHandCore
//
//  Domain: sharing. Clipboard text sync (S10), both ways, text only, up to
//  `ClipboardPolicy.maxTextBytes`.
//
//  Transfers (S1, protocol 13): files, photos, links and text between
//  paired devices, both ways. The bytes go through Loom's transfer engine
//  (its own control stream and one data stream per transfer; chunked,
//  resumable, SHA-256 checked), never this envelope; the item's kind rides
//  in the Loom offer's metadata (`TransferManifest`). This domain only
//  carries the receiver's app-level answer, `transferStatus`, which Loom's
//  accept / decline can't express: why it was refused (locked, not paired,
//  no Pro, too large, no space) and where it landed.
//
//  The Mac never sends its clipboard to a remote that hasn't asked for it
//  (`clipboardSync(enabled: true)`), never while it is locked, and never an
//  item a password manager marked concealed or transient. A remote never
//  reads its own clipboard by itself: the person pastes into it
//  (`UIPasteControl` on iOS), which sends `setClipboard`.
//

import Foundation

public enum SharingMessage: Codable, Sendable, Equatable {
    // MARK: Remote → Mac

    /// Turns sending the Mac's clipboard to this remote on or off. Off
    /// until the remote asks. While on, the Mac sends `macClipboard` at
    /// once (when it holds text) and on every change.
    case clipboardSync(enabled: Bool)
    /// Puts `text` on the Mac's clipboard. With `paste`, the Mac then
    /// presses ⌘V so it lands where the Mac's cursor is.
    case setClipboard(text: String, paste: Bool)

    // MARK: Mac → remote

    /// The text now on the Mac's clipboard.
    case macClipboard(text: String)

    // MARK: Both ways (S1)

    /// The receiver of transfer `transferID` (the Loom offer's id) tells
    /// the sender what became of it: asking its person, refused and why,
    /// saved and where, or failed. Sent by whichever side received the
    /// offer; a status for a transfer the sender doesn't know is ignored.
    case transferStatus(transferID: UUID, status: TransferStatus)
}
