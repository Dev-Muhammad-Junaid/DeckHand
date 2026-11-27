//
//  LiveSyncEditsTests.swift
//  PixelHandCoreTests
//
//  Build 29 bug 9: edits from the iPad landed in the wrong place on the
//  Mac (`test30_LiveSyncEditFromIPad`). These run the iPad's reconciler
//  against a simulated Mac field that applies edits the way
//  `FocusTextSync` does after the fix (fresh read, `TextEditCheck`,
//  `TextSelectionPlacement` confirmed by a read, type, answer), over a link
//  with latency, and check the Mac's document exactly.
//

import Foundation
import Testing
@testable import PixelHandCore

// MARK: - A simulated Mac field

/// How the Mac app treats `kAXSelectedTextRangeAttribute`.
enum SimAX: String, Sendable, CaseIterable, CustomTestStringConvertible {
    /// Settable and it takes (TextEdit, Notes).
    case works
    /// Settable, answers success, doesn't move: only the read-back shows it.
    case saysYesButIgnores
    /// Not settable: arrow keys from the caret the Mac read.
    case notSettable

    var testDescription: String { rawValue }
}

struct SimMacField {
    var units: [UInt16]
    var selection: TextRange
    var ax: SimAX = .works
    /// The app reports its selection (else the Mac knows no caret).
    var selectionReadable = true
    var tracker = TextRevisionTracker()
    var previousStart: Int?
    let key: UInt64 = 0xFEED_F00D

    init(_ doc: String, caret: Int? = nil, ax: SimAX = .works) {
        units = Array(doc.utf16)
        selection = .caret(caret ?? doc.utf16.count)
        self.ax = ax
    }

    var doc: String { String(decoding: units, as: UTF16.self) }

    /// Character boundaries, in UTF-16 units.
    var boundaries: [Int] {
        var out = [0]
        var offset = 0
        for character in doc {
            offset += character.utf16.count
            out.append(offset)
        }
        return out
    }

    mutating func reading() -> TextRevisionTracker.Reading {
        let range = TextSyncPolicy.window(fieldLength: units.count, selection: selection, previousStart: previousStart)
        let aligned = TextUnits.aligned(Array(units[range.start..<range.end]), start: range.start)
        previousStart = aligned.start
        return .init(
            readable: .yes,
            window: TextWindow(start: aligned.start, value: String(decoding: aligned.units, as: UTF16.self)),
            length: units.count,
            selection: selection,
            canSetSelection: ax != .notSettable,
            canEdit: true
        )
    }

    mutating func observe() -> (state: FocusedTextState, changed: Bool) {
        tracker.observe(elementKey: key, reading: reading())
    }

    // Typing on the Mac.

    mutating func insert(_ text: String) {
        units.replaceSubrange(selection.start..<selection.end, with: Array(text.utf16))
        selection = .caret(selection.start + text.utf16.count)
    }

    mutating func press(_ chord: [String]) {
        let shift = chord.contains("shift")
        let b = boundaries
        func before(_ offset: Int) -> Int { b.last(where: { $0 < offset }) ?? 0 }
        func after(_ offset: Int) -> Int { b.first(where: { $0 > offset }) ?? units.count }
        switch chord.last {
        case "tab": insert("\t")
        case "return": insert("\n")
        case "delete":
            if selection.length == 0, selection.start > 0 {
                selection = TextRange(start: before(selection.start), length: selection.start - before(selection.start))
            }
            insert("")
        case "left":
            selection = .caret(selection.length > 0 ? selection.start : before(selection.start))
        case "right":
            if shift {
                selection = TextRange(start: selection.start, length: after(selection.end) - selection.start)
            } else {
                selection = .caret(selection.length > 0 ? selection.end : after(selection.start))
            }
        default: break
        }
    }

    /// `FocusTextSync.placeSelection`: a step, then a fresh read.
    mutating func place(_ target: TextRange) -> Bool {
        var attempts = TextSelectionPlacement.Attempts()
        while true {
            let window = reading().window
            switch TextSelectionPlacement.next(
                target: target, current: selectionReadable ? selection : nil,
                canSetSelection: ax != .notSettable, window: window, attempts: attempts
            ) {
            case .done: return true
            case .fail: return false
            case .accessibility:
                attempts.accessibility += 1
                if ax == .works, target.end <= units.count { selection = target }
            case let .arrows(chords):
                attempts.arrows += 1
                for chord in chords { press(chord) }
            }
        }
    }
}

// MARK: - The link and the two ends

final class LiveSyncHarness {
    enum ToMac: Equatable {
        case edit(TextEditRequest)
        case select(TextSelectRequest)
        case raw(TextSyncRawInput)
    }

    enum ToPad {
        case state(FocusedTextState)
        case result(TextEditResult)
    }

    var pad = TextSyncReconciler()
    /// The iPad's `UITextView`.
    var fieldText = ""
    var fieldSelection = TextRange.caret(0)
    var mac: SimMacField
    var now = 0.0
    let latency: Double
    /// The Mac's time to read, check, place and answer an edit, and per
    /// typed character.
    let macPerEdit: Double
    let macPerCharacter: Double
    private let step = 0.005
    private var toMac: [(at: Double, message: ToMac)] = []
    private var toPad: [(at: Double, message: ToPad)] = []
    private var macBusyUntil = 0.0
    /// The Mac → iPad channel is in order (one Loom stream).
    private var lastToPadAt = 0.0
    /// Everything the iPad sent, in order.
    private(set) var sent: [ToMac] = []
    private(set) var outstandingEdits = 0
    private(set) var maxOutstandingEdits = 0
    private(set) var conflicts = 0
    /// What the Mac typed text with, in order (for interleaving checks).
    private(set) var macLog: [String] = []

    init(_ doc: String, caret: Int? = nil, ax: SimAX = .works, latency: Double = 0.02, macPerEdit: Double = 0.06, macPerCharacter: Double = 0.004) {
        mac = SimMacField(doc, caret: caret, ax: ax)
        self.latency = latency
        self.macPerEdit = macPerEdit
        self.macPerCharacter = macPerCharacter
        let (state, _) = mac.observe()
        toPadInOrder(latency, .state(state))
        advance(0.1)
    }

    // The iPad person.

    /// Types `text` a character at a time at the field's caret, the way
    /// UIKit reports it: the selection delegate first, then the change.
    func padType(_ text: String, every interval: Double = 0.08) {
        for character in text {
            let s = String(character)
            let units = Array(fieldText.utf16)
            var next = units
            next.replaceSubrange(fieldSelection.start..<fieldSelection.end, with: Array(s.utf16))
            let newText = String(decoding: next, as: UTF16.self)
            let newSelection = TextRange.caret(fieldSelection.start + s.utf16.count)
            run(pad.localSelection(newSelection, fieldText: newText, now: now))
            fieldText = newText
            fieldSelection = newSelection
            run(pad.localChange(text: newText, selection: newSelection, composing: false, now: now))
            advance(interval)
        }
    }

    /// The keyboard's ⌫: the character before the caret (or the
    /// selection).
    func padBackspace() {
        var range = fieldSelection
        if range.length == 0 {
            var offset = 0
            var previous = 0
            for character in fieldText {
                if offset >= range.start { break }
                previous = offset
                offset += character.utf16.count
            }
            range = TextRange(start: previous, length: range.start - previous)
        }
        let newText = TextUnits.replacing(range, in: fieldText, with: "")!
        let newSelection = TextRange.caret(range.start)
        run(pad.localSelection(newSelection, fieldText: newText, now: now))
        fieldText = newText
        fieldSelection = newSelection
        run(pad.localChange(text: newText, selection: newSelection, composing: false, now: now))
    }

    /// A tap, a space-bar trackpad step or a handle drag.
    func padCaret(_ range: TextRange) {
        fieldSelection = range
        run(pad.localSelection(range, fieldText: fieldText, now: now))
    }

    func padRaw(_ input: TextSyncRawInput) {
        run(pad.localRaw(input, now: now))
    }

    // The Mac person.

    func macTypes(_ text: String, at offset: Int) {
        mac.selection = .caret(offset)
        mac.insert(text)
        emitState(at: now)
    }

    // Time.

    func advance(_ seconds: Double) {
        let end = now + seconds
        while now < end - 1e-9 {
            now += step
            deliver()
            run(pad.tick(now: now))
        }
    }

    func settle() { advance(4) }

    // MARK: Plumbing

    private func run(_ effects: [TextSyncReconciler.Effect]) {
        for effect in effects {
            switch effect {
            case let .sendEdit(edit):
                outstandingEdits += 1
                maxOutstandingEdits = max(maxOutstandingEdits, outstandingEdits)
                send(.edit(edit))
            case let .sendSelect(select): send(.select(select))
            case let .sendRaw(input): send(.raw(input))
            case let .show(text, selection):
                fieldText = text
                fieldSelection = selection
            case .becameBlind:
                fieldText = ""
            case .conflict:
                conflicts += 1
            }
        }
    }

    private func send(_ message: ToMac) {
        sent.append(message)
        toMac.append((now + latency, message))
    }

    private func deliver() {
        while let first = toMac.first, first.at <= now, macBusyUntil <= now {
            toMac.removeFirst()
            macHandle(first.message)
        }
        while let first = toPad.first, first.at <= now {
            toPad.removeFirst()
            switch first.message {
            case let .state(state): run(pad.receive(state, now: now))
            case let .result(result):
                outstandingEdits -= 1
                run(pad.receive(result, now: now))
            }
        }
    }

    private func emitState(at time: Double) {
        let (state, changed) = mac.observe()
        if changed { toPadInOrder(time + latency, .state(state)) }
    }

    private func toPadInOrder(_ at: Double, _ message: ToPad) {
        lastToPadAt = max(lastToPadAt, at)
        toPad.append((lastToPadAt, message))
    }

    /// `FocusTextSync`: one job at a time; states as it types; the state
    /// for the result's revision, then the result.
    private func macHandle(_ message: ToMac) {
        var t = now
        switch message {
        case let .edit(request):
            emitState(at: t)
            let state = mac.observe().state
            let span = TextEditCheck.span(for: request, fieldLength: mac.units.count)
            let decision = TextEditCheck.decide(
                request, field: state.field, readable: .yes, canEdit: true, fieldLength: mac.units.count,
                span: Array(mac.units[span.start..<span.end]), spanStart: span.start
            )
            var outcome = decision.outcome
            t += macPerEdit
            switch decision {
            case let .apply(range), let .rebase(range):
                if mac.place(range) {
                    emitState(at: t)
                    macLog.append(request.replacement)
                    if request.replacement.isEmpty {
                        if range.length > 0 { mac.press(["delete"]) }
                    } else {
                        for character in request.replacement {
                            mac.insert(String(character))
                            t += macPerCharacter
                            emitState(at: t)
                        }
                    }
                } else {
                    outcome = .refused(reason: .notEditable)
                }
            case .conflict, .refused:
                break
            }
            emitState(at: t)
            let revision = mac.observe().state.revision
            toPadInOrder(t + latency, .result(TextEditResult(field: request.field, request: request.request, outcome: outcome, revision: revision)))
        case let .select(request):
            let state = mac.observe().state
            if state.field == request.field, request.range.end <= mac.units.count {
                _ = mac.place(request.range)
            }
            t += macPerEdit / 2
            emitState(at: t)
        case let .raw(input):
            switch input {
            case let .keys(chord):
                macLog.append(chord.joined(separator: "+"))
                mac.press(chord)
            case let .text(text):
                macLog.append(text)
                mac.insert(text)
            }
            t += 0.01
            emitState(at: t)
        }
        macBusyUntil = t
    }
}

// MARK: - The walks that failed (build 29 bug 9)

@Suite struct LiveSyncEditReproTests {
    static let scratch = "Pixel Hand QA scratch\ntyped on the Mac"

    /// iPad Pro 11": the wide field's centre tap lands past the text, so
    /// the caret stays at the Mac's (the end).
    @Test("iPad walk: accept⇥ and \"pixel hand\" at the end, X at the tapped start", arguments: SimAX.allCases)
    func iPadWalk(ax: SimAX) {
        let h = LiveSyncHarness(Self.scratch, ax: ax)
        #expect(h.fieldText == Self.scratch && h.fieldSelection == .caret(Self.scratch.utf16.count))
        // test29_LiveSyncTabAccept
        h.padType("accept")
        h.advance(1)
        h.padRaw(.keys(["tab"]))
        h.advance(3)
        #expect(h.mac.doc == Self.scratch + "accept\t")
        // test30_LiveSyncEditFromIPad
        h.padType("pixel hand")
        h.advance(2)
        #expect(h.pad.badge(now: h.now) == .sync)
        h.padCaret(.caret(0)) // the tap at the field's start
        h.advance(1)
        h.padType("X")
        h.settle()
        let expected = "X" + Self.scratch + "accept\tpixel hand"
        #expect(h.mac.doc == expected)
        #expect(h.fieldText == expected)
        #expect(h.mac.selection == .caret(1) && h.fieldSelection == .caret(1))
        #expect(h.pad.badge(now: h.now) == .sync && h.conflicts == 0)
        #expect(h.maxOutstandingEdits == 1)
    }

    /// iPhone 17 Pro: the narrow field's centre tap lands mid-text (after
    /// "Pixel Hand", then after "Pixel "). Build 29 typed
    /// "Pixel pixel XhandHandaccept⇥ QA scratch…".
    @Test("iPhone walk: edits land at the field's caret and never cut into each other", arguments: SimAX.allCases)
    func iPhoneWalk(ax: SimAX) {
        let h = LiveSyncHarness(Self.scratch, ax: ax)
        // test29_LiveSyncTabAccept: the opening tap puts the caret after "Pixel Hand".
        h.padCaret(.caret(10))
        h.advance(1)
        #expect(h.mac.selection == .caret(10))
        h.padType("accept")
        h.advance(1)
        h.padRaw(.keys(["tab"]))
        h.advance(3)
        #expect(h.mac.doc == "Pixel Handaccept\t QA scratch\ntyped on the Mac")
        // test30_LiveSyncEditFromIPad: the opening tap lands after "Pixel ".
        h.padCaret(.caret(6))
        h.advance(1)
        h.padType("pixel hand")
        h.advance(2)
        h.padCaret(.caret(0))
        h.advance(1)
        h.padType("X")
        h.settle()
        let expected = "XPixel pixel handHandaccept\t QA scratch\ntyped on the Mac"
        #expect(h.mac.doc == expected)
        #expect(h.fieldText == expected)
        #expect(h.pad.badge(now: h.now) == .sync && h.conflicts == 0)
    }

    @Test("The same walks with no pauses: everything queues behind the edit in flight", arguments: SimAX.allCases)
    func walkWithoutPauses(ax: SimAX) {
        let h = LiveSyncHarness(Self.scratch, ax: ax, macPerEdit: 0.25)
        h.padCaret(.caret(10))
        h.padType("accept", every: 0.02)
        h.padRaw(.keys(["tab"]))
        h.padCaret(.caret(6))
        h.padType("pixel hand", every: 0.02)
        h.padCaret(.caret(0))
        h.padType("X", every: 0.02)
        h.settle()
        #expect(h.mac.doc == "XPixel pixel handHandaccept\t QA scratch\ntyped on the Mac")
        #expect(h.fieldText == h.mac.doc)
        #expect(h.maxOutstandingEdits == 1)
    }
}

// MARK: - Caret moves

@Suite struct LiveSyncCaretTests {
    @Test("A tap at the start of the field moves the Mac's caret there, deep in a long document", arguments: SimAX.allCases)
    func tapAtStartOfWindow(ax: SimAX) {
        let doc = String(repeating: "line of text\n", count: 230) // 2 990 units
        let h = LiveSyncHarness(doc, ax: ax)
        let start = h.pad.windowStart
        #expect(start > 0) // the field shows a window, not the whole document
        h.padCaret(.caret(0))
        h.advance(0.5)
        #expect(h.mac.selection == .caret(start))
        h.padType("X")
        h.settle()
        var expected = Array(doc.utf16)
        expected.insert(contentsOf: Array("X".utf16), at: start)
        #expect(h.mac.doc == String(decoding: expected, as: UTF16.self))
    }

    @Test("Typing at the caret sends no textSelect (UIKit reports the caret before the text)")
    func typingSendsNoSelect() {
        let h = LiveSyncHarness("Hello")
        h.padType(" world")
        h.settle()
        #expect(h.mac.doc == "Hello world")
        #expect(!h.sent.contains { if case .select = $0 { true } else { false } })
    }

    @Test("The space-bar trackpad: the Mac's caret follows; the last position wins", arguments: SimAX.allCases)
    func spaceBarTrackpad(ax: SimAX) {
        let h = LiveSyncHarness("The quick brown fox", ax: ax)
        for offset in stride(from: 19, through: 4, by: -1) {
            h.padCaret(.caret(offset))
            h.advance(0.016)
        }
        h.advance(1)
        #expect(h.mac.selection == .caret(4))
        #expect(h.fieldSelection == .caret(4))
        h.padType("very ")
        h.settle()
        #expect(h.mac.doc == "The very quick brown fox")
    }

    @Test("A caret moved while an edit is in flight goes after it")
    func caretDuringFlight() {
        let h = LiveSyncHarness("abc", macPerEdit: 0.3)
        h.padType("d", every: 0.01)
        h.padCaret(.caret(1))
        h.padCaret(.caret(0)) // the space bar dragged on
        h.advance(1.5)
        #expect(h.mac.doc == "abcd" && h.mac.selection == .caret(0))
        h.padType("Z")
        h.settle()
        #expect(h.mac.doc == "Zabcd")
    }

    @Test("A selection made with the handles is selected on the Mac, and typing replaces it", arguments: SimAX.allCases)
    func selectionReplaced(ax: SimAX) {
        let h = LiveSyncHarness("one two three", ax: ax)
        h.padCaret(TextRange(start: 4, length: 3))
        h.advance(0.5)
        #expect(h.mac.selection == TextRange(start: 4, length: 3))
        h.padType("2")
        h.settle()
        #expect(h.mac.doc == "one 2 three")
    }
}

// MARK: - One edit in flight, keys behind it

@Suite struct LiveSyncQueueTests {
    @Test("Typing while an edit is in flight: one edit at a time, nothing sent raw, every letter lands in order")
    func typingWhileInFlight() {
        let h = LiveSyncHarness("Dear Sam,", macPerEdit: 0.2)
        h.padType(" thank you for the update", every: 0.03)
        h.settle()
        #expect(h.mac.doc == "Dear Sam, thank you for the update")
        #expect(h.maxOutstandingEdits == 1)
        #expect(!h.sent.contains { if case .raw = $0 { true } else { false } })
        #expect(h.sent.count < 25) // batched, not a message a letter
    }

    @Test("Accept ⇥ pressed while text is in flight waits for it, at the field's caret")
    func acceptBehindText() {
        let h = LiveSyncHarness("x", macPerEdit: 0.3)
        h.padType("accept", every: 0.01)
        h.padRaw(.keys(["tab"]))
        #expect(h.pad.queuedRawCount == 1)
        h.settle()
        #expect(h.mac.doc == "xaccept\t")
        #expect(h.macLog.last == "tab")
    }

    @Test("Text typed right after Accept ⇥ goes after the Tab")
    func typingAfterAccept() {
        let h = LiveSyncHarness("a", macPerEdit: 0.2)
        h.padRaw(.keys(["tab"]))
        h.padType("next", every: 0.01)
        h.settle()
        #expect(h.mac.doc == "a\tnext")
        #expect(h.fieldText == "a\tnext")
    }

    @Test("Text typed, a key, more text: the key goes between them")
    func keyBetweenText() {
        let h = LiveSyncHarness("", macPerEdit: 0.3)
        h.padType("one", every: 0.01)
        h.padRaw(.keys(["return"]))
        h.padType("two", every: 0.01)
        h.settle()
        #expect(h.mac.doc == "one\ntwo")
    }

    @Test("Joystick arrows with nothing typed go straight out and the field follows")
    func joystickArrows() {
        let h = LiveSyncHarness("abcdef")
        for _ in 0..<3 {
            h.padRaw(.keys(["left"]))
            h.advance(0.03)
        }
        #expect(h.sent.filter { if case .raw = $0 { true } else { false } }.count == 3)
        h.advance(1)
        #expect(h.mac.selection == .caret(3) && h.fieldSelection == .caret(3))
        h.padType("X")
        h.settle()
        #expect(h.mac.doc == "abcXdef")
    }

    @Test("Blind: raw input goes at once, as before")
    func blindRaw() {
        var r = TextSyncReconciler()
        #expect(r.localRaw(.keys(["tab"]), now: 0) == [.sendRaw(.keys(["tab"]))])
    }
}

// MARK: - Concurrent Mac edits, MAC WINS

@Suite struct LiveSyncConcurrentTests {
    @Test("The Mac types elsewhere while the iPad's edit is in flight: both land")
    func macTypesElsewhere() {
        let h = LiveSyncHarness("middle", macPerEdit: 0.2)
        h.padType(" end", every: 0.03)
        h.macTypes("Start ", at: 0)
        h.settle()
        #expect(h.mac.doc == "Start middle end")
        #expect(h.fieldText == "Start middle end")
        #expect(h.conflicts == 0)
    }

    @Test("The Mac types at the same place: MAC WINS restores the Mac's text and caret, nothing doubles")
    func macWinsSamePlace() {
        let h = LiveSyncHarness("abc", macPerEdit: 0.3)
        h.padCaret(.caret(1))
        h.advance(0.5)
        h.padType("d", every: 0.05)  // "ad|bc" on the Mac
        h.padType("e", every: 0.01)  // waits behind "d"
        h.macTypes("X", at: 2)       // right where "e" goes: "adX|bc"
        h.advance(1)
        #expect(h.conflicts == 1)
        #expect(h.pad.badge(now: h.now) == .macWins)
        h.settle()
        #expect(h.mac.doc == "adXbc")  // nothing doubled, no "e" cut in
        #expect(h.fieldText == "adXbc" && h.fieldSelection == h.mac.selection)
        #expect(h.pad.badge(now: h.now) == .sync)
    }

    @Test("An insert whose context still matches lands beside the Mac's text")
    func macTypesAfterAtEnd() {
        let h = LiveSyncHarness("abc", macPerEdit: 0.3)
        h.padType("d", every: 0.05)
        h.padType("e", every: 0.01)
        h.macTypes("X", at: 4)
        h.settle()
        #expect(h.mac.doc == "abcdeX")
        #expect(h.fieldText == "abcdeX")
    }

    @Test("A stale edit is rebased onto text the Mac added before it")
    func staleEditRebased() {
        var r = TextSyncReconciler()
        let field = FieldToken(5)
        _ = r.receive(FocusedTextState(field: field, revision: 1, readable: .yes, window: TextWindow(start: 0, value: "hello world"),
                                       length: 11, selection: .caret(11), canSetSelection: true, canEdit: true), now: 0)
        let out = r.localChange(text: "hello world!", selection: .caret(12), composing: false, now: 1)
        guard case let .sendEdit(edit)? = out.first else { Issue.record("no edit"); return }
        // The Mac added "Oh, " meanwhile: the edit's context moved 4 units.
        let now = Array("Oh, hello world".utf16)
        let decision = TextEditCheck.decide(edit, field: field, readable: .yes, canEdit: true, fieldLength: now.count, span: now, spanStart: 0)
        #expect(decision == .rebase(.caret(15)))
    }
}

// MARK: - UTF-16: emoji and CJK

@Suite struct LiveSyncUnicodeTests {
    @Test("Emoji and CJK: taps, typing and ⌫ land on whole characters", arguments: SimAX.allCases)
    func emojiAndCJK(ax: SimAX) {
        let doc = "👍🏽 日本語 👨‍👩‍👧 ok"
        let h = LiveSyncHarness(doc, ax: ax)
        // Between 日本 and 語: 👍🏽 is 4 units, space 1, 日本 2.
        h.padCaret(.caret(7))
        h.advance(0.5)
        #expect(h.mac.selection == .caret(7))
        h.padType("の")
        h.advance(1)
        #expect(h.mac.doc == "👍🏽 日本の語 👨‍👩‍👧 ok")
        // After the family emoji (8 units): ⌫ removes it whole.
        let familyEnd = "👍🏽 日本の語 👨‍👩‍👧".utf16.count
        h.padCaret(.caret(familyEnd))
        h.advance(0.5)
        h.padBackspace()
        h.advance(1)
        #expect(h.mac.doc == "👍🏽 日本の語  ok")
        // At the very start, before the skin-toned thumb.
        h.padCaret(.caret(0))
        h.advance(0.5)
        h.padType("✅")
        h.settle()
        #expect(h.mac.doc == "✅👍🏽 日本の語  ok")
        #expect(h.fieldText == h.mac.doc)
    }
}

// MARK: - Never type at a guessed position

@Suite struct LiveSyncPlacementTests {
    @Test("No settable selection and no known caret: nothing is typed and the iPad says so")
    func cannotPlace() {
        let h = LiveSyncHarness("keep me", caret: 7, ax: .saysYesButIgnores)
        h.mac.selectionReadable = false
        h.padCaret(.caret(0))
        h.advance(0.5)
        h.padType("X")
        h.settle()
        #expect(h.mac.doc == "keep me") // not "keep meX"
        #expect(h.fieldText == "keep me")
        #expect(h.macLog.isEmpty)
    }

    @Test("Planner: Accessibility first, confirmed by a read; then arrows from the read caret; else fail")
    func planner() {
        let window = TextWindow(start: 0, value: "abcdef")
        typealias P = TextSelectionPlacement
        #expect(P.next(target: .caret(2), current: .caret(2), canSetSelection: true, window: window, attempts: .init()) == .done)
        #expect(P.next(target: .caret(2), current: .caret(6), canSetSelection: true, window: window, attempts: .init()) == .accessibility)
        // It said yes but didn't move, twice: arrows from where it is.
        #expect(P.next(target: .caret(2), current: .caret(6), canSetSelection: true, window: window, attempts: .init(accessibility: 2))
            == .arrows(Array(repeating: ["left"], count: 4)))
        #expect(P.next(target: TextRange(start: 1, length: 2), current: .caret(0), canSetSelection: false, window: window, attempts: .init())
            == .arrows([["right"], ["shift", "right"], ["shift", "right"]]))
        // Arrows drifted twice: give up.
        #expect(P.next(target: .caret(2), current: .caret(3), canSetSelection: false, window: window, attempts: .init(arrows: 2)) == .fail)
        // The caret isn't known: never guess.
        #expect(P.next(target: .caret(2), current: nil, canSetSelection: false, window: window, attempts: .init()) == .fail)
        #expect(P.next(target: .caret(2), current: nil, canSetSelection: true, window: window, attempts: .init(accessibility: 2)) == .fail)
        // Out of the window: no arrow plan.
        #expect(P.next(target: .caret(900), current: .caret(2), canSetSelection: false, window: window, attempts: .init()) == .fail)
    }

    @Test("Landed: length, caret and the typed units, before the answer goes")
    func landed() {
        func state(_ value: String, caret: Int) -> FocusedTextState {
            FocusedTextState(field: FieldToken(1), revision: 1, readable: .yes, window: TextWindow(start: 0, value: value),
                             length: value.utf16.count, selection: .caret(caret), canSetSelection: true, canEdit: true)
        }
        typealias P = TextSelectionPlacement
        #expect(P.landed(range: .caret(3), replacement: "XY", lengthBefore: 6, after: state("abcXYdef", caret: 5)))
        // Keys still in the app's queue: only "X" so far.
        #expect(!P.landed(range: .caret(3), replacement: "XY", lengthBefore: 6, after: state("abcXdef", caret: 4)))
        // Typed somewhere else.
        #expect(!P.landed(range: .caret(3), replacement: "XY", lengthBefore: 6, after: state("abcdefXY", caret: 8)))
        // A deletion over a selection.
        #expect(P.landed(range: TextRange(start: 1, length: 2), replacement: "", lengthBefore: 6, after: state("adef", caret: 1)))
        // Emoji count in UTF-16.
        #expect(P.landed(range: .caret(0), replacement: "👍🏽", lengthBefore: 2, after: state("👍🏽ok", caret: 4)))
    }
}

// MARK: - Reconciler details

@Suite struct LiveSyncReconcilerDetailTests {
    let field = FieldToken(9)

    func state(_ value: String, rev: UInt32, sel: Int? = nil) -> FocusedTextState {
        FocusedTextState(field: field, revision: rev, readable: .yes, window: TextWindow(start: 0, value: value),
                         length: value.utf16.count, selection: .caret(sel ?? value.utf16.count), canSetSelection: true, canEdit: true)
    }

    @Test("A selection callback carrying a text change is not a caret move")
    func selectionWithTextChange() {
        var r = TextSyncReconciler()
        _ = r.receive(state("Hello", rev: 1), now: 0)
        #expect(r.localSelection(.caret(6), fieldText: "Hello!", now: 1).isEmpty)
        #expect(r.selection == .caret(5))
    }

    @Test("An edit never answered and no state: given up on the tick, with a note")
    func tickTimeout() {
        var r = TextSyncReconciler()
        _ = r.receive(state("a", rev: 1), now: 0)
        _ = r.localChange(text: "ab", selection: .caret(2), composing: false, now: 1)
        #expect(r.nextDeadline(now: 1) == 1 + TextSyncReconciler.inFlightTimeout)
        #expect(r.tick(now: 2).isEmpty)
        let effects = r.tick(now: 4.1)
        #expect(effects == [.show(text: "a", selection: .caret(1))])
        #expect(r.note(now: 4.1) == .noAnswer)
        #expect(r.badge(now: 4.1) == .sync)
    }

    @Test("Refused although readable and editable: the caret couldn't be placed; a note says so")
    func caretNotPlacedNote() {
        var r = TextSyncReconciler()
        _ = r.receive(state("a", rev: 1), now: 0)
        let out = r.localChange(text: "ab", selection: .caret(2), composing: false, now: 1)
        guard case let .sendEdit(edit)? = out.first else { Issue.record("no edit"); return }
        _ = r.receive(TextEditResult(field: field, request: edit.request, outcome: .refused(reason: .notEditable), revision: 1), now: 1.1)
        #expect(r.note(now: 1.2) == .caretNotPlaced)
        #expect(r.note(now: 1.1 + TextSyncReconciler.noteDuration + 0.1) == nil)
        #expect(TextSyncNote.caretNotPlaced.line == "The Mac couldn't move its caret there, so nothing was typed")
    }

    @Test("Merge: two insertions at one point, the Mac's (keys pressed first) goes first")
    func mergeMacFirst() {
        let base = "ab"
        let mac = TextEdit(range: .caret(2), replacement: "\t")
        let local = TextEdit(range: .caret(2), replacement: "x")
        #expect(TextSyncReconciler.merge(base: base, mac, local) == nil)
        #expect(TextSyncReconciler.merge(base: base, mac, local, macFirstAtSamePoint: true) == "ab\tx")
    }

    @Test("Raw input waits while an input method composes")
    func rawWaitsForComposition() {
        var r = TextSyncReconciler()
        _ = r.receive(state("Hi ", rev: 1), now: 0)
        _ = r.localChange(text: "Hi に", selection: .caret(4), composing: true, now: 1)
        #expect(r.localRaw(.keys(["tab"]), now: 1.1).isEmpty)
        let out = r.localChange(text: "Hi 日", selection: .caret(4), composing: false, now: 1.2)
        #expect(out.count == 1)
        guard case let .sendEdit(edit)? = out.first else { Issue.record("no edit"); return }
        #expect(edit.replacement == "日")
    }
}
