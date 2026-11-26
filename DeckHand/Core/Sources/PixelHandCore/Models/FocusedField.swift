//
//  FocusedField.swift
//  PixelHandCore
//
//  Where the Mac's focused text field is, for the Type panel's loupe
//  (owner testing build 26, OT-12), and what it holds, for OT-13. The Mac
//  sends it as `system.focusState(focus:)` while a remote watches
//  (`system.watchFocus(on: true)`), at most about eight times a second and
//  only when something changed (`FocusReading.differsMeaningfully`).
//
//  Every rect is in the display's points with the origin at that display's
//  top-left corner, y down (Quartz's global space, made display-local), so
//  `FocusLoupe` maps it onto the mirror with one division.
//

import Foundation

/// A rectangle in a display's points, origin at the display's top-left,
/// y down.
public struct FocusRect: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// Every number finite and the size not negative.
    public var isValid: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite && width >= 0 && height >= 0
    }

    /// A rect of `size` × `size` centred on a point (the pointer's rect).
    public static func around(x: Double, y: Double, size: Double) -> FocusRect {
        FocusRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }
}

/// What the Mac reports about its focused text field.
public struct FocusedFieldSnapshot: Codable, Sendable, Hashable {
    /// Where the rects came from.
    public enum Source: String, Codable, Sendable, Hashable {
        /// The focused element's frame from Accessibility (and the caret,
        /// when the app reports it).
        case accessibility
        /// Accessibility gave no frame (many web and Electron fields): only
        /// `pointer` is set, and the loupe zooms around it.
        case pointer
        /// Nothing to show: no focused element and no pointer, or the Mac
        /// is locked (everything else is `nil` then).
        case none
    }

    /// The focused element's kind, from its Accessibility role.
    public enum Role: String, Codable, Sendable, Hashable {
        /// `AXTextField` (search fields included).
        case textField
        /// `AXTextArea`: multi-line text, web `contenteditable` in most
        /// browsers.
        case textArea
        case comboBox
        /// `AXWebArea`: a whole web document has focus (some editors).
        case webArea
        case other
    }

    /// The display the field is on (`CGDirectDisplayID`).
    public var displayID: UInt32
    /// That display's size in points.
    public var displayWidth: Double
    public var displayHeight: Double
    /// The focused element's frame, `nil` when Accessibility gave none.
    public var field: FocusRect?
    /// The caret (or the selection's bounds), `nil` when the app doesn't
    /// report it. Often 0–1 pt wide.
    public var caret: FocusRect?
    /// A small square around the pointer, so a remote can fall back to it.
    public var pointer: FocusRect?
    public var source: Source
    /// The app in front, by name.
    public var app: String?
    public var role: Role
    /// The field's text near the caret: only for native, non-secure fields
    /// on an unlocked Mac (`FocusReading.mayReadText`), else `nil`.
    public var text: FocusedText?

    public init(
        displayID: UInt32,
        displayWidth: Double,
        displayHeight: Double,
        field: FocusRect?,
        caret: FocusRect?,
        pointer: FocusRect?,
        source: Source,
        app: String?,
        role: Role,
        text: FocusedText?
    ) {
        self.displayID = displayID
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.field = field
        self.caret = caret
        self.pointer = pointer
        self.source = source
        self.app = app
        self.role = role
        self.text = text
    }

    /// "Nothing to show" on `displayID`: sent while the Mac is locked and
    /// when nothing is focused and the pointer can't be read.
    public static func nothing(displayID: UInt32, displayWidth: Double, displayHeight: Double) -> FocusedFieldSnapshot {
        FocusedFieldSnapshot(
            displayID: displayID,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            field: nil,
            caret: nil,
            pointer: nil,
            source: .none,
            app: nil,
            role: .other,
            text: nil
        )
    }
}

/// The focused field's text around the caret (OT-13).
public struct FocusedText: Codable, Sendable, Hashable {
    /// A selection in UTF-16 offsets into `value` (`NSRange` style).
    public struct Selection: Codable, Sendable, Hashable {
        public var start: Int
        public var length: Int

        public init(start: Int, length: Int) {
            self.start = start
            self.length = length
        }
    }

    /// At most `FocusReading.maxTextLength` UTF-16 units around the caret.
    public var value: String
    /// The caret (`length` 0) or the selection, relative to `value`.
    public var selection: Selection
    /// The field has more text before / after `value`.
    public var truncatedBefore: Bool
    public var truncatedAfter: Bool
    /// An inline suggestion the app shows at the caret (ghost text). No app
    /// exposes one reliably through Accessibility today, so the Mac always
    /// sends `nil`; see the OT-13 notes in `FocusReading`.
    public var suggestion: String?

    public init(value: String, selection: Selection, truncatedBefore: Bool, truncatedAfter: Bool, suggestion: String?) {
        self.value = value
        self.selection = selection
        self.truncatedBefore = truncatedBefore
        self.truncatedAfter = truncatedAfter
        self.suggestion = suggestion
    }
}
