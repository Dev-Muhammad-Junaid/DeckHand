//
//  KeyboardLayoutMap.swift
//  DeckHandMac
//
//  Which key on the Mac's current keyboard layout types each character,
//  for `input.typeText`. Built with the public Text Input Sources and
//  `UCKeyTranslate` APIs: every key code 0…127 is translated with no
//  modifier, Shift, Option and Shift-Option, and the first key that
//  produces a single character wins (main keys come before the keypad).
//
//  Characters the layout can't type (another script, emoji, an accent
//  behind a dead key) aren't in the map; `TypingPlanner` posts those as
//  Unicode strings. When the current input source is an input method
//  (Japanese, Chinese, Korean, …) rather than a plain layout, key presses
//  would go through that method and compose something else, so the map
//  is empty and everything is typed as Unicode.
//

import Carbon.HIToolbox
import Foundation

@MainActor
final class KeyboardLayoutMap {
    static let shared = KeyboardLayoutMap()

    private var sourceID: String?
    private var strokes: [Character: LayoutKeyStroke] = [:]

    private init() {}

    /// The key that types `character` on the current layout, or `nil`.
    func stroke(for character: Character) -> LayoutKeyStroke? {
        strokes[character]
    }

    /// Re-reads the layout if the current input source changed. Cheap when
    /// it didn't (one ID comparison). Call once per piece of text.
    func refreshIfNeeded() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            sourceID = nil
            strokes = [:]
            return
        }
        let id = Self.stringProperty(current, kTISPropertyInputSourceID) ?? "?"
        guard id != sourceID else { return }
        sourceID = id

        // An input method composes: typing its keys wouldn't produce the
        // characters we mean. Type everything as Unicode instead.
        guard Self.stringProperty(current, kTISPropertyInputSourceType) == (kTISTypeKeyboardLayout as String) else {
            strokes = [:]
            DeckHandLog.input.info("Typing: input source \(id, privacy: .public) is an input method; typed text goes as Unicode")
            return
        }
        strokes = Self.build(from: current)
        DeckHandLog.input.info("Typing: layout \(id, privacy: .public) maps \(self.strokes.count, privacy: .public) characters to keys")
    }

    // MARK: - Building

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func build(from source: TISInputSource) -> [Character: LayoutKeyStroke] {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())

        // UCKeyTranslate wants Carbon modifier bits shifted right by 8.
        let shift = UInt32(shiftKey >> 8)
        let option = UInt32(optionKey >> 8)
        let states: [(UInt32, Bool, Bool)] = [
            (0, false, false),
            (shift, true, false),
            (option, false, true),
            (shift | option, true, true),
        ]

        // Main keys first, the keypad only for what the main keys lack (a
        // terminal in keypad mode reads keypad keys differently).
        let mainKeys = Array(UInt16(0)..<0x41) + Array(UInt16(0x5D)..<128)
        let keypadKeys = Array(UInt16(0x41)...0x5C)

        var map: [Character: LayoutKeyStroke] = [:]
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for keyCodes in [mainKeys, keypadKeys] {
                for (modifierState, needsShift, needsOption) in states {
                    for keyCode in keyCodes {
                        var deadKeyState: UInt32 = 0
                        var length = 0
                        let maxLength = 4
                        var chars = [UniChar](repeating: 0, count: maxLength)
                        // No options: a dead key (Option-E's accent) leaves
                        // `deadKeyState` set, and is skipped, because
                        // pressing it would combine with the next letter.
                        let status = UCKeyTranslate(
                            layout,
                            keyCode,
                            UInt16(kUCKeyActionDown),
                            modifierState,
                            keyboardType,
                            OptionBits(0),
                            &deadKeyState,
                            maxLength,
                            &length,
                            &chars
                        )
                        guard status == noErr, length > 0, deadKeyState == 0 else { continue }
                        let string = String(utf16CodeUnits: chars, count: length)
                        guard string.count == 1, let character = string.first else { continue }
                        // Control characters (Return, Tab, the arrows'
                        // private-use codes) are named keys, not text.
                        guard let scalar = string.unicodeScalars.first,
                              scalar.value >= 0x20, scalar.value != 0x7F,
                              !(0xF700...0xF8FF).contains(scalar.value)
                        else { continue }
                        if map[character] == nil {
                            map[character] = LayoutKeyStroke(keyCode: keyCode, shift: needsShift, option: needsOption)
                        }
                    }
                }
            }
        }
        return map
    }
}
