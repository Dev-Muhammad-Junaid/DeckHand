//
//  InputMessage.swift
//  PixelHandCore
//
//  Domain: input. Pointer, scroll, clicks, drags, key chords, typed text
//  and media keys. Remote → Mac. Owned by the iOS interaction lane (remote side) and the
//  Mac system control lane (`InputHandler`).
//

import Foundation

public enum InputMessage: Codable, Sendable, Equatable {
    /// Relative pointer movement in points.
    case mouseDelta(dx: Float, dy: Float)
    /// Continuous scroll delta tagged with a `ScrollPhase` so the host can
    /// emit native trackpad-style scroll events (with rubber-banding and
    /// momentum) instead of unphased mouse-wheel ticks.
    case mouseScroll(dx: Float, dy: Float, phase: ScrollPhase)
    case mouseClick(button: MouseButton)
    case mouseDoubleClick(button: MouseButton)
    /// Presses `button` and holds it: the pointer moves that follow are
    /// drags until `mouseUp`. A remote that keeps the button down repeats
    /// this every `DragPolicy.keepDownInterval` as a keep-alive; the Mac
    /// releases a button nobody refreshed for `DragPolicy.hostReleaseAfter`,
    /// and every held button when the remote disconnects.
    case mouseDown(button: MouseButton)
    /// Releases a button pressed with `mouseDown`. Releasing a button that
    /// isn't held does nothing.
    case mouseUp(button: MouseButton)
    /// A key chord such as `["cmd", "shift", "p"]`, posted to whatever app
    /// is frontmost.
    case keyboardShortcut(keys: [String])
    /// Text typed into whatever app is frontmost, as the characters
    /// themselves (any language, emoji included). `\n` presses Return and
    /// `\t` presses Tab. A remote sends long text in pieces of at most
    /// `TextChunker.defaultChunkBytes`; the Mac drops a message over
    /// `TypingPolicy.maxMessageBytes`.
    case typeText(text: String)
    /// A hardware media key.
    case media(key: MediaKey)
    /// Live text sync (protocol 17): replace a range of the Mac's focused
    /// field, as of a revision. The Mac selects the range and types the
    /// replacement (never sets `AXValue`), or answers `conflict`.
    case textEdit(edit: TextEditRequest)
    /// Live text sync (protocol 17): put the Mac's caret or selection in
    /// its focused field.
    case textSelect(selection: TextSelectRequest)
    /// Arrow presses the Mac coalesces (the arrow joystick, the blind
    /// trackpad). Refused under secure input. Protocol 17.
    case caretMove(move: CaretMove)
}

public enum MouseButton: String, Codable, Sendable, CaseIterable {
    case left, right, middle
}

/// The media keys a remote can press.
public enum MediaKey: String, Codable, Sendable, CaseIterable {
    case playPause = "playpause"
    case next
    case previous = "prev"
}
