//
//  HeaderAskButton.swift
//  PixelHandCore – Design
//
//  The header's compact ⌘K button (owner testing, build 27, OT-18). It
//  replaces the wide "Tell <Mac>…" field, which had alignment issues and
//  only ever opened Ask: the button does exactly that (Ask in the right
//  column where there is one, else the Ask sheet), keeps ⌘K, and shows
//  when Ask is already open in the column, and lit while its field has
//  focus.
//
//  A command palette is not built (the owner decides later). It would plug
//  in at `HeaderAskButton.Command`: ⌘K and the button would open the
//  palette instead of Ask, with Ask as the palette's first command (typing
//  without picking a command falls through to Ask).
//

import Foundation

public enum HeaderAskButton {
    /// What ⌘K (and the button) does today. A palette would add a case.
    public enum Command: Equatable, Sendable {
        /// Ask in the right column (expanding it) or the Ask sheet.
        case ask
    }

    /// The command ⌘K runs.
    public static let command = Command.ask

    /// The key with ⌘.
    public static let key: Character = "k"
    /// The chord as shown on the button.
    public static let chord = "⌘K"
    /// The pointer and long-press tooltip.
    public static let tooltip = "Ask (⌘K)"

    /// What the button shows.
    public enum State: Equatable, Sendable {
        /// Ask isn't showing: the glyph and ⌘K in ink.
        case idle
        /// Ask is showing in the right column, its field not focused.
        case open
        /// Ask is showing and its field has focus: lit (accent) and
        /// selected.
        case active

        /// Lit in the accent colour.
        public var isLit: Bool { self == .active }
        /// Selected for VoiceOver.
        public var isSelected: Bool { self != .idle }

        /// VoiceOver's value.
        public var spokenValue: String {
            switch self {
            case .idle: ""
            case .open: "Open"
            case .active: "Open, typing"
            }
        }
    }

    /// The state from the right column: whether it shows Ask (expanded,
    /// mode Ask) and whether Ask's field has focus.
    public static func state(columnShowsAsk: Bool, fieldFocused: Bool) -> State {
        guard columnShowsAsk else { return .idle }
        return fieldFocused ? .active : .open
    }

    // MARK: Size

    /// The button: a 44 pt glass capsule, 12 inset, the Ask glyph, an 8 gap
    /// and the ⌘K chord. 80 pt wide on the grid.
    public static let width = 80.0
    /// When the header's row has no room for the capsule: a 44 circle.
    public static let compactWidth = 44.0
    /// What the header's row reserves for it (the button and its 8 gap).
    public static let reservedWidth = width + 8
}
