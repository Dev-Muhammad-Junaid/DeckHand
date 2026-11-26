//
//  LiveTextSyncTests.swift
//  PixelHandCoreTests
//
//  Live text sync, Phase 1 (protocol 17, `RD-live-sync-and-caret.md` §6):
//  range edits, the context check and rebase, the window, pacing, tokens
//  and revisions, arrow plans, the reconciler (applied, rebased, conflict,
//  echo suppression, composition hold, selection), lock and validation
//  rules, and logs that never carry text.
//

import Foundation
@testable import PixelHandCore
import Testing

// MARK: - TextEdit.between

@Suite struct TextEditBetweenTests {
    func check(_ old: String, _ new: String, start: Int, length: Int, replacement: String) {
        let edit = TextEdit.between(old, new)
        #expect(edit.range == TextRange(start: start, length: length), "\(old) → \(new)")
        #expect(edit.replacement == replacement)
        #expect(edit.applied(to: old) == new)
    }

    @Test("Typing at the end is an insertion at the end")
    func append() { check("hello", "hello world", start: 5, length: 0, replacement: " world") }

    @Test("Deleting at the end removes only the tail")
    func deleteTail() { check("hello", "hel", start: 3, length: 2, replacement: "") }

    @Test("Autocorrect mid-text is one small range, not a retype")
    func autocorrectMidText() {
        check("I said teh cat sat", "I said the cat sat", start: 8, length: 2, replacement: "he")
    }

    @Test("Inserting in the middle keeps prefix and suffix")
    func insertMiddle() { check("ac", "abc", start: 1, length: 0, replacement: "b") }

    @Test("Equal texts give an empty edit")
    func equal() {
        #expect(TextEdit.between("same", "same").isEmpty)
        #expect(TextEdit.between("", "").isEmpty)
    }

    @Test("Emoji are counted in UTF-16 units and never split")
    func emoji() {
        // 👋🏽 is 4 UTF-16 units; changing its skin tone replaces it whole.
        check("hi 👋🏽!", "hi 👋🏿!", start: 3, length: 4, replacement: "👋🏿")
        check("a👍b", "a👍👍b", start: 3, length: 0, replacement: "👍")
    }

    @Test("Flags and combining marks stay whole")
    func clusters() {
        check("🇫🇷x", "🇩🇪x", start: 0, length: 4, replacement: "🇩🇪")
        // e + combining acute vs e + combining grave.
        check("cafe\u{301}", "cafe\u{300}", start: 3, length: 2, replacement: "e\u{300}")
    }

    @Test("Precomposed and decomposed characters differ (exact units)")
    func canonicalEquivalence() {
        let edit = TextEdit.between("caf\u{E9}", "cafe\u{301}")
        #expect(edit.range == TextRange(start: 3, length: 1))
        #expect(edit.replacement == "e\u{301}")
    }

    @Test("CJK and RTL text")
    func cjkAndRTL() {
        check("世界你好", "世界大家好", start: 2, length: 1, replacement: "大家")
        // The shared final ם stays.
        check("שלום עולם", "שלום לכם", start: 5, length: 3, replacement: "לכ")
    }

    @Test("Repeated letters: the edit is still minimal and correct")
    func repeated() {
        let edit = TextEdit.between("aaa", "aaaa")
        #expect(edit.range.length == 0 && edit.replacement == "a")
        #expect(edit.applied(to: "aaa") == "aaaa")
    }

    @Test("The caret after an edit sits after its replacement")
    func caretAfter() {
        #expect(TextEdit(range: TextRange(start: 3, length: 2), replacement: "xyz").caretAfter == 6)
    }
}

// MARK: - UTF-16 helpers

@Suite struct TextUnitsTests {
    @Test("Character boundaries")
    func boundaries() {
        let text = "a👋🏽b"
        #expect(TextUnits.isCharacterBoundary(0, in: text))
        #expect(TextUnits.isCharacterBoundary(1, in: text))
        #expect(!TextUnits.isCharacterBoundary(2, in: text))
        #expect(!TextUnits.isCharacterBoundary(3, in: text))
        #expect(TextUnits.isCharacterBoundary(5, in: text))
        #expect(TextUnits.isCharacterBoundary(6, in: text))
        #expect(!TextUnits.isCharacterBoundary(7, in: text))
    }

    @Test("Character counts for arrow presses")
    func characterCount() {
        let text = "a👋🏽b"
        #expect(TextUnits.characterCount(TextRange(start: 0, length: 6), in: text) == 3)
        #expect(TextUnits.characterCount(TextRange(start: 1, length: 4), in: text) == 1)
        #expect(TextUnits.characterCount(TextRange(start: 2, length: 1), in: text) == nil)
        #expect(TextUnits.characterCount(TextRange(start: 0, length: 9), in: text) == nil)
    }

    @Test("A window cut through a surrogate pair is trimmed")
    func aligned() {
        let units = Array("👍ab👍".utf16)
        let cut = Array(units[1..<5]) // low half, a, b, high half
        let out = TextUnits.aligned(cut, start: 101)
        #expect(out.start == 102)
        #expect(String(decoding: out.units, as: UTF16.self) == "ab")
        #expect(TextUnits.aligned(units, start: 0).units == units)
    }

    @Test("Replace and substring stay in bounds")
    func replace() {
        #expect(TextUnits.replacing(TextRange(start: 1, length: 1), in: "abc", with: "XY") == "aXYc")
        #expect(TextUnits.replacing(TextRange(start: 2, length: 5), in: "abc", with: "") == nil)
        #expect(TextUnits.substring("abc", TextRange(start: 1, length: 2)) == "bc")
    }

    @Test("FNV-1a is the published function")
    func fnv() {
        #expect(TextHash.fnv1a([UInt16]()) == 2_166_136_261)
        #expect(TextHash.fnv1a(Array("a".utf16)) != TextHash.fnv1a(Array("b".utf16)))
    }
}

// MARK: - The Mac's edit check

@Suite struct TextEditCheckTests {
    let field = FieldToken(77)

    func request(base text: String, windowStart: Int = 0, edit: TextEdit) -> TextEditRequest {
        TextEditRequest(
            field: field,
            request: 1,
            baseRevision: 5,
            range: edit.range.shifted(by: windowStart),
            replacement: edit.replacement,
            context: TextEditContext.make(units: Array(text.utf16), range: edit.range)!
        )
    }

    func decide(_ request: TextEditRequest, macText: String, readable: TextReadability = .yes, canEdit: Bool = true, token: FieldToken? = nil) -> TextEditCheck.Decision {
        let units = Array(macText.utf16)
        let span = TextEditCheck.span(for: request, fieldLength: units.count)
        return TextEditCheck.decide(
            request,
            field: token ?? field,
            readable: readable,
            canEdit: canEdit,
            fieldLength: units.count,
            span: Array(units[span.start..<span.end]),
            spanStart: span.start
        )
    }

    @Test("Unchanged text: applied where the remote said")
    func applied() {
        let base = "The quick teh fox"
        let req = request(base: base, edit: TextEdit.between(base, "The quick the fox"))
        #expect(decide(req, macText: base) == .apply(TextRange(start: 11, length: 2)))
    }

    @Test("Someone typed before the range on the Mac: rebased by the difference")
    func rebased() {
        let base = "The quick teh fox"
        let req = request(base: base, edit: TextEdit.between(base, "The quick the fox"))
        let mac = "Oh! The quick teh fox"
        #expect(decide(req, macText: mac) == .rebase(TextRange(start: 15, length: 2)))
    }

    @Test("The text the edit was based on is gone: conflict")
    func conflict() {
        let base = "The quick teh fox"
        let req = request(base: base, edit: TextEdit.between(base, "The quick the fox"))
        #expect(decide(req, macText: "Something else entirely here") == .conflict)
    }

    @Test("Text past the rebase radius is a conflict, not a guess")
    func farAway() {
        let base = "abc teh xyz"
        let req = request(base: base, edit: TextEdit.between(base, "abc the xyz"))
        let mac = String(repeating: "-", count: 200) + base
        #expect(decide(req, macText: mac) == .conflict)
    }

    @Test("An edit at the end of a window, deep in the field")
    func absoluteOffsets() {
        let prefix = String(repeating: "x", count: 3000)
        let window = "hello"
        let req = request(base: window, windowStart: 3000, edit: TextEdit.between(window, "hello!"))
        #expect(decide(req, macText: prefix + window) == .apply(TextRange(start: 3005, length: 0)))
    }

    @Test("Refusals: secure, locked, another field, not editable, out of bounds")
    func refusals() {
        let base = "abc"
        let req = request(base: base, edit: TextEdit.between(base, "abcd"))
        #expect(decide(req, macText: base, readable: .secure) == .refused(.secure))
        #expect(decide(req, macText: base, readable: .locked) == .refused(.locked))
        #expect(decide(req, macText: base, readable: .webOff(app: "Claude")) == .refused(.notEditable))
        #expect(decide(req, macText: base, token: FieldToken(1)) == .refused(.fieldChanged))
        #expect(decide(req, macText: base, canEdit: false) == .refused(.notEditable))
        var outside = req
        outside.range = TextRange(start: 10, length: 1)
        #expect(decide(outside, macText: base) == .refused(.invalid))
    }

    @Test("Decisions map to outcomes")
    func outcomes() {
        #expect(TextEditCheck.Decision.apply(.caret(0)).outcome == .applied)
        #expect(TextEditCheck.Decision.rebase(.caret(0)).outcome == .rebased)
        #expect(TextEditCheck.Decision.conflict.outcome == .conflict)
        #expect(TextEditCheck.Decision.refused(.secure).outcome == .refused(reason: .secure))
    }
}

// MARK: - Readability, window, pacing, revisions, arrows

@Suite struct TextSyncPolicyTests {
    func readability(
        lock: MacLockState = .unlocked, secureInput: Bool = false, hasFocus: Bool = true,
        role: String? = "AXTextArea", subrole: String? = nil, web: Bool = false,
        bundleID: String? = "com.apple.TextEdit", count: Int? = 10, line: Bool = true
    ) -> TextReadability {
        TextSyncPolicy.readability(
            lock: lock, secureInput: secureInput, hasFocus: hasFocus, axRole: role, axSubrole: subrole,
            inWebContent: web, appName: "App", bundleID: bundleID, characterCount: count, hasInsertionPointLine: line
        )
    }

    @Test("Native fields are readable")
    func native() {
        #expect(readability() == .yes)
        #expect(readability(role: "AXTextField") == .yes)
        #expect(readability(role: "AXComboBox") == .yes)
    }

    @Test("Never read: locked, secure input, password fields")
    func neverRead() {
        #expect(readability(lock: .screenLocked) == .locked)
        #expect(readability(lock: .offConsole, secureInput: true) == .locked)
        #expect(readability(secureInput: true) == .secure)
        #expect(readability(role: "AXSecureTextField") == .secure)
        #expect(readability(role: "AXTextField", subrole: "AXSecureTextField") == .secure)
    }

    @Test("Web content is off (Phase 2); Chromium is unsupported")
    func web() {
        #expect(readability(web: true, bundleID: "com.anthropic.claudefordesktop") == .webOff(app: "App"))
        #expect(readability(role: "AXWebArea", bundleID: "com.apple.Safari") == .webOff(app: "App"))
        #expect(readability(web: true, bundleID: "com.google.Chrome") == .unsupported(app: "App"))
    }

    @Test("Terminals are keys only, by bundle and by shape")
    func terminals() {
        #expect(readability(bundleID: "com.apple.Terminal") == .terminal)
        #expect(readability(bundleID: "com.googlecode.iterm2") == .terminal)
        #expect(readability(bundleID: "x.unknown", count: 250_000, line: false) == .terminal)
        #expect(readability(bundleID: "com.apple.dt.Xcode", count: 250_000, line: true) == .yes)
    }

    @Test("No field")
    func noField() {
        #expect(readability(hasFocus: false) == .noField)
        #expect(readability(role: "AXButton") == .noField)
    }

    @Test("Reason lines are plain words")
    func reasons() {
        #expect(TextReadability.secure.reasonLine == "Password field: the text stays on the Mac")
        #expect(TextReadability.webOff(app: "Claude").reasonLine == "Web text is off for Claude")
        #expect(TextReadability.unsupported(app: "Chrome").reasonLine == "Chrome doesn't share its text")
        #expect(TextReadability.terminal.reasonLine == "Terminal: keys only")
        #expect(TextReadability.noField.reasonLine == "No text field")
        #expect(TextReadability.locked.reasonLine == "Mac is locked")
        #expect(TextReadability.yes.reasonLine == nil)
    }

    @Test("A short field is sent whole")
    func shortField() {
        #expect(TextSyncPolicy.window(fieldLength: 400, selection: .caret(200), previousStart: nil) == TextRange(start: 0, length: 400))
    }

    @Test("A long field gets 1 000 units, a third before the caret")
    func longField() {
        let w = TextSyncPolicy.window(fieldLength: 10_000, selection: .caret(5_000), previousStart: nil)
        #expect(w == TextRange(start: 5_000 - 333, length: 1_000))
        let end = TextSyncPolicy.window(fieldLength: 10_000, selection: .caret(10_000), previousStart: nil)
        #expect(end == TextRange(start: 9_000, length: 1_000))
    }

    @Test("The window holds still until the caret nears an edge, then slides")
    func slider() {
        let start = 4_667
        // Caret moves within the window, far from its edges: kept.
        #expect(TextSyncPolicy.window(fieldLength: 10_000, selection: .caret(5_400), previousStart: start).start == start)
        // Within 150 of the end: recentred on the caret.
        let slid = TextSyncPolicy.window(fieldLength: 10_000, selection: .caret(5_560), previousStart: start)
        #expect(slid.start == 5_560 - 333)
        // Within 150 of the start: recentred too.
        #expect(TextSyncPolicy.window(fieldLength: 10_000, selection: .caret(4_700), previousStart: start).start == 4_700 - 333)
        // At the field's own edges the window doesn't need room.
        #expect(TextSyncPolicy.window(fieldLength: 10_000, selection: .caret(10), previousStart: 0).start == 0)
        #expect(TextSyncPolicy.window(fieldLength: 10_000, selection: .caret(9_990), previousStart: 9_000).start == 9_000)
        // A field that shrank under the old window: clamped.
        #expect(TextSyncPolicy.window(fieldLength: 2_000, selection: .caret(1_500), previousStart: 1_800).end <= 2_000)
    }

    @Test("Pacer: leading edge, 30 a second, one trailing")
    func pacer() {
        var pacer = TextSyncPacer()
        let v1 = pacer.note(now: 0)
        #expect(v1 == .sendNow)
        let v2 = pacer.note(now: 0.01)
        #expect(v2 == .sendAt(TextSyncPolicy.notificationInterval))
        let v3 = pacer.note(now: 0.02)
        #expect(v3 == .wait)
        let v4 = pacer.note(now: 0.03)
        #expect(v4 == .wait)
        let v5 = pacer.fire(now: 0.0334)
        #expect(v5)
        let v6 = pacer.fire(now: 0.04)
        #expect(!v6)
        // Quiet for a while: the next one goes at once.
        let v7 = pacer.note(now: 1)
        #expect(v7 == .sendNow)
        pacer.reset()
        let v8 = pacer.note(now: 1.001)
        #expect(v8 == .sendNow)
    }

    @Test("Pacer: a burst of keystrokes sends about 30 a second")
    func pacerBurst() {
        var pacer = TextSyncPacer()
        var sends = 0
        var scheduled: Double?
        var t = 0.0
        while t < 1.0 {
            if let at = scheduled, t >= at {
                if pacer.fire(now: t) { sends += 1 }
                scheduled = nil
            }
            switch pacer.note(now: t) {
            case .sendNow: sends += 1
            case let .sendAt(at): scheduled = at
            case .wait: break
            }
            t += 0.005 // a notification every 5 ms
        }
        #expect(sends >= 25 && sends <= 31)
    }

    func reading(_ value: String, sel: Int) -> TextRevisionTracker.Reading {
        .init(readable: .yes, window: TextWindow(start: 0, value: value), length: value.utf16.count, selection: .caret(sel), canSetSelection: true, canEdit: true)
    }

    @Test("Revisions go up on every change; a new field gets a new token")
    func revisions() {
        var tracker = TextRevisionTracker()
        let a = tracker.observe(elementKey: 1, reading: reading("a", sel: 1))
        #expect(a.changed && a.state.revision == 1 && a.state.field != .none)
        let same = tracker.observe(elementKey: 1, reading: reading("a", sel: 1))
        #expect(!same.changed && same.state.revision == 1)
        let typed = tracker.observe(elementKey: 1, reading: reading("ab", sel: 2))
        #expect(typed.changed && typed.state.revision == 2)
        let moved = tracker.observe(elementKey: 1, reading: reading("ab", sel: 0))
        #expect(moved.changed && moved.state.revision == 3 && moved.state.field == a.state.field)
        let other = tracker.observe(elementKey: 2, reading: reading("x", sel: 0))
        #expect(other.state.field != a.state.field && other.state.revision == 1)
        // Back to the first element: a new focus epoch, a new token.
        let back = tracker.observe(elementKey: 1, reading: reading("ab", sel: 0))
        #expect(back.state.field != a.state.field && back.state.field != other.state.field)
        let none = tracker.observe(elementKey: nil, reading: .init(readable: .noField, window: nil, length: 0, selection: .caret(0), canSetSelection: false, canEdit: false))
        #expect(none.state.field == .none)
    }

    @Test("Arrow plan: from a caret to a selection, through emoji")
    func arrows() {
        let window = "ab👋🏽cd"
        // Caret at 1 → select "👋🏽c" (2..<7): → once, then ⇧→ twice.
        let chords = TextSyncPolicy.arrowChords(window: window, windowStart: 100, from: .caret(101), to: TextRange(start: 102, length: 5))
        #expect(chords == [["right"], ["shift", "right"], ["shift", "right"]])
        // A selection collapses with ← first, then moves left.
        let back = TextSyncPolicy.arrowChords(window: window, windowStart: 100, from: TextRange(start: 106, length: 2), to: .caret(100))
        // ← collapses to "c", then three characters left (b, a and the emoji count as one each).
        #expect(back == [["left"], ["left"], ["left"], ["left"]])
        // Outside the window or inside a character: no plan.
        #expect(TextSyncPolicy.arrowChords(window: window, windowStart: 100, from: .caret(101), to: .caret(50)) == nil)
        #expect(TextSyncPolicy.arrowChords(window: window, windowStart: 100, from: .caret(101), to: .caret(103)) == nil)
    }

    @Test("caretMove chords: modifiers per unit, count clamped")
    func caretMove() {
        #expect(CaretMove(direction: .left, unit: .word, count: 2, extend: true).chord == ["shift", "option", "left"])
        #expect(CaretMove(direction: .down, unit: .line, count: 1, extend: false).chord == ["down"])
        #expect(CaretMove(direction: .up, unit: .paragraph, count: 1, extend: false).chord == ["option", "up"])
        #expect(TextSyncPolicy.chords(for: CaretMove(direction: .right, unit: .character, count: 200, extend: false)).count == 60)
        #expect(TextSyncPolicy.chords(for: CaretMove(direction: .right, unit: .character, count: 0, extend: false)).count == 1)
        for chord in [["shift", "option", "left"], ["down"]] {
            #expect(KeyTable.chord(chord) != nil)
        }
        #expect(!TextSyncPolicy.allowsCaretMove(secureInput: true, lock: .unlocked))
        #expect(!TextSyncPolicy.allowsCaretMove(secureInput: false, lock: .screenLocked))
        #expect(TextSyncPolicy.allowsCaretMove(secureInput: false, lock: .unlocked))
    }
}

// MARK: - The iPad's reconciler

@Suite struct TextSyncReconcilerTests {
    let field = FieldToken(9)

    func state(_ value: String, rev: UInt32, sel: Int? = nil, start: Int = 0, field: FieldToken? = nil, length: Int? = nil) -> FocusedTextState {
        FocusedTextState(
            field: field ?? self.field,
            revision: rev,
            readable: .yes,
            window: TextWindow(start: start, value: value),
            length: length ?? (start + value.utf16.count),
            selection: .caret(start + (sel ?? value.utf16.count)),
            canSetSelection: true,
            canEdit: true
        )
    }

    func synced(_ value: String, rev: UInt32 = 1) -> TextSyncReconciler {
        var r = TextSyncReconciler()
        _ = r.receive(state(value, rev: rev), now: 0)
        return r
    }

    func sentEdit(_ effects: [TextSyncReconciler.Effect]) -> TextEditRequest? {
        for case let .sendEdit(edit) in effects { return edit }
        return nil
    }

    func sentSelect(_ effects: [TextSyncReconciler.Effect]) -> TextSelectRequest? {
        for case let .sendSelect(select) in effects { return select }
        return nil
    }

    @Test("The Mac's text shows with the caret at its selection")
    func showsMacText() {
        var r = TextSyncReconciler()
        #expect(r.badge(now: 0) == .blind)
        let effects = r.receive(state("Hello world", rev: 1, sel: 5), now: 0)
        #expect(effects == [.show(text: "Hello world", selection: .caret(5))])
        #expect(r.isSynced && r.badge(now: 0) == .sync)
    }

    @Test("A Tab-accepted suggestion appears from the Mac's next value change")
    func tabAccept() {
        var r = synced("Dear Sam, thank")
        let effects = r.receive(state("Dear Sam, thank you for the update", rev: 2), now: 1)
        #expect(effects == [.show(text: "Dear Sam, thank you for the update", selection: .caret(34))])
    }

    @Test("A local edit goes out anchored, with local echo; applied → SYNC")
    func applied() {
        var r = synced("Hello")
        let out = r.localChange(text: "Hello!", selection: .caret(6), composing: false, now: 1)
        let edit = try! #require(sentEdit(out))
        #expect(edit.range == .caret(5) && edit.replacement == "!" && edit.baseRevision == 1 && edit.field == field)
        #expect(r.text == "Hello!" && r.badge(now: 1) == .sending)
        // The Mac types "!": its state comes first, then the answer.
        let v9 = r.receive(state("Hello!", rev: 2), now: 1.05)
        #expect(v9.isEmpty)
        let v10 = r.receive(TextEditResult(field: field, request: edit.request, outcome: .applied, revision: 2), now: 1.06)
        #expect(v10.isEmpty)
        #expect(r.badge(now: 1.06) == .sync && r.text == "Hello!")
    }

    @Test("Echo suppression: the Mac's intermediate states never move the field")
    func echoSuppression() {
        var r = synced("ab")
        let edit = try! #require(sentEdit(r.localChange(text: "abcdef", selection: .caret(6), composing: false, now: 1)))
        // The Mac types key by key; none of this shows.
        let v11 = r.receive(state("abc", rev: 2), now: 1.01)
        #expect(v11.isEmpty)
        let v12 = r.receive(state("abcde", rev: 3), now: 1.02)
        #expect(v12.isEmpty)
        let v13 = r.receive(state("abcdef", rev: 4), now: 1.03)
        #expect(v13.isEmpty)
        let v14 = r.receive(TextEditResult(field: field, request: edit.request, outcome: .applied, revision: 4), now: 1.04)
        #expect(v14.isEmpty)
        #expect(r.text == "abcdef" && r.selection == .caret(6))
    }

    @Test("Only one edit in flight; changes meanwhile go as one edit after it")
    func oneInFlight() {
        var r = synced("a")
        let first = try! #require(sentEdit(r.localChange(text: "ab", selection: .caret(2), composing: false, now: 1)))
        let v15 = r.localChange(text: "abc", selection: .caret(3), composing: false, now: 1.01)
        #expect(sentEdit(v15) == nil)
        let v16 = r.localChange(text: "abcd", selection: .caret(4), composing: false, now: 1.02)
        #expect(sentEdit(v16) == nil)
        _ = r.receive(state("ab", rev: 2), now: 1.03)
        let after = r.receive(TextEditResult(field: field, request: first.request, outcome: .applied, revision: 2), now: 1.04)
        let second = try! #require(sentEdit(after))
        #expect(second.range == .caret(2) && second.replacement == "cd" && second.baseRevision == 2)
        #expect(second.request != first.request)
    }

    @Test("The answer before its state: settled when the state arrives")
    func answerBeforeState() {
        var r = synced("a")
        let edit = try! #require(sentEdit(r.localChange(text: "ab", selection: .caret(2), composing: false, now: 1)))
        let v17 = r.receive(TextEditResult(field: field, request: edit.request, outcome: .applied, revision: 2), now: 1.01)
        #expect(v17.isEmpty)
        #expect(r.badge(now: 1.01) == .sending)
        _ = r.receive(state("ab", rev: 2), now: 1.02)
        #expect(r.badge(now: 1.02) == .sync)
    }

    @Test("Rebased counts as applied")
    func rebased() {
        var r = synced("abc")
        let edit = try! #require(sentEdit(r.localChange(text: "abcd", selection: .caret(4), composing: false, now: 1)))
        _ = r.receive(state("abcd", rev: 2), now: 1.01)
        _ = r.receive(TextEditResult(field: field, request: edit.request, outcome: .rebased, revision: 2), now: 1.02)
        #expect(r.badge(now: 1.02) == .sync)
    }

    @Test("The Mac autocorrects what we typed: the iPad shows the Mac's word")
    func macAutocorrect() {
        var r = synced("I ")
        let edit = try! #require(sentEdit(r.localChange(text: "I teh ", selection: .caret(6), composing: false, now: 1)))
        _ = r.receive(state("I the ", rev: 3), now: 1.05)
        let effects = r.receive(TextEditResult(field: field, request: edit.request, outcome: .applied, revision: 3), now: 1.06)
        #expect(effects == [.show(text: "I the ", selection: .caret(6))])
        #expect(sentEdit(effects) == nil) // never typed back
    }

    @Test("Conflict: the Mac's text shows and the badge says MAC WINS for 1.4 s")
    func conflict() {
        var r = synced("Hello")
        let edit = try! #require(sentEdit(r.localChange(text: "Hello there", selection: .caret(11), composing: false, now: 10)))
        _ = r.localChange(text: "Hello there!", selection: .caret(12), composing: false, now: 10.01) // queued, dropped
        _ = r.receive(state("Goodbye", rev: 7), now: 10.05)
        let effects = r.receive(TextEditResult(field: field, request: edit.request, outcome: .conflict, revision: 7), now: 10.06)
        #expect(effects == [.show(text: "Goodbye", selection: .caret(7)), .conflict])
        #expect(r.text == "Goodbye")
        #expect(r.badge(now: 10.06) == .macWins)
        #expect(r.badge(now: 11.0) == .macWins)
        #expect(r.badgeDeadline(now: 11.0) == 10.06 + 1.4)
        #expect(r.badge(now: 11.5) == .sync)
    }

    @Test("Queued changes merge with Mac changes that don't touch them")
    func merge() {
        var r = synced("one two")
        let edit = try! #require(sentEdit(r.localChange(text: "one two three", selection: .caret(13), composing: false, now: 1)))
        _ = r.localChange(text: "one two three four", selection: .caret(18), composing: false, now: 1.01)
        // Meanwhile on the Mac someone capitalised the first word.
        _ = r.receive(state("One two three", rev: 4), now: 1.02)
        let effects = r.receive(TextEditResult(field: field, request: edit.request, outcome: .applied, revision: 4), now: 1.03)
        #expect(effects.first == .show(text: "One two three four", selection: .caret(18)))
        let next = try! #require(sentEdit(effects))
        #expect(next.range == .caret(13) && next.replacement == " four" && next.baseRevision == 4)
    }

    @Test("Queued changes that collide with the Mac's: the Mac wins")
    func mergeCollision() {
        var r = synced("abc")
        let edit = try! #require(sentEdit(r.localChange(text: "abcd", selection: .caret(4), composing: false, now: 1)))
        _ = r.localChange(text: "abcde", selection: .caret(5), composing: false, now: 1.01)
        _ = r.receive(state("abcdX", rev: 4), now: 1.02)
        let effects = r.receive(TextEditResult(field: field, request: edit.request, outcome: .applied, revision: 4), now: 1.03)
        #expect(effects == [.show(text: "abcdX", selection: .caret(5)), .conflict])
        #expect(r.badge(now: 1.03) == .macWins)
    }

    @Test("Composition hold: nothing goes out and Mac updates wait until commit")
    func compositionHold() {
        var r = synced("Hi ")
        let v18 = r.localChange(text: "Hi に", selection: .caret(4), composing: true, now: 1)
        #expect(v18.isEmpty)
        let v19 = r.localChange(text: "Hi にほ", selection: .caret(5), composing: true, now: 1.1)
        #expect(v19.isEmpty)
        // The Mac's suggestion lands while composing: held.
        let v20 = r.receive(state("Hi there", rev: 2), now: 1.2)
        #expect(v20.isEmpty)
        #expect(r.text == "Hi にほ")
        // Commit: the edit goes out, then the held state applies as the base.
        let effects = r.localChange(text: "Hi 日本", selection: .caret(5), composing: false, now: 1.3)
        let edit = try! #require(sentEdit(effects))
        #expect(edit.replacement == "日本" && edit.baseRevision == 1)
        #expect(r.mac?.revision == 2)
        #expect(r.text == "Hi 日本") // the composition wasn't yanked
    }

    @Test("A caret moved here goes out as textSelect; stale Mac selections are ignored")
    func selection() {
        var r = synced("Hello world")
        let out = r.localSelection(.caret(5), now: 2)
        let select = try! #require(sentSelect(out))
        #expect(select.range == .caret(5) && select.baseRevision == 1 && select.field == field)
        // A late state still showing the old caret: ignored within the grace.
        let v21 = r.receive(state("Hello world", rev: 1, sel: 11), now: 2.1)
        #expect(v21.isEmpty)
        #expect(r.selection == .caret(5))
        // The Mac follows: done.
        let v22 = r.receive(state("Hello world", rev: 2, sel: 5), now: 2.2)
        #expect(v22.isEmpty)
        // A selection range (system handles) goes too.
        let v23 = r.localSelection(TextRange(start: 0, length: 5), now: 3)
        #expect(sentSelect(v23)?.range == TextRange(start: 0, length: 5))
        // The same selection as the Mac's sends nothing.
        _ = r.receive(state("Hello world", rev: 3, sel: 11), now: 4)
        let v24 = r.localSelection(.caret(11), now: 4.1)
        #expect(v24.isEmpty)
    }

    @Test("The caret moved on the Mac: the iPad caret follows")
    func macMovesCaret() {
        var r = synced("Hello world")
        let v25 = r.receive(state("Hello world", rev: 2, sel: 0), now: 1)
        #expect(v25 == [.show(text: "Hello world", selection: .caret(0))])
    }

    @Test("A caret moved here during an edit goes out after it")
    func selectAfterEdit() {
        var r = synced("Hello")
        let edit = try! #require(sentEdit(r.localChange(text: "Hello!", selection: .caret(6), composing: false, now: 1)))
        let v26 = r.localSelection(.caret(0), now: 1.01)
        #expect(v26.isEmpty)
        _ = r.receive(state("Hello!", rev: 2), now: 1.02)
        let effects = r.receive(TextEditResult(field: field, request: edit.request, outcome: .applied, revision: 2), now: 1.03)
        #expect(sentSelect(effects)?.range == .caret(0))
    }

    @Test("Offsets are absolute: a window deep in a long field")
    func absolute() {
        var r = TextSyncReconciler()
        _ = r.receive(state("middle text", rev: 5, sel: 6, start: 2_000, length: 9_000), now: 0)
        #expect(r.selection == .caret(6))
        let edit = try! #require(sentEdit(r.localChange(text: "middle! text", selection: .caret(7), composing: false, now: 1)))
        #expect(edit.range == .caret(2_006))
        let v27 = r.localSelection(.caret(0), now: 5)
        #expect(sentSelect(v27) == nil) // in flight
    }

    @Test("A new field resets: no edit for the old one survives")
    func newField() {
        var r = synced("old")
        _ = r.localChange(text: "old!", selection: .caret(4), composing: false, now: 1)
        let effects = r.receive(state("new field", rev: 1, field: FieldToken(99)), now: 1.1)
        #expect(effects == [.show(text: "new field", selection: .caret(9))])
        #expect(r.badge(now: 1.1) == .sync)
    }

    @Test("Unreadable: back to the blind buffer with a reason")
    func blind() {
        var r = synced("text")
        let effects = r.receive(.unreadable(.secure, field: FieldToken(3), revision: 1), now: 1)
        #expect(effects == [.becameBlind])
        #expect(!r.isSynced && r.badge(now: 1) == .blind)
        #expect(r.reasonLine == "Password field: the text stays on the Mac")
        // Blind: local changes send nothing (the field types blind, as before).
        let v28 = r.localChange(text: "x", selection: .caret(1), composing: false, now: 2)
        #expect(v28.isEmpty)
    }

    @Test("An edit the Mac never answers is given up")
    func timeout() {
        var r = synced("a")
        _ = r.localChange(text: "ab", selection: .caret(2), composing: false, now: 1)
        let effects = r.receive(state("a", rev: 1), now: 5)
        #expect(effects == [.show(text: "a", selection: .caret(1))])
        #expect(r.badge(now: 5) == .sync)
    }

    @Test("A refused edit shows the Mac's text without MAC WINS")
    func refused() {
        var r = synced("a")
        let edit = try! #require(sentEdit(r.localChange(text: "ab", selection: .caret(2), composing: false, now: 1)))
        let effects = r.receive(TextEditResult(field: field, request: edit.request, outcome: .refused(reason: .notEditable), revision: 1), now: 1.1)
        #expect(effects == [.show(text: "a", selection: .caret(1))])
        #expect(r.badge(now: 1.1) == .sync)
    }

    @Test("A replacement over 4 KiB goes in parts")
    func longPaste() {
        var r = synced("")
        let big = String(repeating: "abcdefgh", count: 1_000) // 8 000 bytes
        let first = try! #require(sentEdit(r.localChange(text: big, selection: .caret(8_000), composing: false, now: 1)))
        #expect(first.replacement.utf8.count <= TextSyncPolicy.maxReplacementBytes)
        _ = r.receive(state(first.replacement, rev: 2), now: 1.5)
        let rest = try! #require(sentEdit(r.receive(TextEditResult(field: field, request: first.request, outcome: .applied, revision: 2), now: 1.6)))
        #expect(rest.range.start == first.replacement.utf16.count)
        #expect(first.replacement + rest.replacement == big)
    }

    @Test("Context hashes let the Mac find the range")
    func contextMatchesMac() {
        var r = synced("I said teh cat")
        let edit = try! #require(sentEdit(r.localChange(text: "I said the cat", selection: .caret(14), composing: false, now: 1)))
        let units = Array("I said teh cat".utf16)
        let decision = TextEditCheck.decide(edit, field: field, readable: .yes, canEdit: true, fieldLength: units.count, span: units, spanStart: 0)
        #expect(decision == .apply(TextRange(start: 8, length: 2)))
    }

    @Test("Badge labels")
    func badges() {
        #expect(SyncBadge.allCases.map(\.label) == ["SYNC", "SENDING", "MAC WINS", "BLIND"])
    }
}

// MARK: - Lock gate, validation, logs

@Suite struct LiveTextSyncGateTests {
    let edit = TextEditRequest(field: FieldToken(1), request: 1, baseRevision: 1, range: .caret(0), replacement: "a",
                               context: TextEditContext(beforeHash: 0, beforeLength: 0, afterHash: 0, afterLength: 0))

    @Test("Locked: edits, selections and caret moves are dropped; watching passes")
    func lock() {
        let move = CaretMove(direction: .left, unit: .character, count: 1, extend: false)
        for lock in [MacLockState.screenLocked, .offConsole] {
            #expect(LockPolicy.decide(.input(.textEdit(edit: edit)), state: lock) == .refuse(reply: .none))
            #expect(LockPolicy.decide(.input(.textSelect(selection: TextSelectRequest(field: FieldToken(1), baseRevision: 1, range: .caret(0)))), state: lock) == .refuse(reply: .none))
            #expect(LockPolicy.decide(.input(.caretMove(move: move)), state: lock) == .refuse(reply: .none))
            #expect(LockPolicy.decide(.system(.watchFocus(on: true, wantsText: true)), state: lock) == .allow)
            #expect(LockPolicy.withholdsText(lock))
        }
        #expect(LockPolicy.decide(.input(.textEdit(edit: edit)), state: .unlocked) == .allow)
        #expect(!LockPolicy.withholdsText(.unlocked))
        // The password is still typed as keys at the lock screen.
        #expect(LockPolicy.decide(.input(.typeText(text: "pw")), state: .screenLocked) == .allow)
    }

    @Test("A textState or textEditResult sent to the Mac is dropped")
    func macToRemoteOnly() {
        #expect(RemoteInputValidation.sanitize(.system(.textState(state: .unreadable(.noField)))) == nil)
        #expect(RemoteInputValidation.sanitize(.system(.textEditResult(result: TextEditResult(field: .none, request: 1, outcome: .applied, revision: 1)))) == nil)
        #expect(RemoteInputValidation.sanitize(.system(.watchFocus(on: true, wantsText: true))) == .system(.watchFocus(on: true, wantsText: true)))
    }

    @Test("Edits: sane ranges, bounded and clean replacements; deletions pass")
    func validation() {
        #expect(RemoteInputValidation.sanitize(.input(.textEdit(edit: edit))) == .input(.textEdit(edit: edit)))
        var deletion = edit
        deletion.range = TextRange(start: 3, length: 2)
        deletion.replacement = ""
        #expect(RemoteInputValidation.sanitize(.input(.textEdit(edit: deletion))) != nil)
        var negative = edit
        negative.range = TextRange(start: -1, length: 0)
        #expect(RemoteInputValidation.sanitize(.input(.textEdit(edit: negative))) == nil)
        var huge = edit
        huge.range = TextRange(start: Int.max - 1, length: 5)
        #expect(RemoteInputValidation.sanitize(.input(.textEdit(edit: huge))) == nil)
        var long = edit
        long.replacement = String(repeating: "x", count: 4_097)
        #expect(RemoteInputValidation.sanitize(.input(.textEdit(edit: long))) == nil)
        var control = edit
        control.replacement = "a\u{1B}b"
        #expect(RemoteInputValidation.sanitize(.input(.textEdit(edit: control))) == nil)
        var context = edit
        context.context.beforeLength = 11
        #expect(RemoteInputValidation.sanitize(.input(.textEdit(edit: context))) == nil)
        let badSelect = TextSelectRequest(field: FieldToken(1), baseRevision: 1, range: TextRange(start: 0, length: -1))
        #expect(RemoteInputValidation.sanitize(.input(.textSelect(selection: badSelect))) == nil)
    }

    @Test("caretMove: count clamped, zero dropped")
    func caretMoveValidation() {
        let many = CaretMove(direction: .right, unit: .character, count: 250, extend: false)
        guard case let .input(.caretMove(safe))? = RemoteInputValidation.sanitize(.input(.caretMove(move: many))) else {
            Issue.record("dropped")
            return
        }
        #expect(safe.count == TextSyncPolicy.maxCaretMoveCount)
        let zero = CaretMove(direction: .right, unit: .character, count: 0, extend: false)
        #expect(RemoteInputValidation.sanitize(.input(.caretMove(move: zero))) == nil)
    }

    @Test("Sync traffic isn't a person action for display wake, except input")
    func displayWake() {
        #expect(!DisplayWakePolicy.isPersonAction(.system(.textState(state: .unreadable(.noField)))))
        #expect(DisplayWakePolicy.isPersonAction(.input(.textEdit(edit: edit))))
    }
}

@Suite struct TextSyncLogTests {
    @Test("Log lines carry offsets and sizes, never the text")
    func noTextInLogs() {
        let secret = "hunter2-secret"
        let state = FocusedTextState(field: FieldToken(4), revision: 3, readable: .webOff(app: "SecretApp"),
                                     window: TextWindow(start: 10, value: secret), length: 40,
                                     selection: .caret(12), canSetSelection: true, canEdit: true)
        let edit = TextEditRequest(field: FieldToken(4), request: 2, baseRevision: 3, range: .caret(12), replacement: secret,
                                   context: TextEditContext(beforeHash: 1, beforeLength: 2, afterHash: 3, afterLength: 4))
        let lines = [
            TextSyncLog.describe(state),
            TextSyncLog.describe(edit),
            TextSyncLog.describe(TextSelectRequest(field: FieldToken(4), baseRevision: 3, range: .caret(1))),
            TextSyncLog.describe(TextEditResult(field: FieldToken(4), request: 2, outcome: .refused(reason: .secure), revision: 3)),
        ]
        for line in lines {
            #expect(!line.contains("hunter2"))
            #expect(!line.contains("SecretApp"))
        }
        #expect(lines[1].contains("14 units"))
    }
}
