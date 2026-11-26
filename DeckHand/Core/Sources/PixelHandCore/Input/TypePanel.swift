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
//  Beside the field: the inverted-T arrows. Under it (or beside it on wide
//  panels): two compact rows of keys, sticky ⌘ ⌥ ⌃ ⇧ first, F1–F12 behind
//  fn (`TypeKeyBlock`, OT-7), and a 5 × 4 numpad that docks beside the
//  keys. The panel's open/closed state has one owner (`TypePanelPresence`);
//  its layout follows its own width (`TypePanelLayout`), and where it sits
//  is the person's choice (`TypePanelGeometry`, OT-6), never decided by
//  moving the shell (OT-2).
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
    case seven, eight, nine, divide, delete
    case four, five, six, multiply, enter
    case one, two, three, minus
    case zero, point, equals, plus

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

    /// Where the key sits on the 5 × 4 grid (OT-7): column, row and
    /// spans. Rows 7 8 9 ÷ ⌫ / 4 5 6 × / 1 2 3 − / 0 . = +, and Enter
    /// fills the last column under ⌫ (three rows tall), like the keypad
    /// of a full-size keyboard turned compact.
    public struct Cell: Sendable, Hashable {
        public let column: Int
        public let row: Int
        public let columnSpan: Int
        public let rowSpan: Int

        init(_ column: Int, _ row: Int, rowSpan: Int = 1) {
            self.column = column
            self.row = row
            self.columnSpan = 1
            self.rowSpan = rowSpan
        }
    }

    public static let columns = 5
    public static let rows = 4

    public var cell: Cell {
        switch self {
        case .seven: Cell(0, 0)
        case .eight: Cell(1, 0)
        case .nine: Cell(2, 0)
        case .divide: Cell(3, 0)
        case .delete: Cell(4, 0)
        case .four: Cell(0, 1)
        case .five: Cell(1, 1)
        case .six: Cell(2, 1)
        case .multiply: Cell(3, 1)
        case .enter: Cell(4, 1, rowSpan: 3)
        case .one: Cell(0, 2)
        case .two: Cell(1, 2)
        case .three: Cell(2, 2)
        case .minus: Cell(3, 2)
        case .zero: Cell(0, 3)
        case .point: Cell(1, 3)
        case .equals: Cell(2, 3)
        case .plus: Cell(3, 3)
        }
    }

    /// The keys row by row (a key spanning rows is listed in its first).
    public static func row(_ index: Int) -> [NumpadKey] {
        allCases.filter { $0.cell.row == index }.sorted { $0.cell.column < $1.cell.column }
    }
}

// MARK: - Compact key block and arrows (OT-7)

/// The keys under (or beside) the field, in two compact rows on a 7-column
/// grid of `TypePanelLayout.keyPitch` cells (OT-7; build 25 had one long
/// stretched row):
///
///     ⌘  ⌥  ⌃  ⇧  esc  tab─────
///     ⌫  ⏎  home end pg↑ pg↓ fn
///
/// The modifiers and the two keys you reach for with them; then editing
/// and navigation, with fn at the end. Tab is two cells wide, as on a real
/// keyboard. With fn on, the second row's keys before fn give way to a
/// strip of F1–F12 that scrolls.
public enum TypeKeyBlock {
    public enum Item: Sendable, Hashable {
        case modifier(KeyModifier)
        case key(TypeKey)
        /// The fn toggle (F1–F12).
        case fn

        /// The accessibility identifier, matching build 25's.
        public var identifier: String {
            switch self {
            case let .modifier(modifier): "ph.type.modifier.\(modifier.rawValue)"
            case let .key(key): "ph.type.key.\(key.wireName)"
            case .fn: "ph.type.fn"
            }
        }
    }

    public struct Cell: Sendable, Hashable {
        public let item: Item
        public let column: Int
        public let row: Int
        public let columnSpan: Int
    }

    public static let columns = 7
    public static let rows = 2

    public static let cells: [Cell] = {
        var cells: [Cell] = []
        for (index, modifier) in ModifierLatch.chips.enumerated() {
            cells.append(Cell(item: .modifier(modifier), column: index, row: 0, columnSpan: 1))
        }
        cells.append(Cell(item: .key(.remote(.escape)), column: 4, row: 0, columnSpan: 1))
        cells.append(Cell(item: .key(.remote(.tab)), column: 5, row: 0, columnSpan: 2))
        let second: [RemoteKey] = [.delete, .return, .home, .end, .pageUp, .pageDown]
        for (index, key) in second.enumerated() {
            cells.append(Cell(item: .key(.remote(key)), column: index, row: 1, columnSpan: 1))
        }
        cells.append(Cell(item: .fn, column: 6, row: 1, columnSpan: 1))
        return cells
    }()

    /// The cells in `row`, left to right.
    public static func row(_ index: Int) -> [Cell] {
        cells.filter { $0.row == index }.sorted { $0.column < $1.column }
    }

    /// The columns the F1–F12 strip takes when fn is on (the second row
    /// before fn).
    public static let functionStripColumns = 6
}

/// The inverted-T arrow cluster beside the field (OT-7): ↑ over ← ↓ →,
/// three cells wide and two tall, shaped like the arrow keys of a Mac
/// keyboard.
public enum ArrowCluster {
    public static let columns = 3
    public static let rows = 2

    /// Each arrow and its cell (column, row).
    public static let cells: [(key: TypeKey, column: Int, row: Int)] = [
        (.remote(.up), 1, 0),
        (.remote(.left), 0, 1),
        (.remote(.down), 1, 1),
        (.remote(.right), 2, 1),
    ]
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

/// How the panel is put together for its width, the window and the
/// keyboard (OT-2, OT-3; compact since build 25's OT-7).
///
/// The layout follows the **panel's** width (the person resizes it,
/// `TypePanelGeometry`), not the window's:
///
///     one block (wide panels, numpad off)
///     ┌─────────────────────────────────────────────────────────┐
///     │ ⠿ [Live│Compose] ⌨ Typing into Safari    [▦] [–] (×)    │
///     │ ┌────────────────────┐      ↑     ⌘ ⌥ ⌃ ⇧ esc tab──    │
///     │ │ field              │   ←  ↓  →  ⌫ ⏎ home end ↑ ↓ fn │
///     │ └────────────────────┘ [paste]                          │
///     └─────────────────────────────────────────────────────────┘
///
///     stacked (narrower panels, or the numpad on)
///     ┌──────────────────────────────────┐
///     │ ⠿ [Live│Compose]   [▦] [–] (×)   │
///     │ ⌨ Typing into Safari             │  (narrow: own line)
///     │ ┌──────────────┐      ↑          │
///     │ │ field        │   ←  ↓  →       │
///     │ [paste]                          │
///     │ ⌘ ⌥ ⌃ ⇧ esc tab │ 7 8 9 ÷ ⌫      │  numpad beside the keys
///     │ ⌫ ⏎ hm end ↑ ↓ fn│ 4 5 6 × ⏎ ...  │  when it fits, else below
///     └──────────────────────────────────┘
public struct TypePanelLayout: Sendable, Hashable {
    /// What the panel shows.
    public enum Body: String, Sendable, Hashable {
        /// Header (grip, mode, target, numpad, collapse, close), field,
        /// arrows and keys.
        case full
        /// A hardware keyboard types: the field is one line naming the
        /// target (it must hold focus to take the keys), with no paste or
        /// Compose actions under it.
        case keysOnly
    }

    /// How the field (with the arrows) and the key block share the panel.
    public enum Arrangement: String, Sendable, Hashable {
        /// Field, arrows and keys side by side in one block.
        case oneBlock
        /// Field and arrows on top, the key block under them.
        case stacked
    }

    /// Where the numpad goes when it's on.
    public enum NumpadPlacement: String, Sendable, Hashable {
        case hidden
        /// To the right of the key block, in the same band.
        case beside
        /// Under the key block (narrow panels).
        case below
    }

    public let body: Body
    /// The header row. Off when the room above the keyboard is short
    /// (iPhone landscape): the field row then carries the grip and the
    /// close button, and the field's placeholder names the target.
    public let showsHeader: Bool
    /// "Typing into …" sits in the header (wide panels) or on its own line
    /// under it.
    public let targetInHeader: Bool
    /// The widest the panel may be in this window.
    public let maximumWidth: Double
    /// The panel's width this layout is for.
    public let panelWidth: Double
    public let arrangement: Arrangement
    public let numpadPlacement: NumpadPlacement
    /// The field's width (the arrows sit beside it).
    public let fieldWidth: Double
    /// Lines the Compose field may grow to before it scrolls.
    public let composeLines: Int
    /// The side margin of the window.
    public let margin: Double

    // MARK: Sizes (points)

    /// One key cell: a 40 pt cap and a 4 pt gap, so every key keeps a
    /// 44 pt touch target without overlapping its neighbour's.
    public static let keyPitch: Double = 44
    public static let keyGap: Double = 4
    public static var keyCap: Double { keyPitch - keyGap }
    /// Between the field, the arrows, the keys and the numpad.
    public static let blockGap: Double = 12
    /// The panel's inner padding.
    public static let padding: Double = 12
    /// The field never gets narrower than this (about 18 characters).
    public static let fieldMinimumWidth: Double = 192
    /// Numpad keys: the same 44 pt cells as the key block.
    public static var numpadGap: Double { keyGap }

    public static var keyBlockSize: (width: Double, height: Double) {
        (Double(TypeKeyBlock.columns) * keyPitch, Double(TypeKeyBlock.rows) * keyPitch)
    }
    public static var arrowsSize: (width: Double, height: Double) {
        (Double(ArrowCluster.columns) * keyPitch, Double(ArrowCluster.rows) * keyPitch)
    }
    public static var numpadSize: (width: Double, height: Double) {
        (Double(NumpadKey.columns) * keyPitch, Double(NumpadKey.rows) * keyPitch)
    }

    /// The panel never grows past this: a block of keys, not a bar.
    public static let wideMaximumWidth: Double = 760
    /// Below this much room above the keyboard the header row goes.
    public static let headerMinimumRoom: Double = 300
    /// From this panel width "Typing into …" fits in the header.
    public static let targetInHeaderMinimumWidth: Double = 560

    /// The narrowest panel that takes the one-block arrangement:
    /// padding, the field at its minimum, the arrows and the keys.
    public static var oneBlockMinimumWidth: Double {
        2 * padding + fieldMinimumWidth + blockGap + arrowsSize.width + blockGap + keyBlockSize.width
    }

    /// The narrowest panel with the numpad beside the keys.
    public static var numpadBesideMinimumWidth: Double {
        2 * padding + keyBlockSize.width + blockGap + numpadSize.width
    }

    /// - Parameters:
    ///   - width / height: the window's (the shell's planning size).
    ///   - keyboard / keyboardOverlap: what covers the window.
    ///   - panelWidth: the panel's current width (`TypePanelGeometry`);
    ///     `nil` lays out for the widest the window allows.
    ///   - showsNumpad: whether the numpad is on.
    public init(
        width: Double,
        height: Double,
        keyboard: KeyboardKind,
        keyboardOverlap: Double = 0,
        panelWidth: Double? = nil,
        showsNumpad: Bool = false
    ) {
        let metrics = LayoutMetrics(width: width, height: height)
        margin = metrics.margin
        body = keyboard == .hardware ? .keysOnly : .full
        maximumWidth = min(Self.wideMaximumWidth, max(0, width - 2 * metrics.margin))
        let panel = max(0, min(panelWidth ?? maximumWidth, maximumWidth))
        self.panelWidth = panel
        // The room above the keyboard decides how tall the panel may be:
        // iPhone landscape with the keyboard up has barely a line.
        let above = height - (keyboard == .software ? keyboardOverlap : 0)
        showsHeader = above >= Self.headerMinimumRoom
        targetInHeader = panel >= Self.targetInHeaderMinimumWidth
        composeLines = above < 360 ? 1 : (above < 520 ? 2 : 4)

        let inner = panel - 2 * Self.padding
        if showsNumpad {
            arrangement = .stacked
            numpadPlacement = panel >= Self.numpadBesideMinimumWidth ? .beside : .below
        } else {
            arrangement = panel >= Self.oneBlockMinimumWidth ? .oneBlock : .stacked
            numpadPlacement = .hidden
        }
        let beside = Self.blockGap + Self.arrowsSize.width
        switch arrangement {
        case .oneBlock:
            fieldWidth = (inner - beside - Self.blockGap - Self.keyBlockSize.width).rounded(.down)
        case .stacked:
            fieldWidth = max(0, inner - beside).rounded(.down)
        }
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
    /// Folded to the pill (target and mode; one tap opens it, OT-6).
    public private(set) var isCollapsed = false
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
        isCollapsed = false
        focusRequest += 1
    }

    public mutating func close() {
        isShown = false
        isCollapsed = false
        showsFunctionKeys = false
        modifiers.clear()
    }

    /// Folds the panel to its pill: the keyboard steps down and held
    /// modifiers let go (the pill can't show them).
    public mutating func collapse() {
        guard isShown, !isCollapsed else { return }
        isCollapsed = true
        modifiers.clear()
    }

    /// Opens the pill back up where it was, on the tab it had.
    public mutating func expand() {
        guard isShown, isCollapsed else { return }
        isCollapsed = false
        if tab.wantsSystemKeyboard { focusRequest += 1 }
    }

    /// The header's numpad button: the numpad docks beside the keys or
    /// goes away (OT-7).
    public mutating func toggleNumpad() {
        select(tab == .numpad ? .keys : .numpad)
    }

    /// The field took focus (a tap) while the numpad was on: back to the
    /// system keyboard, so focus and the tab agree.
    public mutating func fieldFocused() {
        if tab == .numpad { tab = .keys }
    }

    public mutating func select(_ newTab: TypeTab) {
        guard newTab != tab else { return }
        tab = newTab
        if newTab.wantsSystemKeyboard { focusRequest += 1 }
    }

    /// Whether the field should hold the keyboard now.
    public var wantsFocus: Bool { isShown && !isCollapsed && tab.wantsSystemKeyboard }

    /// The pill's words: "Safari · Live" (`TypingTargetGuard`'s app name,
    /// or "Mac" when none is known).
    public func pillCaption(frontApp: String?) -> String {
        let app = frontApp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(app.isEmpty ? "Mac" : app) · \(mode.title)"
    }
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
