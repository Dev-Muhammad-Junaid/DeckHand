//
//  TypePanel.swift
//  PixelHandCore
//
//  The Type panel (owner testing, build 24, OT-3): how text and keys get
//  from the iPhone or iPad into the Mac. Pure rules, so they're tested on
//  Linux; `DeckHandiOS/Keyboard/TypePanel.swift` draws them.
//
//    Live      every key goes to the Mac as it's typed (the old keyboard
//              bar's behaviour, `TypingEdit` diffs).
//    Compose   type or dictate into a local field, read it, then Send it,
//              with or without a Return after it.
//
//  Under both: a keys row (esc, tab, ⌫, ⏎, arrows, home/end, page up/down,
//  F1–F12 behind the fn toggle), sticky ⌘ ⌥ ⌃ ⇧ chips, and a Numpad tab.
//  The panel's open/closed state has one owner (`TypePanelPresence`), and
//  where it sits is decided from the keyboard, never by moving the shell
//  (`TypePanelLayout`, OT-2).
//

import Foundation

// MARK: - Modes and tabs

/// How typed text reaches the Mac.
public enum TypeMode: String, Sendable, Hashable, CaseIterable, Codable {
    /// Each key goes to the Mac at once.
    case live
    /// Text waits in a local field until Send.
    case compose

    public var title: String {
        switch self {
        case .live: "Live"
        case .compose: "Compose"
        }
    }

    /// What VoiceOver reads for the mode switch.
    public var spokenHint: String {
        switch self {
        case .live: "Every key goes to the Mac as you type."
        case .compose: "Type or dictate here first, then send it to the Mac."
        }
    }

    /// The field's placeholder.
    public var placeholder: String {
        switch self {
        case .live: "Type: it goes straight to the Mac"
        case .compose: "Type or dictate, then Send"
        }
    }

    /// The stored mode, or Live when nothing (or something unknown) is
    /// stored: the panel remembers the last mode.
    public static func restored(_ raw: String?) -> TypeMode {
        raw.flatMap(TypeMode.init(rawValue:)) ?? .live
    }
}

/// What the panel's body shows.
public enum TypeTab: String, Sendable, Hashable, CaseIterable {
    /// The field and the system keyboard.
    case keys
    /// The dot-matrix number pad (the system keyboard steps down).
    case numpad

    public var title: String {
        switch self {
        case .keys: "Keys"
        case .numpad: "Numpad"
        }
    }

    /// Whether the system keyboard should be up on this tab.
    public var wantsSystemKeyboard: Bool { self == .keys }
}

// MARK: - Keys row

/// One key in the keys row: a `RemoteKey` or a function key.
public enum TypeKey: Sendable, Hashable, Identifiable {
    case remote(RemoteKey)
    /// F1–F12.
    case function(Int)

    public var id: String { wireName }

    /// The `KeyTable` name sent to the Mac.
    public var wireName: String {
        switch self {
        case let .remote(key): key.wireName
        case let .function(number): "f\(number)"
        }
    }

    /// The key cap: short text where a symbol alone doesn't say what the
    /// key is (VQ-034: Escape read as "⟲").
    public var cap: String {
        switch self {
        case let .remote(key):
            switch key {
            case .escape: "esc"
            case .tab: "tab"
            case .delete: "⌫"
            case .forwardDelete: "⌦"
            case .return: "⏎"
            case .left: "←"
            case .right: "→"
            case .up: "↑"
            case .down: "↓"
            case .home: "home"
            case .end: "end"
            case .pageUp: "pg up"
            case .pageDown: "pg dn"
            }
        case let .function(number): "F\(number)"
        }
    }

    /// What VoiceOver reads.
    public var spokenName: String {
        switch self {
        case let .remote(key):
            switch key {
            case .escape: "Escape"
            case .tab: "Tab"
            case .delete: "Delete"
            case .forwardDelete: "Forward delete"
            case .return: "Return"
            case .left: "Left arrow"
            case .right: "Right arrow"
            case .up: "Up arrow"
            case .down: "Down arrow"
            case .home: "Home"
            case .end: "End"
            case .pageUp: "Page up"
            case .pageDown: "Page down"
            }
        case let .function(number): "F\(number)"
        }
    }

    /// The chord this key sends with `modifiers` held.
    public func chord(with modifiers: [KeyModifier]) -> [String] {
        KeyModifier.pressOrder.filter(modifiers.contains).map(\.wireName) + [wireName]
    }

    /// Whether this key is Return (Return to another app asks first, VQ-036).
    public var isReturn: Bool { self == .remote(.return) }
}

/// The keys row, in the order it's drawn.
public enum TypeKeysRow {
    /// Always shown: editing keys, then the arrows, then navigation.
    public static let main: [TypeKey] = [
        .remote(.escape), .remote(.tab), .remote(.delete), .remote(.return),
        .remote(.left), .remote(.down), .remote(.up), .remote(.right),
        .remote(.home), .remote(.end), .remote(.pageUp), .remote(.pageDown),
    ]

    /// Behind the fn toggle.
    public static let functionKeys: [TypeKey] = (1...12).map(TypeKey.function)

    /// The row for the fn toggle's state.
    public static func keys(showsFunctionKeys: Bool) -> [TypeKey] {
        showsFunctionKeys ? functionKeys : main
    }
}

// MARK: - Sticky modifiers

/// The ⌘ ⌥ ⌃ ⇧ chips (`04-Interaction-Model.md` §2 Keyboard): tap once to
/// hold a modifier for the next key, tap again to lock it, tap a third time
/// to let it go. A once-modifier is used up by the next key; a locked one
/// stays lit until tapped.
public struct ModifierLatch: Sendable, Hashable {
    public enum State: Sendable, Hashable {
        case off, once, locked
    }

    /// The chips, in the order they're drawn.
    public static let chips: [KeyModifier] = [.command, .option, .control, .shift]

    private var states: [KeyModifier: State] = [:]

    public init() {}

    public func state(_ modifier: KeyModifier) -> State { states[modifier] ?? .off }

    /// Lit while latched (once or locked).
    public func isLit(_ modifier: KeyModifier) -> Bool { state(modifier) != .off }

    /// The held modifiers, in press order.
    public var held: [KeyModifier] {
        KeyModifier.pressOrder.filter(isLit)
    }

    public var isEmpty: Bool { held.isEmpty }

    /// off → once → locked → off.
    public mutating func tap(_ modifier: KeyModifier) {
        switch state(modifier) {
        case .off: states[modifier] = .once
        case .once: states[modifier] = .locked
        case .locked: states[modifier] = nil
        }
    }

    /// A key or chord went out with `held`: once-modifiers are used up.
    /// Answers the modifiers it went out with.
    @discardableResult
    public mutating func consume() -> [KeyModifier] {
        let used = held
        states = states.filter { $0.value == .locked }
        return used
    }

    /// Lets everything go (the panel closed).
    public mutating func clear() { states = [:] }

    /// What VoiceOver reads for a chip.
    public func spokenValue(_ modifier: KeyModifier) -> String {
        switch state(modifier) {
        case .off: "Off"
        case .once: "Held for the next key"
        case .locked: "Locked"
        }
    }
}

extension KeyModifier {
    /// The chip's glyph.
    public var chipGlyph: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        case .function: "fn"
        }
    }

    /// What VoiceOver reads for the chip.
    public var spokenName: String {
        switch self {
        case .command: "Command"
        case .option: "Option"
        case .control: "Control"
        case .shift: "Shift"
        case .function: "Function"
        }
    }
}

// MARK: - Numpad

/// The number pad (dot-matrix keys). Digits, the point and the operators
/// go as typed text, so they land the same on every keyboard layout; Enter
/// is the keypad's Enter and ⌫ is Delete.
public enum NumpadKey: String, Sendable, Hashable, CaseIterable, Identifiable {
    case delete, equals, divide, multiply
    case seven, eight, nine, minus
    case four, five, six, plus
    case one, two, three, enter
    case zero, point

    public var id: String { rawValue }

    /// The key cap, drawn in the dot-matrix font.
    public var cap: String {
        switch self {
        case .delete: "⌫"
        case .equals: "="
        case .divide: "÷"
        case .multiply: "×"
        case .minus: "-"
        case .plus: "+"
        case .enter: "ENTER"
        case .point: "."
        case .zero: "0"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        }
    }

    public var spokenName: String {
        switch self {
        case .delete: "Delete"
        case .equals: "Equals"
        case .divide: "Divide"
        case .multiply: "Multiply"
        case .minus: "Minus"
        case .plus: "Plus"
        case .enter: "Enter"
        case .point: "Decimal point"
        default: cap
        }
    }

    /// What the key sends.
    public enum Output: Sendable, Hashable {
        /// Typed as text at the Mac's cursor.
        case text(String)
        /// Pressed as a key (`KeyTable` name).
        case key(String)
    }

    public var output: Output {
        switch self {
        case .delete: .key(RemoteKey.delete.wireName)
        case .enter: .key("keypadenter")
        // The Mac's typed text: plain ASCII operators, which every
        // spreadsheet and calculator reads.
        case .divide: .text("/")
        case .multiply: .text("*")
        case .equals: .text("=")
        case .minus: .text("-")
        case .plus: .text("+")
        case .point: .text(".")
        default: .text(cap)
        }
    }

    /// Whether the cap is an operator (drawn in the accent ink).
    public var isOperator: Bool {
        switch self {
        case .equals, .divide, .multiply, .minus, .plus: true
        default: false
        }
    }

    /// Where the key sits on the 4 × 5 grid: column, row and spans.
    /// 0 spans two columns; Enter spans two rows.
    public struct Cell: Sendable, Hashable {
        public let column: Int
        public let row: Int
        public let columnSpan: Int
        public let rowSpan: Int
    }

    public static let columns = 4
    public static let rows = 5

    public var cell: Cell {
        switch self {
        case .delete: Cell(column: 0, row: 0, columnSpan: 1, rowSpan: 1)
        case .equals: Cell(column: 1, row: 0, columnSpan: 1, rowSpan: 1)
        case .divide: Cell(column: 2, row: 0, columnSpan: 1, rowSpan: 1)
        case .multiply: Cell(column: 3, row: 0, columnSpan: 1, rowSpan: 1)
        case .seven: Cell(column: 0, row: 1, columnSpan: 1, rowSpan: 1)
        case .eight: Cell(column: 1, row: 1, columnSpan: 1, rowSpan: 1)
        case .nine: Cell(column: 2, row: 1, columnSpan: 1, rowSpan: 1)
        case .minus: Cell(column: 3, row: 1, columnSpan: 1, rowSpan: 1)
        case .four: Cell(column: 0, row: 2, columnSpan: 1, rowSpan: 1)
        case .five: Cell(column: 1, row: 2, columnSpan: 1, rowSpan: 1)
        case .six: Cell(column: 2, row: 2, columnSpan: 1, rowSpan: 1)
        case .plus: Cell(column: 3, row: 2, columnSpan: 1, rowSpan: 1)
        case .one: Cell(column: 0, row: 3, columnSpan: 1, rowSpan: 1)
        case .two: Cell(column: 1, row: 3, columnSpan: 1, rowSpan: 1)
        case .three: Cell(column: 2, row: 3, columnSpan: 1, rowSpan: 1)
        case .enter: Cell(column: 3, row: 3, columnSpan: 1, rowSpan: 2)
        case .zero: Cell(column: 0, row: 4, columnSpan: 2, rowSpan: 1)
        case .point: Cell(column: 2, row: 4, columnSpan: 1, rowSpan: 1)
        }
    }

    /// The keys row by row (a key spanning rows is listed in its first).
    public static func row(_ index: Int) -> [NumpadKey] {
        allCases.filter { $0.cell.row == index }.sorted { $0.cell.column < $1.cell.column }
    }
}

// MARK: - Compose

/// What Compose's Send does with the draft.
public enum ComposeSend {
    /// The messages Send makes: the draft as typed text, in pieces small
    /// enough for the Mac (`TextChunker`), then a Return
    /// when asked. A draft of only whitespace sends nothing (but a bare
    /// Return still goes when asked). Line breaks inside the draft are
    /// typed as Returns by the Mac, the same as Live.
    public enum Message: Sendable, Hashable {
        case text(String)
        case key(String)
    }

    public static func messages(draft: String, withReturn: Bool) -> [Message] {
        var out: [Message] = []
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += TextChunker.chunks(draft).map(Message.text)
        }
        if withReturn { out.append(.key(RemoteKey.return.wireName)) }
        return out
    }

    /// Whether Send is offered for this draft.
    public static func canSend(draft: String, withReturn: Bool) -> Bool {
        withReturn || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Where the keyboard is

/// The keyboard situation the panel lays out for.
public enum KeyboardKind: String, Sendable, Hashable {
    /// No keyboard covers the window (none up, or it was dismissed).
    case none
    /// The on-screen keyboard is up.
    case software
    /// A hardware keyboard is attached: at most the system's slim
    /// shortcut bar covers the window.
    case hardware

    /// Below this overlap a "keyboard" is the iPad's shortcut bar (or the
    /// floating keyboard's leftovers), not a full on-screen keyboard.
    public static let softwareMinimumOverlap: Double = 120

    /// Classifies what covers the window: `overlap` is how many points of
    /// the window's bottom the keyboard's frame covers.
    public static func classify(overlap: Double, hardwareAttached: Bool) -> KeyboardKind {
        if overlap >= softwareMinimumOverlap { return .software }
        return hardwareAttached ? .hardware : .none
    }

    /// The overlap of a keyboard frame with the window, in window space:
    /// 0 when the keyboard is off-screen, floating above the bottom edge
    /// (iPad's floating keyboard) or undocked.
    public static func overlap(windowMaxY: Double, keyboardMinY: Double, keyboardMaxY: Double, keyboardHeight: Double) -> Double {
        guard keyboardHeight > 0, keyboardMinY < windowMaxY else { return 0 }
        // A floating or undocked keyboard doesn't reach the bottom edge.
        guard keyboardMaxY >= windowMaxY - 1 else { return 0 }
        return max(0, windowMaxY - keyboardMinY)
    }
}

/// How the panel is put together for one window and keyboard.
public struct TypePanelLayout: Sendable, Hashable {
    /// What the panel shows.
    public enum Body: String, Sendable, Hashable {
        /// Header (mode, target, tabs, close), field, keys row, modifiers.
        case full
        /// A hardware keyboard types: the target line, keys row and
        /// modifiers only (the field stays, one line, to take the keys).
        case keysOnly
    }

    public let body: Body
    /// The header row (mode, target, tabs, close). Off for the keys-only
    /// panel and when the room above the keyboard is short (iPhone
    /// landscape): the field row then carries the close button and the
    /// field's placeholder names the target.
    public let showsHeader: Bool
    /// "Typing into …" sits in the header (medium and wide) or on its own
    /// line under it (compact).
    public let targetInHeader: Bool
    /// The panel's width cap (centred in the window).
    public let maximumWidth: Double
    /// The modifier chips share the keys row (700 pt and wider, or a short
    /// panel) or get a row of their own.
    public let modifiersInKeysRow: Bool
    /// Lines the Compose field may grow to before it scrolls.
    public let composeLines: Int
    /// The numpad's key size (square), whole points.
    public let numpadKeySize: Double
    /// The side margin.
    public let margin: Double

    public static let numpadGap: Double = 8
    /// Numpad keys stay between these (44 pt minimum touch target).
    public static let numpadMinimumKey: Double = 44
    public static let numpadMaximumKey: Double = 64
    /// The panel never grows past this on wide windows: a column of keys,
    /// not a stretched bar.
    public static let wideMaximumWidth: Double = 760
    /// Below this much room above the keyboard the header row goes.
    public static let headerMinimumRoom: Double = 300
    /// From this width the chips fit in the keys row.
    public static let chipsInRowMinimumWidth: Double = 700

    /// `width` and `height` are the window's (the shell's planning size),
    /// `keyboard` what covers it, `keyboardOverlap` how much it covers.
    public init(width: Double, height: Double, keyboard: KeyboardKind, keyboardOverlap: Double = 0) {
        let metrics = LayoutMetrics(width: width, height: height)
        margin = metrics.margin
        body = keyboard == .hardware ? .keysOnly : .full
        maximumWidth = min(Self.wideMaximumWidth, max(0, width - 2 * metrics.margin))
        // The room above the keyboard decides how tall the panel may be:
        // iPhone landscape with the keyboard up has barely a line.
        let above = height - (keyboard == .software ? keyboardOverlap : 0)
        showsHeader = body == .full && above >= Self.headerMinimumRoom
        targetInHeader = metrics.widthClass != .compact
        modifiersInKeysRow = width >= Self.chipsInRowMinimumWidth || !showsHeader
        composeLines = above < 360 ? 1 : (above < 520 ? 2 : 4)
        // Four keys and three gaps across the panel, capped; on short
        // windows the five rows must fit too.
        let across = ((maximumWidth - 3 * Self.numpadGap) / Double(NumpadKey.columns)).rounded(.down)
        let tall = ((height * 0.45 - 4 * Self.numpadGap) / Double(NumpadKey.rows)).rounded(.down)
        numpadKeySize = min(Self.numpadMaximumKey, max(Self.numpadMinimumKey, min(across, tall)))
    }

    /// The numpad grid's size for `numpadKeySize`.
    public var numpadSize: (width: Double, height: Double) {
        let columns = Double(NumpadKey.columns)
        let rows = Double(NumpadKey.rows)
        return (
            columns * numpadKeySize + (columns - 1) * Self.numpadGap,
            rows * numpadKeySize + (rows - 1) * Self.numpadGap
        )
    }

    /// The panel's bottom padding inside its container: it sits `gap`
    /// above whichever is higher of the on-screen keyboard and the app
    /// dock, so neither covers it and the dock's keyboard button stays
    /// usable when no keyboard is up. All values share one coordinate
    /// space (the window's): `containerMaxY` is the bottom of the area the
    /// panel is laid out in, `keyboardMinY` the keyboard's top (`nil` when
    /// none covers the window), `dockMinY` the dock's top (`nil` when no
    /// dock shows).
    public static func bottomPadding(containerMaxY: Double, keyboardMinY: Double?, dockMinY: Double?, gap: Double = 8) -> Double {
        let obstacles = [keyboardMinY, dockMinY].compactMap { $0 }.filter { $0 < containerMaxY }
        guard let top = obstacles.min() else { return gap }
        return containerMaxY - top + gap
    }
}

// MARK: - One owner for "shown"

/// Whether the Type panel is open, and which tab and mode it shows. One
/// value owned by the shell; the dock's keyboard button, the pad's
/// keyboard button and the lock banner's Keyboard button all go through
/// it, so the panel and the keyboard can't disagree (OT-2).
public struct TypePanelPresence: Sendable, Hashable {
    public private(set) var isShown = false
    public var mode: TypeMode
    public var tab: TypeTab = .keys
    public var showsFunctionKeys = false
    public var modifiers = ModifierLatch()
    /// Bumped each time the field should take focus (open, back to Keys).
    public private(set) var focusRequest = 0

    public init(mode: TypeMode = .live) {
        self.mode = mode
    }

    /// The dock's or pad's keyboard button.
    public mutating func toggle() {
        isShown ? close() : open()
    }

    /// Opens on the Keys tab with the field focused (the lock banner's
    /// Keyboard button, and toggle).
    public mutating func open() {
        if !isShown {
            isShown = true
            tab = .keys
        }
        focusRequest += 1
    }

    public mutating func close() {
        isShown = false
        showsFunctionKeys = false
        modifiers.clear()
    }

    public mutating func select(_ newTab: TypeTab) {
        guard newTab != tab else { return }
        tab = newTab
        if newTab.wantsSystemKeyboard { focusRequest += 1 }
    }

    /// Whether the field should hold the keyboard now.
    public var wantsFocus: Bool { isShown && tab.wantsSystemKeyboard }
}

// MARK: - The shell's planning size

/// The rule that keeps the keyboard out of the arrangement (OT-2): the
/// shell plans its form from the window's size. The on-screen keyboard
/// covers the shell's foot (the shell ignores the keyboard's safe area)
/// and the Type panel rides on top of it, so showing or hiding the
/// keyboard never changes `CanvasPlan.form`, never rebuilds the view that
/// holds the text field, and can't make the keyboard drop and come back.
public enum ShellPlanningSize {
    /// The size `CanvasPlan` reads: the window's, whatever the keyboard.
    /// `measuredHeight` must be measured with the keyboard's safe area
    /// ignored; a host that can only measure the shortened frame passes
    /// how much the keyboard took as `keyboardShortening`, and it is given
    /// back.
    public static func size(
        measuredWidth: Double,
        measuredHeight: Double,
        keyboardShortening: Double = 0
    ) -> (width: Double, height: Double) {
        (measuredWidth, measuredHeight + max(0, keyboardShortening))
    }
}
