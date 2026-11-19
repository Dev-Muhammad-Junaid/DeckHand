//
//  TextTypingTests.swift
//  PixelHandCoreTests
//
//  Typed text (`input.typeText`): the key table, cleaning, chunking on the
//  remote, and the Mac's plan of key presses and Unicode strings.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct KeyTableTests {
    @Test("Named keys resolve to their macOS key codes, any case")
    func namedKeys() {
        #expect(KeyTable.keyCode(for: "return") == 0x24)
        #expect(KeyTable.keyCode(for: "Delete") == 0x33)
        #expect(KeyTable.keyCode(for: "backspace") == 0x33)
        #expect(KeyTable.keyCode(for: "left") == 0x7B)
        #expect(KeyTable.keyCode(for: "right") == 0x7C)
        #expect(KeyTable.keyCode(for: "down") == 0x7D)
        #expect(KeyTable.keyCode(for: "up") == 0x7E)
        #expect(KeyTable.keyCode(for: "a") == 0x00)
        #expect(KeyTable.keyCode(for: " ") == 0x31)
        #expect(KeyTable.keyCode(for: "cmd") == nil)
        #expect(KeyTable.keyCode(for: "nonsense") == nil)
    }

    @Test("Chords: modifiers plus exactly one key")
    func chords() {
        #expect(KeyTable.chord(["cmd", "shift", "p"]) == KeyChord(modifiers: [.command, .shift], keyCode: 0x23))
        #expect(KeyTable.chord(["CTRL", "alt", "left"]) == KeyChord(modifiers: [.control, .option], keyCode: 0x7B))
        #expect(KeyTable.chord(["cmd"]) == nil, "no key")
        #expect(KeyTable.chord(["a", "b"]) == nil, "two keys")
        #expect(KeyTable.chord(["cmd", "warp"]) == nil, "unknown name")
        #expect(KeyTable.chord(["cmd", "shift", "option", "ctrl", "fn", "x"])?.orderedModifiers
            == [.command, .shift, .option, .control, .function])
    }

    @Test("Every remote key's chord resolves, with and without modifiers")
    func remoteKeysResolve() {
        for key in RemoteKey.allCases {
            #expect(KeyTable.chord(key.chord()) != nil, "\(key)")
            #expect(KeyTable.chord(key.chord(with: [.option, .shift]))?.modifiers == [.option, .shift], "\(key)")
        }
        #expect(RemoteKey.left.chord(with: [.shift, .command]) == ["cmd", "shift", "left"])
    }

    @Test("Every remote key's chord passes validation")
    func remoteKeysAreValid() {
        for key in RemoteKey.allCases {
            #expect(RemoteInputValidation.isAcceptableChord(key.chord(with: KeyModifier.allCases)))
        }
    }
}

@Suite struct TypingTextTests {
    @Test("Line endings become \\n; Tab stays; other controls go")
    func normalizes() {
        #expect(TypingText.normalized("a\r\nb\rc\nd") == "a\nb\nc\nd")
        #expect(TypingText.normalized("a\tb") == "a\tb")
        #expect(TypingText.normalized("a\u{0}b\u{1B}c\u{7F}d\u{85}e") == "abcde")
        #expect(TypingText.normalized("\r\n\r\n") == "\n\n")
        #expect(TypingText.normalized("Héllo 世界 👋🏽") == "Héllo 世界 👋🏽")
    }
}

@Suite struct TextChunkerTests {
    @Test("Short text is one chunk; empty is none")
    func shortText() {
        #expect(TextChunker.chunks("hello") == ["hello"])
        #expect(TextChunker.chunks("").isEmpty)
    }

    @Test("Chunks stay under the byte limit and join back to the text")
    func limits() {
        let text = String(repeating: "Grüße, 世界! 👨‍👩‍👧‍👦 🇵🇰 ", count: 200)
        for limit in [4, 7, 16, 64, 1_024] {
            let chunks = TextChunker.chunks(text, maxBytes: limit)
            #expect(chunks.joined() == text, "limit \(limit)")
            for chunk in chunks where chunk.count > 1 {
                #expect(chunk.utf8.count <= limit, "limit \(limit)")
            }
        }
    }

    @Test("A character is never split when it fits")
    func keepsCharactersWhole() {
        let family = "👨‍👩‍👧‍👦" // 25 UTF-8 bytes, one character
        let chunks = TextChunker.chunks(String(repeating: family, count: 10), maxBytes: 60)
        for chunk in chunks {
            #expect(chunk.allSatisfy { $0 == Character(family) })
        }
    }

    @Test("A character larger than the limit is cut between scalars, not lost")
    func oversizeCharacter() {
        let family = "👨‍👩‍👧‍👦"
        let chunks = TextChunker.chunks("a" + family + "b", maxBytes: 8)
        #expect(chunks.joined() == "a" + family + "b")
        for chunk in chunks {
            #expect(chunk.utf8.count <= 8)
        }
    }

    @Test("The default chunk is always under the Mac's message limit")
    func defaultFits() {
        #expect(TextChunker.defaultChunkBytes <= TypingPolicy.maxMessageBytes)
        let text = String(repeating: "🇵🇰", count: 5_000)
        for chunk in TextChunker.chunks(text) {
            #expect(chunk.utf8.count <= TypingPolicy.maxMessageBytes)
            #expect(RemoteInputValidation.sanitize(.input(.typeText(text: chunk))) == .input(.typeText(text: chunk)))
        }
    }
}

@Suite struct TypingPlannerTests {
    /// A tiny US-like layout: lowercase letters, their capitals with Shift,
    /// "é" with Option.
    private func usLayout(_ c: Character) -> LayoutKeyStroke? {
        switch c {
        case "a": LayoutKeyStroke(keyCode: 0)
        case "A": LayoutKeyStroke(keyCode: 0, shift: true)
        case "b": LayoutKeyStroke(keyCode: 11)
        case " ": LayoutKeyStroke(keyCode: 49)
        case "é": LayoutKeyStroke(keyCode: 14, option: true)
        default: nil
        }
    }

    @Test("Layout characters are keys; Return and Tab are named keys")
    func keysAndNamedKeys() {
        let steps = TypingPlanner.plan("aA b\n\té", stroke: usLayout)
        #expect(steps == [
            .key(LayoutKeyStroke(keyCode: 0)),
            .key(LayoutKeyStroke(keyCode: 0, shift: true)),
            .key(LayoutKeyStroke(keyCode: 49)),
            .key(LayoutKeyStroke(keyCode: 11)),
            .named("return"),
            .named("tab"),
            .key(LayoutKeyStroke(keyCode: 14, option: true)),
        ])
    }

    @Test("Characters off the layout go as Unicode runs, between keys")
    func unicodeRuns() {
        let steps = TypingPlanner.plan("a世界b👋🏽", stroke: usLayout)
        #expect(steps == [
            .key(LayoutKeyStroke(keyCode: 0)),
            .unicode("世界"),
            .key(LayoutKeyStroke(keyCode: 11)),
            .unicode("👋🏽"),
        ])
    }

    @Test("Unicode runs never pass 20 UTF-16 units and never split a character")
    func unicodeRunLimit() {
        let text = String(repeating: "世界🇵🇰👋🏽", count: 30)
        let steps = TypingPlanner.plan(text, stroke: { _ in nil })
        var rebuilt = ""
        for step in steps {
            guard case let .unicode(run) = step else {
                Issue.record("unexpected \(step)")
                continue
            }
            #expect(run.utf16.count <= TypingPlanner.maxUnicodeUnitsPerEvent)
            rebuilt += run
        }
        #expect(rebuilt == text)
    }

    @Test("A character longer than one event is cut between scalars")
    func longCharacter() {
        // A base letter with many combining marks: one character, 31 UTF-16 units.
        let long = "e" + String(repeating: "\u{301}", count: 30)
        #expect(long.count == 1)
        #expect(long.utf16.count > TypingPlanner.maxUnicodeUnitsPerEvent)
        let steps = TypingPlanner.plan(long, stroke: { _ in nil })
        var rebuilt = ""
        for case let .unicode(run) in steps {
            #expect(run.utf16.count <= TypingPlanner.maxUnicodeUnitsPerEvent)
            rebuilt += run
        }
        #expect(rebuilt == long)
    }

    @Test("Without key preference everything but Return and Tab is Unicode")
    func unicodeOnly() {
        let steps = TypingPlanner.plan("ab\nA", preferKeys: false, stroke: usLayout)
        #expect(steps == [.unicode("ab"), .named("return"), .unicode("A")])
    }

    @Test("Named steps resolve in the key table")
    func namedStepsResolve() {
        for case let .named(name) in TypingPlanner.plan("\n\t", stroke: { _ in nil }) {
            #expect(KeyTable.keyCode(for: name) != nil)
        }
    }
}
