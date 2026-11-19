//
//  SharingMessage.swift
//  PixelHandCore
//
//  Domain: sharing. Clipboard text sync (S10), both ways, text only, up to
//  `ClipboardPolicy.maxTextBytes`. Files and links between paired devices
//  come later; large payloads will go through Loom's transfer engine, not
//  this envelope.
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
}
