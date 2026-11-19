//
//  RemoteInputValidation.swift
//  PixelHandCore
//
//  The one place the Mac checks every number a remote sends before it
//  reaches CoreGraphics, ScreenCaptureKit or an integer conversion. A remote
//  is a peer on the network, not trusted code: `Int32(-dy * 3)` used to trap
//  (and take the whole host down) on a scroll of 1e9, and JSON can carry
//  any value up to `Float.greatestFiniteMagnitude`.
//
//  Rules: non-finite values drop the message, finite values are clamped to
//  a range no real gesture exceeds. Nothing here can trap.
//

import Foundation

public enum RemoteInputValidation {
    /// Largest pointer delta (points) accepted in one `mouseDelta`. A fast
    /// swipe at 120 Hz sends well under 200.
    public static let maxPointerDelta: Float = 2_000
    /// Largest scroll delta accepted in one `mouseScroll`.
    public static let maxScrollDelta: Float = 10_000
    /// Bounds for `startMirror`. The mirror service applies the same caps;
    /// they're repeated here so this layer is complete on its own.
    public static let mirrorFPSRange: ClosedRange<Int> = 1...30
    public static let mirrorWidthRange: ClosedRange<Int> = 120...1920

    // MARK: - Message-level entry point

    /// Returns `message` with every remote-supplied number made safe, or
    /// `nil` when the message must be dropped (a non-finite float, an empty
    /// capture region, a string or list past `ProtocolLimits`, typed text
    /// over `TypingPolicy.maxMessageBytes` or empty once cleaned, clipboard
    /// text over `ClipboardPolicy.maxTextBytes`). Messages without numbers
    /// or strings (`mouseDown`, `mouseUp`, `clipboardSync`) pass through
    /// unchanged.
    public static func sanitize(_ message: ControlMessage) -> ControlMessage? {
        switch message {
        case let .input(.mouseDelta(dx, dy)):
            guard let safeDX = clamp(dx, limit: maxPointerDelta),
                  let safeDY = clamp(dy, limit: maxPointerDelta) else { return nil }
            return .input(.mouseDelta(dx: safeDX, dy: safeDY))

        case let .input(.mouseScroll(dx, dy, phase)):
            guard let safeDX = clamp(dx, limit: maxScrollDelta),
                  let safeDY = clamp(dy, limit: maxScrollDelta) else { return nil }
            return .input(.mouseScroll(dx: safeDX, dy: safeDY, phase: phase))

        case let .input(.keyboardShortcut(keys)):
            return isAcceptableChord(keys) ? message : nil

        case let .input(.typeText(text)):
            // Control characters other than Return and Tab never become
            // key presses; empty or oversize text is dropped.
            guard text.utf8.count <= TypingPolicy.maxMessageBytes else { return nil }
            let clean = TypingText.normalized(text)
            guard !clean.isEmpty else { return nil }
            return .input(.typeText(text: clean))

        case let .sharing(.setClipboard(text, paste)):
            guard ClipboardPolicy.isAcceptable(remoteText: text) else { return nil }
            return .sharing(.setClipboard(text: text, paste: paste))

        case .sharing(.macClipboard):
            // Mac → remote only; a remote has no business sending it.
            return nil

        case let .apps(.launchApp(bundleID)):
            return isAcceptable(bundleID) ? message : nil

        case let .apps(.appShortcut(bundleID, keys)):
            return isAcceptable(bundleID) && isAcceptableChord(keys) ? message : nil

        case let .apps(.triggerContextAction(id)):
            return isAcceptable(id) ? message : nil

        case let .deck(.requestAppMenuShortcuts(bundleID)):
            return isAcceptable(bundleID) ? message : nil

        case let .capture(.requestScreenshot(requestID, mode, quality)):
            guard isAcceptable(requestID), let safeMode = sanitize(mode) else { return nil }
            return .capture(.requestScreenshot(requestID: requestID, mode: safeMode, quality: quality))

        case let .capture(.requestWindowList(requestID)):
            return isAcceptable(requestID) ? message : nil

        case let .mirror(.start(fps, maxWidth, displayID, codec, windowID)):
            return .mirror(.start(
                fps: clamp(fps, to: mirrorFPSRange),
                maxWidth: clamp(maxWidth, to: mirrorWidthRange),
                displayID: displayID,
                codec: codec,
                // S14: 0 is never a CGWindowID; read it as "a display".
                windowID: windowID == 0 ? nil : windowID
            ))

        case let .diagnostics(.mirrorClientStats(stats)):
            return .diagnostics(.mirrorClientStats(stats: stats.sanitized()))

        case let .deck(.run(requestID, action)):
            guard isAcceptable(requestID), isAcceptable(action) else { return nil }
            return message

        case let .pairing(.submitCode(code)):
            // Pairing lane (S4): a code is a few digits; the Mac reads it
            // with PairingCodeWindow, which counts anything invalid as a guess.
            return code.utf8.count <= PairingCode.maxInputLength ? message : nil

        default:
            return message
        }
    }

    /// An action from a remote (`deck.run`). The first six are checked as
    /// the message they stand for, a step of a sequence too; every Deck 2
    /// string and number is bounded by `ActionValidation`: bundle IDs,
    /// menu paths (≤ 6 titles of ≤ 256 bytes, no control characters),
    /// Shortcuts names (≤ 256 bytes, no control characters, no leading
    /// `-`), sequences (1…20 steps, no nesting, no dialog presses, pauses
    /// 0…10 000 ms and ≤ 30 000 ms in all). Anything outside is dropped
    /// whole: a run is never partly run.
    public static func isAcceptable(_ action: Action) -> Bool {
        guard ActionValidation.isValid(action, storable: false) else { return false }
        switch action {
        case let .sequence(steps):
            return steps.allSatisfy { step in
                guard let inner = step.action else { return true }
                return isAcceptable(inner)
            }
        case .menuCommand, .macShortcut:
            return true
        case .shortcut, .appShortcut, .launchApp, .system, .media, .contextAction:
            guard let domain = action.message else { return false }
            return sanitize(domain) == domain
        }
    }

    /// A string from a remote: not longer than `ProtocolLimits.maxStringLength`.
    public static func isAcceptable(_ string: String) -> Bool {
        string.utf8.count <= ProtocolLimits.maxStringLength
    }

    /// A key chord from a remote: at most `ProtocolLimits.maxChordKeys` keys,
    /// each a short name.
    public static func isAcceptableChord(_ keys: [String]) -> Bool {
        keys.count <= ProtocolLimits.maxChordKeys && keys.allSatisfy { $0.utf8.count <= 32 }
    }

    /// Region captures must lie inside the display (0…1) and be non-empty.
    /// The region is intersected with the unit square rather than rejected,
    /// so a crop dragged slightly past the edge still works.
    public static func sanitize(_ mode: CaptureMode) -> CaptureMode? {
        guard case let .region(x, y, width, height) = mode else { return mode }
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else { return nil }
        // Already inside: return it untouched, since recomputing the size
        // from the clipped edges can shift it by a Float rounding step.
        if x >= 0, y >= 0, x + width <= 1, y + height <= 1 { return mode }
        let minX = max(0, min(1, x))
        let minY = max(0, min(1, y))
        let maxX = max(0, min(1, x + width))
        let maxY = max(0, min(1, y + height))
        guard maxX > minX, maxY > minY else { return nil }
        return .region(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Primitives

    /// `nil` for NaN/±∞, otherwise `value` clamped to `-limit…limit`.
    public static func clamp(_ value: Float, limit: Float) -> Float? {
        guard value.isFinite else { return nil }
        return max(-limit, min(limit, value))
    }

    public static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, min(range.upperBound, value))
    }

    /// Converts a scroll delta to the wheel units `CGEvent` takes
    /// (`-delta * 3`, natural direction). Never traps: non-finite input is
    /// 0 and the result is clamped to `Int32`'s range. `InputInjector` uses
    /// this as a second line of defence behind `sanitize`.
    public static func wheelUnits(forScrollDelta delta: Float) -> Int32 {
        guard delta.isFinite else { return 0 }
        let units = (-Double(delta) * 3).rounded(.towardZero)
        if units >= Double(Int32.max) { return .max }
        if units <= Double(Int32.min) { return .min }
        return Int32(units)
    }
}
