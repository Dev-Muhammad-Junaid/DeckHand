//
//  KeyTable.swift
//  PixelHandCore
//
//  Key names on the wire and the macOS virtual key codes they press. A
//  remote names keys in `input.keyboardShortcut(keys:)` ("cmd", "shift",
//  "return", "left", "a"); the Mac turns them into `CGEvent` key presses
//  with this table. It lives here, not in the Mac app, so both apps agree
//  on the names and the table is tested on Linux.
//
//  Key codes are the ANSI positions from `HIToolbox/Events.h`
//  (`kVK_ANSI_A` = 0x00 and so on). Letter and punctuation codes name a
//  *position*: on a non-US layout "z" presses whatever that layout has
//  there, which is how macOS shortcuts behave too. Typed text does not
//  use this table (see `TypingPlanner`).
//

import Foundation

/// A modifier key a chord can hold.
public enum KeyModifier: String, CaseIterable, Sendable, Hashable {
    case command, shift, option, control, function

    /// The left-hand key's virtual key code, pressed as its own event so
    /// apps that only look at `flagsChanged` see the modifier.
    public var keyCode: UInt16 {
        switch self {
        case .command: 0x37
        case .shift: 0x38
        case .option: 0x3A
        case .control: 0x3B
        case .function: 0x3F
        }
    }

    /// The order modifiers are pressed in (and released in reverse).
    public static let pressOrder: [KeyModifier] = [.command, .shift, .option, .control, .function]

    /// The wire names that mean this modifier.
    public static func named(_ name: String) -> KeyModifier? {
        switch name.lowercased() {
        case "cmd", "command": .command
        case "shift": .shift
        case "option", "alt", "opt": .option
        case "ctrl", "control": .control
        case "fn", "function": .function
        default: nil
        }
    }
}

/// A chord resolved against `KeyTable`: the modifiers to hold and the one
/// key to press.
public struct KeyChord: Equatable, Sendable {
    public var modifiers: Set<KeyModifier>
    public var keyCode: UInt16

    public init(modifiers: Set<KeyModifier>, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    /// Modifiers in press order.
    public var orderedModifiers: [KeyModifier] {
        KeyModifier.pressOrder.filter(modifiers.contains)
    }
}

public enum KeyTable {
    /// Every non-modifier key name and its virtual key code.
    public static let keyCodes: [String: UInt16] = [
        // Letters (ANSI positions)
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "o": 0x1F,
        "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28,
        "n": 0x2D, "m": 0x2E,
        // Digits
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
        "9": 0x19, "7": 0x1A, "8": 0x1C, "0": 0x1D,
        // Punctuation
        "=": 0x18, "-": 0x1B, "]": 0x1E, "[": 0x21, "'": 0x27, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, ".": 0x2F, "`": 0x32,
        // Editing and whitespace
        " ": 0x31, "space": 0x31,
        "return": 0x24, "enter": 0x24,
        "keypadenter": 0x4C,
        "tab": 0x30,
        "delete": 0x33, "backspace": 0x33,
        "forwarddelete": 0x75,
        "escape": 0x35, "esc": 0x35,
        // Navigation
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
        // Function keys
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    ]

    /// The key code for one key name, any case. `nil` for unknown names and
    /// for modifiers.
    public static func keyCode(for name: String) -> UInt16? {
        keyCodes[name.lowercased()] ?? (name == " " ? 0x31 : nil)
    }

    /// Resolves a chord such as `["cmd", "shift", "p"]`. `nil` when it has
    /// no key, more than one key, or a name this table doesn't know.
    public static func chord(_ keys: [String]) -> KeyChord? {
        var modifiers: Set<KeyModifier> = []
        var keyCode: UInt16?
        for name in keys {
            if let modifier = KeyModifier.named(name) {
                modifiers.insert(modifier)
            } else if let code = Self.keyCode(for: name) {
                guard keyCode == nil else { return nil }
                keyCode = code
            } else {
                return nil
            }
        }
        guard let keyCode else { return nil }
        return KeyChord(modifiers: modifiers, keyCode: keyCode)
    }
}

/// The special keys a remote's keyboard row offers, and the chord each
/// sends. Characters are typed with `input.typeText`; these are the keys
/// that aren't characters.
public enum RemoteKey: String, CaseIterable, Sendable, Hashable, Identifiable {
    case escape, tab, delete, forwardDelete, `return`
    case left, right, up, down
    case home, end, pageUp, pageDown

    public var id: String { rawValue }

    /// The chord this key sends, optionally with modifiers held (for
    /// example ⌥← moves a word, ⌘← to the line start, ⇧→ selects).
    public func chord(with modifiers: [KeyModifier] = []) -> [String] {
        KeyModifier.pressOrder.filter(modifiers.contains).map(\.wireName) + [wireName]
    }

    /// The key's name in `KeyTable`.
    public var wireName: String {
        switch self {
        case .escape: "escape"
        case .tab: "tab"
        case .delete: "delete"
        case .forwardDelete: "forwarddelete"
        case .return: "return"
        case .left: "left"
        case .right: "right"
        case .up: "up"
        case .down: "down"
        case .home: "home"
        case .end: "end"
        case .pageUp: "pageup"
        case .pageDown: "pagedown"
        }
    }
}

extension KeyModifier {
    /// The name a remote sends for this modifier.
    public var wireName: String {
        switch self {
        case .command: "cmd"
        case .shift: "shift"
        case .option: "option"
        case .control: "ctrl"
        case .function: "fn"
        }
    }
}
