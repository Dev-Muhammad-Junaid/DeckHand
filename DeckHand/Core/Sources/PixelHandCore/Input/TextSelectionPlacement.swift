//
//  TextSelectionPlacement.swift
//  PixelHandCore
//
//  Live text sync (protocol 17): how the Mac puts its caret where an edit
//  or a `textSelect` says, before anything is typed (`RD-live-sync-and-caret.md`
//  §1.2 "C. Select, then type"; build 29 bug 9).
//
//  The Mac runs a loop: read the field, ask `next` what to do, do it, read
//  again. A step only counts when a fresh read shows the caret there:
//
//  1. Accessibility (`kAXSelectedTextRangeAttribute`) where it's settable,
//     up to `maxAccessibilityTries` times. An app may answer "success" and
//     not move (or move after its pending keys): only the read counts.
//  2. Otherwise, or when that didn't take, ←/→ (⇧→ to select) from the
//     caret the Mac **read** (never a guessed one), up to `maxArrowRounds`
//     rounds: a round that drifts (soft wraps, hidden text) is corrected
//     from where it ended up.
//  3. Otherwise `fail`: the Mac types nothing and refuses the edit, and
//     the iPad says so. Typing at a guessed position is what put build
//     29's text at the end of the document.
//
//  `landed` tells the Mac its typing has reached the field (the keys it
//  posted are consumed, not just posted), so the answer and the next edit
//  never race keys still in the app's queue.
//

import Foundation

public enum TextSelectionPlacement {
    public enum Step: Equatable, Sendable {
        /// The caret is there.
        case done
        /// Set `kAXSelectedTextRangeAttribute`, then read again.
        case accessibility
        /// Press these chords, wait for them, then read again.
        case arrows([[String]])
        /// It can't be placed: type nothing.
        case fail
    }

    /// What was tried so far for one placement.
    public struct Attempts: Equatable, Sendable {
        public var accessibility = 0
        public var arrows = 0

        public init(accessibility: Int = 0, arrows: Int = 0) {
            self.accessibility = accessibility
            self.arrows = arrows
        }
    }

    public static let maxAccessibilityTries = 2
    public static let maxArrowRounds = 2

    /// The next step to put the caret at `target`, from a fresh read:
    /// `current` is the field's selection as read (`nil` when the app
    /// didn't say), `window` the text around it.
    public static func next(
        target: TextRange,
        current: TextRange?,
        canSetSelection: Bool,
        window: TextWindow?,
        attempts: Attempts
    ) -> Step {
        if let current, current == target { return .done }
        if canSetSelection, attempts.accessibility < maxAccessibilityTries {
            return .accessibility
        }
        guard let current, let window, attempts.arrows < maxArrowRounds,
              let chords = TextSyncPolicy.arrowChords(window: window.value, windowStart: window.start, from: current, to: target),
              !chords.isEmpty else {
            return .fail
        }
        return .arrows(chords)
    }

    /// Whether typing `replacement` over `range` has reached the field:
    /// its length and caret are what the edit makes, and the replacement
    /// is there when the window shows that part. (The Mac's own
    /// autocorrect can change it; the Mac stops waiting after a moment.)
    public static func landed(range: TextRange, replacement: String, lengthBefore: Int, after: FocusedTextState) -> Bool {
        let units = replacement.utf16.count
        guard after.length == lengthBefore - range.length + units,
              after.selection == .caret(range.start + units) else { return false }
        if let window = after.window, range.start >= window.start, range.start + units <= window.end,
           let typed = TextUnits.substring(window.value, TextRange(start: range.start - window.start, length: units)) {
            return typed == replacement
        }
        return true
    }
}
