//
//  FocusReading.swift
//  PixelHandCore
//
//  The Mac's rules for reading the focused field (OT-12, OT-13), kept pure
//  so they are tested here: which Accessibility roles count as text, when
//  the field's text may be read at all, the window of text sent around the
//  caret, which display a global rect is on, when a new reading is worth
//  sending, and how often to look.
//
//  OT-13 (inline suggestions). What Accessibility gives, by kind of field:
//
//  - Native AppKit fields (`NSTextField` / `NSTextView`: `AXTextField`,
//    `AXTextArea`): `AXValue`, `AXSelectedTextRange`, `AXNumberOfCharacters`
//    and `AXStringForRange` / `AXBoundsForRange` are reliable. macOS 14's
//    inline predictions are drawn by the text system as a temporary
//    completion that is not part of the text storage, so they are not in
//    `AXValue`, and no documented attribute exposes them.
//  - Web content (Safari/WebKit, Chrome, Electron apps such as the Claude
//    desktop app: `AXWebArea` and its `contenteditable` / `<textarea>`
//    descendants): value and selection come through text markers and are
//    usable, but ghost text is whatever the page draws, usually a styled
//    `<span>` or an overlay outside the editable text. It shows up, if at
//    all, as an ordinary static-text child or as part of the value, with
//    nothing that tells it apart from typed text across apps.
//
//  So `FocusedText.suggestion` stays `nil`: there is no source that is
//  reliable across apps. Text is read only from native, non-secure fields.
//

import Foundation

public enum FocusReading {
    /// Most UTF-16 units of the field's text sent around the caret.
    public static let maxTextLength = 1_000
    /// Rects that moved less than this (points) count as unchanged.
    public static let tolerance: Double = 0.75
    /// Side of the square sent around the pointer.
    public static let pointerSize: Double = 24

    // MARK: Roles and privacy

    /// The snapshot's role for an Accessibility role and subrole.
    public static func role(axRole: String?, axSubrole: String?) -> FocusedFieldSnapshot.Role {
        switch axRole {
        case "AXTextField", "AXSecureTextField", "AXSearchField":
            return .textField
        case "AXTextArea":
            return .textArea
        case "AXComboBox":
            return .comboBox
        case "AXWebArea":
            return .webArea
        default:
            return .other
        }
    }

    /// Whether the element is a password field: its role or subrole is
    /// `AXSecureTextField`, or either names something secure. Checked
    /// before any value is read, never after.
    public static func isSecure(axRole: String?, axSubrole: String?) -> Bool {
        for name in [axRole, axSubrole].compactMap({ $0 }) {
            let lower = name.lowercased()
            if lower.contains("secure") || lower.contains("password") { return true }
        }
        return false
    }

    /// Whether the field's text may be read and sent: a native text role
    /// (not web content, whose text Pixel Hand doesn't read), not a
    /// password field, on an unlocked Mac.
    public static func mayReadText(axRole: String?, axSubrole: String?, inWebContent: Bool, lock: MacLockState) -> Bool {
        guard !lock.isLocked, !inWebContent, !isSecure(axRole: axRole, axSubrole: axSubrole) else { return false }
        switch role(axRole: axRole, axSubrole: axSubrole) {
        case .textField, .textArea, .comboBox:
            return true
        case .webArea, .other:
            return false
        }
    }

    // MARK: Text around the caret

    /// The UTF-16 range of a field of `count` units to read for a caret or
    /// selection starting at `selectionStart`: the whole
    /// field when it fits `limit`, else `limit` units with the selection's
    /// start near the middle (a third before, two thirds after), slid to
    /// stay inside the field.
    public static func textWindow(count: Int, selectionStart: Int, limit: Int = maxTextLength) -> (location: Int, length: Int) {
        let count = max(0, count)
        let limit = max(1, limit)
        guard count > limit else { return (0, count) }
        let caret = min(max(0, selectionStart), count)
        let before = limit / 3
        let start = min(max(0, caret - before), count - limit)
        return (start, limit)
    }

    /// The text to send: `window` is the field's text read at
    /// `windowLocation` from a field of `totalCount` units, the selection in
    /// field offsets. The selection is made relative to `window` and
    /// clamped into it; `window` itself is cut to `limit` units on whole
    /// characters if a reader returned more.
    public static func text(
        window: String,
        windowLocation: Int,
        totalCount: Int,
        selectionStart: Int,
        selectionLength: Int,
        limit: Int = maxTextLength
    ) -> FocusedText {
        var value = window
        if value.utf16.count > limit {
            var cut = ""
            var units = 0
            for character in value {
                let n = String(character).utf16.count
                if units + n > limit { break }
                cut.append(character)
                units += n
            }
            value = cut
        }
        let length = value.utf16.count
        let start = min(max(0, selectionStart - windowLocation), length)
        let end = min(max(start, selectionStart - windowLocation + max(0, selectionLength)), length)
        return FocusedText(
            value: value,
            selection: FocusedText.Selection(start: start, length: end - start),
            truncatedBefore: windowLocation > 0,
            truncatedAfter: windowLocation + length < totalCount,
            suggestion: nil
        )
    }

    // MARK: Caret from neighbouring characters

    /// A 1 pt caret at the trailing edge of the character before it, for
    /// apps that give an empty rect for a zero-length range.
    public static func caret(after character: FocusRect) -> FocusRect {
        FocusRect(x: character.maxX, y: character.y, width: 1, height: character.height)
    }

    /// A 1 pt caret at the leading edge of the character after it.
    public static func caret(before character: FocusRect) -> FocusRect {
        FocusRect(x: character.x, y: character.y, width: 1, height: character.height)
    }

    /// Whether an Accessibility rect is usable: finite, inside a sane
    /// range, not at the global origin with no size (what many apps
    /// answer for "don't know").
    public static func isUsable(_ rect: FocusRect) -> Bool {
        guard rect.isValid, abs(rect.x) < 100_000, abs(rect.y) < 100_000,
              rect.width < 100_000, rect.height < 100_000 else { return false }
        return !(rect.x == 0 && rect.y == 0 && rect.width == 0 && rect.height == 0) && rect.height > 0
    }

    // MARK: Displays

    /// A display: its id and its bounds in Quartz's global space (points,
    /// origin at the main display's top-left, y down), as `CGDisplayBounds`.
    public struct Display: Sendable, Hashable {
        public var id: UInt32
        public var bounds: FocusRect

        public init(id: UInt32, bounds: FocusRect) {
            self.id = id
            self.bounds = bounds
        }
    }

    /// The display a global rect is on: the one it overlaps most, else the
    /// one containing its centre, else the nearest. `nil` without displays.
    public static func display(for rect: FocusRect, among displays: [Display]) -> Display? {
        guard !displays.isEmpty, rect.isValid else { return nil }
        var best: (display: Display, area: Double)?
        for display in displays {
            let b = display.bounds
            let w = min(rect.maxX, b.maxX) - max(rect.minX, b.minX)
            let h = min(rect.maxY, b.maxY) - max(rect.minY, b.minY)
            let area = (w > 0 && h > 0) ? w * h : 0
            if area > 0, area > (best?.area ?? 0) { best = (display, area) }
        }
        if let best { return best.display }
        // Zero-size rects (a caret, a point) and rects off every display.
        func distance(_ b: FocusRect) -> Double {
            let dx = max(b.minX - rect.midX, 0, rect.midX - b.maxX)
            let dy = max(b.minY - rect.midY, 0, rect.midY - b.maxY)
            return dx * dx + dy * dy
        }
        return displays.min { distance($0.bounds) < distance($1.bounds) }
    }

    /// `rect` (global) in `display`'s local points.
    public static func local(_ rect: FocusRect, on display: Display) -> FocusRect {
        FocusRect(x: rect.x - display.bounds.x, y: rect.y - display.bounds.y, width: rect.width, height: rect.height)
    }

    // MARK: Sending

    /// Whether `new` is worth sending after `old`: anything but the rects
    /// changed, or a rect moved or resized by more than `tolerance` points.
    public static func differsMeaningfully(_ new: FocusedFieldSnapshot, from old: FocusedFieldSnapshot?, tolerance: Double = tolerance) -> Bool {
        guard let old else { return true }
        if new.displayID != old.displayID || new.source != old.source || new.role != old.role
            || new.app != old.app || new.text != old.text
            || new.displayWidth != old.displayWidth || new.displayHeight != old.displayHeight {
            return true
        }
        return moved(new.field, old.field, tolerance)
            || moved(new.caret, old.caret, tolerance)
            || moved(new.pointer, old.pointer, tolerance)
    }

    private static func moved(_ a: FocusRect?, _ b: FocusRect?, _ tolerance: Double) -> Bool {
        switch (a, b) {
        case (nil, nil): return false
        case let (a?, b?):
            return abs(a.x - b.x) > tolerance || abs(a.y - b.y) > tolerance
                || abs(a.width - b.width) > tolerance || abs(a.height - b.height) > tolerance
        default: return true
        }
    }

    // MARK: Pacing

    /// How long to wait before the next look: 125 ms (8 a second) while
    /// things change, 250 ms once nothing has changed for 2 s.
    public static func pollInterval(unchangedFor seconds: Double) -> Double {
        seconds >= 2 ? 0.25 : 0.125
    }
}
