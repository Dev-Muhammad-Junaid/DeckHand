//
//  TextTyping.swift
//  PixelHandCore
//
//  Typing real text on the Mac from a remote (`input.typeText`).
//
//  Remote: `TextChunker` cuts what the person typed or pasted into
//  messages no larger than `TextChunker.defaultChunkBytes`, never inside a
//  character (an emoji with skin tone or a flag stays whole).
//
//  Mac: `TypingText.normalized` cleans the text (`RemoteInputValidation`
//  calls it), and `TypingPlanner` turns it into key presses. A character
//  the Mac's current keyboard layout can type is pressed as that key (with
//  Shift or Option if it needs them), so apps that read key codes (games,
//  terminals, remote desktops) see real keys; anything else (other
//  scripts, emoji, accents the layout lacks) is posted as a Unicode string
//  with `CGEvent.keyboardSetUnicodeString`, at most
//  `TypingPlanner.maxUnicodeUnitsPerEvent` UTF-16 units per event.
//

import Foundation

public enum TypingPolicy {
    /// Largest `typeText` the Mac accepts in one message (UTF-8 bytes).
    public static let maxMessageBytes = 4_096
    /// Most text the Mac keeps queued for typing (UTF-8 bytes). A remote
    /// that sends faster than the Mac types has the excess dropped and
    /// logged, so a paste of a book can't keep the Mac typing for an hour.
    public static let maxQueuedBytes = 64 * 1024
    /// Pause between posted key events, so the frontmost app's event
    /// queue keeps up (some drop keys posted back to back).
    public static let interEventDelay: Duration = .milliseconds(2)
}

public enum TypingText {
    /// The text with line endings made `\n` and other control characters
    /// removed (`\t` and `\n` stay: they press Tab and Return). Text from a
    /// remote is typed into whatever is frontmost, so a stray escape or
    /// NUL must not become a key press.
    public static func normalized(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var lastWasCR = false
        for scalar in text.unicodeScalars {
            defer { lastWasCR = scalar == "\r" }
            switch scalar {
            case "\r":
                out.append("\n")
            case "\n":
                if !lastWasCR { out.append("\n") }
            case "\t":
                out.append(scalar)
            default:
                // C0 and C1 controls and DEL.
                if scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) { continue }
                out.append(scalar)
            }
        }
        return String(out)
    }
}

public enum TextChunker {
    /// Default piece size for `input.typeText` (UTF-8 bytes): a quarter of
    /// `TypingPolicy.maxMessageBytes`, so a piece is never refused.
    public static let defaultChunkBytes = 1_024

    /// `text` cut into pieces of at most `maxBytes` UTF-8 bytes, never
    /// inside a character. A single character longer than `maxBytes` (a
    /// pathological combining sequence) is cut between its scalars rather
    /// than dropped.
    public static func chunks(_ text: String, maxBytes: Int = defaultChunkBytes) -> [String] {
        precondition(maxBytes >= 4, "a chunk must hold any one scalar")
        var chunks: [String] = []
        var current = ""
        var currentBytes = 0
        for character in text {
            let bytes = character.utf8.count
            if bytes > maxBytes {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                    currentBytes = 0
                }
                for scalar in character.unicodeScalars {
                    let size = String(scalar).utf8.count
                    if currentBytes + size > maxBytes {
                        chunks.append(current)
                        current = ""
                        currentBytes = 0
                    }
                    current.unicodeScalars.append(scalar)
                    currentBytes += size
                }
                continue
            }
            if currentBytes + bytes > maxBytes {
                chunks.append(current)
                current = ""
                currentBytes = 0
            }
            current.append(character)
            currentBytes += bytes
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

/// One key on the Mac's current layout: its virtual key code and the
/// modifiers it needs to produce a character.
public struct LayoutKeyStroke: Equatable, Sendable, Hashable {
    public var keyCode: UInt16
    public var shift: Bool
    public var option: Bool

    public init(keyCode: UInt16, shift: Bool = false, option: Bool = false) {
        self.keyCode = keyCode
        self.shift = shift
        self.option = option
    }
}

/// What the Mac posts for one piece of typed text.
public enum TypingStep: Equatable, Sendable {
    /// A key on the current layout, pressed and released (with Shift or
    /// Option held when `stroke` says so).
    case key(LayoutKeyStroke)
    /// A named key from `KeyTable` (Return, Tab).
    case named(String)
    /// Characters the layout can't type, posted with
    /// `keyboardSetUnicodeString` in one key-down/up pair.
    case unicode(String)
}

public enum TypingPlanner {
    /// `CGEvent.keyboardSetUnicodeString` carries at most 20 UTF-16 units;
    /// longer strings are silently truncated by the system.
    public static let maxUnicodeUnitsPerEvent = 20

    /// The steps that type `text`. `stroke` looks a character up on the
    /// Mac's current keyboard layout (`nil` = not on it). With
    /// `preferKeys == false` every character goes as Unicode, which is
    /// faster for long text.
    public static func plan(
        _ text: String,
        preferKeys: Bool = true,
        stroke: (Character) -> LayoutKeyStroke?
    ) -> [TypingStep] {
        var steps: [TypingStep] = []
        var run = ""
        var runUnits = 0

        func flush() {
            if !run.isEmpty {
                steps.append(.unicode(run))
                run = ""
                runUnits = 0
            }
        }

        for character in text {
            switch character {
            case "\n", "\r\n", "\r":
                flush()
                steps.append(.named("return"))
                continue
            case "\t":
                flush()
                steps.append(.named("tab"))
                continue
            default:
                break
            }
            if preferKeys, let key = stroke(character) {
                flush()
                steps.append(.key(key))
                continue
            }
            let units = character.utf16.count
            if units > maxUnicodeUnitsPerEvent {
                // A character longer than one event (a very long emoji
                // sequence): send it alone, cut between scalars.
                flush()
                var piece = ""
                var pieceUnits = 0
                for scalar in character.unicodeScalars {
                    let scalarUnits = scalar.utf16.count
                    if pieceUnits + scalarUnits > maxUnicodeUnitsPerEvent {
                        steps.append(.unicode(piece))
                        piece = ""
                        pieceUnits = 0
                    }
                    piece.unicodeScalars.append(scalar)
                    pieceUnits += scalarUnits
                }
                if !piece.isEmpty { steps.append(.unicode(piece)) }
                continue
            }
            if runUnits + units > maxUnicodeUnitsPerEvent { flush() }
            run.append(character)
            runUnits += units
        }
        flush()
        return steps
    }
}
