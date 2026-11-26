//
//  FocusedTextReadoutTests.swift
//  PixelHandCoreTests
//

import Testing
@testable import PixelHandCore

@Suite("The Mac field's text in one line (OT-13)")
struct FocusedTextReadoutTests {
    func text(_ value: String, _ start: Int, _ length: Int = 0, before: Bool = false, after: Bool = false, suggestion: String? = nil) -> FocusedText {
        FocusedText(value: value, selection: .init(start: start, length: length), truncatedBefore: before, truncatedAfter: after, suggestion: suggestion)
    }

    @Test("Splits at the caret or the selection")
    func split() {
        let caret = try! #require(FocusedTextReadout(text("Hello world", 5)))
        #expect(caret.before == "Hello" && caret.selected.isEmpty && caret.after == " world")
        let selection = try! #require(FocusedTextReadout(text("Hello world", 6, 5)))
        #expect(selection.before == "Hello " && selection.selected == "world" && selection.after.isEmpty)
        #expect(FocusedTextReadout(nil) == nil)
    }

    @Test("One line, cut around the caret, with … where text goes on")
    func cut() {
        let long = String(repeating: "a", count: 100) + "\n" + String(repeating: "b", count: 100)
        let readout = try! #require(FocusedTextReadout(text(long, 101), reach: 10))
        #expect(readout.before == "…aaaaaaaaa ")
        #expect(readout.after == "bbbbbbbbbb…")
        let window = try! #require(FocusedTextReadout(text("abc", 1, before: true, after: true)))
        #expect(window.before == "…a" && window.after == "bc…")
    }

    @Test("Out-of-range selections and UTF-16 offsets are safe")
    func safe() {
        let emoji = try! #require(FocusedTextReadout(text("👋 hi", 2)))
        #expect(emoji.before == "👋" && emoji.after == " hi")
        let past = try! #require(FocusedTextReadout(text("abc", 99, 5)))
        #expect(past.before == "abc" && past.after.isEmpty)
    }

    @Test("A suggestion is kept, trimmed; VoiceOver offers Tab")
    func suggestion() {
        let readout = try! #require(FocusedTextReadout(text("Dear ", 5, suggestion: " Sam,\n")))
        #expect(readout.suggestion == "Sam,")
        #expect(readout.spoken.contains("Accept with Tab"))
        #expect(FocusedTextReadout(text("x", 1, suggestion: "  "))?.suggestion == nil)
    }
}
