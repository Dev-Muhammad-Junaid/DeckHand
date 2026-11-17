//
//  InputMessage.swift
//  PixelHandCore
//
//  Domain: input. Pointer, scroll, clicks, key chords and media keys.
//  Remote → Mac. Owned by the iOS interaction lane (remote side) and the
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
    /// A key chord such as `["cmd", "shift", "p"]`, posted to whatever app
    /// is frontmost.
    case keyboardShortcut(keys: [String])
    /// A hardware media key.
    case media(key: MediaKey)
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
