//
//  RemoteClipboard.swift
//  DeckHandiOS
//
//  S10 on the remote. With Share Clipboard on (Settings), text copied on
//  the Mac arrives as `sharing.macClipboard` and is put on this device's
//  clipboard, ready to paste. Writing the clipboard asks nothing; reading
//  it would show iOS's paste prompt, so this app never reads it by
//  itself: Paste to Mac is the system paste control (`UIPasteControl`),
//  which the person taps, and which asks nothing either.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class RemoteClipboard {
    /// The start of the last text that came from the Mac, for the panel.
    private(set) var lastFromMac: String?
    private(set) var lastFromMacAt: Date?
    /// A short line about the last Paste to Mac.
    private(set) var pasteStatus: String?

    /// Text the Mac copied. Put on this device's clipboard while sync is on.
    func receivedFromMac(_ text: String, syncEnabled: Bool) {
        guard syncEnabled, ClipboardPolicy.isAcceptable(remoteText: text) else { return }
        UIPasteboard.general.string = text
        lastFromMac = Self.preview(text)
        lastFromMacAt = Date()
    }

    /// The person pasted `text` into Paste to Mac.
    func pasteToMac(_ text: String, paste: Bool, sender: TrackpadSender) {
        guard ClipboardPolicy.isAcceptable(remoteText: text) else {
            pasteStatus = text.isEmpty
                ? "Nothing to paste: the clipboard has no text."
                : "Too long to send: the Mac takes up to \(ClipboardPolicy.maxTextBytes / 1024) KB of text."
            return
        }
        pasteStatus = paste ? "Pasted on the Mac." : "On the Mac's clipboard: press ⌘V there."
        Task { await sender.setMacClipboard(text, paste: paste) }
    }

    private static func preview(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }
}
