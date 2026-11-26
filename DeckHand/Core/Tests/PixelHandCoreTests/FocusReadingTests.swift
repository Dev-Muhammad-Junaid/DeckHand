//
//  FocusReadingTests.swift
//  PixelHandCoreTests
//
//  OT-12 / OT-13: the Mac's rules for reading the focused field, the lock
//  gate and validation for the focus messages.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct FocusReadingTests {
    // MARK: Roles and privacy

    @Test("Accessibility roles map to the snapshot's roles")
    func roles() {
        #expect(FocusReading.role(axRole: "AXTextField", axSubrole: nil) == .textField)
        #expect(FocusReading.role(axRole: "AXTextField", axSubrole: "AXSearchField") == .textField)
        #expect(FocusReading.role(axRole: "AXTextArea", axSubrole: nil) == .textArea)
        #expect(FocusReading.role(axRole: "AXComboBox", axSubrole: nil) == .comboBox)
        #expect(FocusReading.role(axRole: "AXWebArea", axSubrole: nil) == .webArea)
        #expect(FocusReading.role(axRole: "AXButton", axSubrole: nil) == .other)
        #expect(FocusReading.role(axRole: nil, axSubrole: nil) == .other)
    }

    @Test("Text is read only from native, non-secure text fields on an unlocked Mac")
    func mayReadText() {
        #expect(FocusReading.mayReadText(axRole: "AXTextField", axSubrole: nil, inWebContent: false, lock: .unlocked))
        #expect(FocusReading.mayReadText(axRole: "AXTextArea", axSubrole: nil, inWebContent: false, lock: .unlocked))
        #expect(FocusReading.mayReadText(axRole: "AXComboBox", axSubrole: nil, inWebContent: false, lock: .unlocked))
        // Password fields, by role or subrole, however named.
        #expect(!FocusReading.mayReadText(axRole: "AXTextField", axSubrole: "AXSecureTextField", inWebContent: false, lock: .unlocked))
        #expect(!FocusReading.mayReadText(axRole: "AXSecureTextField", axSubrole: nil, inWebContent: false, lock: .unlocked))
        #expect(!FocusReading.mayReadText(axRole: "AXTextField", axSubrole: "AXPasswordField", inWebContent: false, lock: .unlocked))
        // Web content, web areas and other roles.
        #expect(!FocusReading.mayReadText(axRole: "AXTextArea", axSubrole: nil, inWebContent: true, lock: .unlocked))
        #expect(!FocusReading.mayReadText(axRole: "AXWebArea", axSubrole: nil, inWebContent: false, lock: .unlocked))
        #expect(!FocusReading.mayReadText(axRole: "AXStaticText", axSubrole: nil, inWebContent: false, lock: .unlocked))
        // Locked or off console.
        #expect(!FocusReading.mayReadText(axRole: "AXTextField", axSubrole: nil, inWebContent: false, lock: .screenLocked))
        #expect(!FocusReading.mayReadText(axRole: "AXTextField", axSubrole: nil, inWebContent: false, lock: .offConsole))
    }

    // MARK: Text window

    @Test("A short field is read whole; a long one around the caret, inside the field")
    func textWindow() {
        #expect(FocusReading.textWindow(count: 120, selectionStart: 40) == (0, 120))
        #expect(FocusReading.textWindow(count: 5_000, selectionStart: 2_500) == (2_167, 1_000))
        #expect(FocusReading.textWindow(count: 5_000, selectionStart: 100) == (0, 1_000))
        #expect(FocusReading.textWindow(count: 5_000, selectionStart: 4_990) == (4_000, 1_000))
        #expect(FocusReading.textWindow(count: 5_000, selectionStart: 99_999) == (4_000, 1_000))
        #expect(FocusReading.textWindow(count: 0, selectionStart: 0) == (0, 0))
    }

    @Test("The selection is made relative to the window, with truncation flags")
    func textRelative() {
        let t = FocusReading.text(window: "hello world", windowLocation: 100, totalCount: 500, selectionStart: 106, selectionLength: 5)
        #expect(t.value == "hello world")
        #expect(t.selection == FocusedText.Selection(start: 6, length: 5))
        #expect(t.truncatedBefore && t.truncatedAfter)
        #expect(t.suggestion == nil)

        let whole = FocusReading.text(window: "abc", windowLocation: 0, totalCount: 3, selectionStart: 3, selectionLength: 0)
        #expect(!whole.truncatedBefore && !whole.truncatedAfter)
        #expect(whole.selection == FocusedText.Selection(start: 3, length: 0))
    }

    @Test("A selection outside the window is clamped into it")
    func textClamped() {
        let t = FocusReading.text(window: "abcdef", windowLocation: 10, totalCount: 100, selectionStart: 2, selectionLength: 50)
        #expect(t.selection == FocusedText.Selection(start: 0, length: 6))
        let after = FocusReading.text(window: "abcdef", windowLocation: 10, totalCount: 100, selectionStart: 90, selectionLength: 1)
        #expect(after.selection == FocusedText.Selection(start: 6, length: 0))
    }

    @Test("Text over the limit is cut on whole characters, never inside an emoji")
    func textCutOnCharacters() {
        let window = String(repeating: "a", count: 9) + "👋🏽" + "bc"
        let t = FocusReading.text(window: window, windowLocation: 0, totalCount: 13, selectionStart: 0, selectionLength: 0, limit: 10)
        #expect(t.value == String(repeating: "a", count: 9))
        #expect(t.truncatedAfter)
    }

    // MARK: Caret

    @Test("A caret from a neighbouring character's rect")
    func caretFromCharacter() {
        let ch = FocusRect(x: 100, y: 50, width: 8, height: 16)
        #expect(FocusReading.caret(after: ch) == FocusRect(x: 108, y: 50, width: 1, height: 16))
        #expect(FocusReading.caret(before: ch) == FocusRect(x: 100, y: 50, width: 1, height: 16))
        #expect(FocusReading.isUsable(ch))
        #expect(!FocusReading.isUsable(FocusRect(x: 0, y: 0, width: 0, height: 0)))
        #expect(!FocusReading.isUsable(FocusRect(x: 10, y: 10, width: 0, height: 0)))
        #expect(!FocusReading.isUsable(FocusRect(x: .infinity, y: 10, width: 1, height: 10)))
        #expect(!FocusReading.isUsable(FocusRect(x: 1e9, y: 10, width: 1, height: 10)))
    }

    // MARK: Displays

    static let main = FocusReading.Display(id: 1, bounds: FocusRect(x: 0, y: 0, width: 1512, height: 982))
    // An external display to the left and above (negative global origin).
    static let left = FocusReading.Display(id: 2, bounds: FocusRect(x: -2560, y: -458, width: 2560, height: 1440))

    @Test("A global rect is placed on the display it overlaps most, in its local points")
    func displays() throws {
        let displays = [Self.main, Self.left]
        let onLeft = FocusRect(x: -1000, y: -200, width: 300, height: 22)
        let d = try #require(FocusReading.display(for: onLeft, among: displays))
        #expect(d.id == 2)
        #expect(FocusReading.local(onLeft, on: d) == FocusRect(x: 1560, y: 258, width: 300, height: 22))

        // Straddling: more of it on the main display.
        let straddle = FocusRect(x: -100, y: 100, width: 400, height: 22)
        #expect(FocusReading.display(for: straddle, among: displays)?.id == 1)

        // A zero-width caret, on the main display.
        #expect(FocusReading.display(for: FocusRect(x: 20, y: 20, width: 0, height: 16), among: displays)?.id == 1)
        // Off every display: the nearest.
        #expect(FocusReading.display(for: FocusRect(x: 1600, y: 100, width: 10, height: 10), among: displays)?.id == 1)
        #expect(FocusReading.display(for: onLeft, among: []) == nil)
    }

    // MARK: Change detection and pacing

    static func snap(field: FocusRect? = FocusRect(x: 10, y: 10, width: 200, height: 22), text: String? = nil) -> FocusedFieldSnapshot {
        FocusedFieldSnapshot(
            displayID: 1, displayWidth: 1512, displayHeight: 982,
            field: field, caret: nil, pointer: FocusRect(x: 5, y: 5, width: 24, height: 24),
            source: .accessibility, app: "Notes", role: .textArea,
            text: text.map { FocusedText(value: $0, selection: .init(start: 0, length: 0), truncatedBefore: false, truncatedAfter: false, suggestion: nil) }
        )
    }

    @Test("Only meaningful changes are sent")
    func changes() {
        let a = Self.snap()
        #expect(FocusReading.differsMeaningfully(a, from: nil))
        #expect(!FocusReading.differsMeaningfully(a, from: a))
        #expect(!FocusReading.differsMeaningfully(Self.snap(field: FocusRect(x: 10.5, y: 10, width: 200, height: 22)), from: a))
        #expect(FocusReading.differsMeaningfully(Self.snap(field: FocusRect(x: 12, y: 10, width: 200, height: 22)), from: a))
        #expect(FocusReading.differsMeaningfully(Self.snap(field: nil), from: a))
        #expect(FocusReading.differsMeaningfully(Self.snap(text: "a"), from: a))
        var other = a
        other.app = "Mail"
        #expect(FocusReading.differsMeaningfully(other, from: a))
    }

    @Test("At most eight looks a second, four once it's quiet")
    func pacing() {
        #expect(FocusReading.pollInterval(unchangedFor: 0) == 0.125)
        #expect(FocusReading.pollInterval(unchangedFor: 1.9) == 0.125)
        #expect(FocusReading.pollInterval(unchangedFor: 2) == 0.25)
    }

    // MARK: Protocol rules

    static let state = ControlMessage.system(.focusState(focus: .nothing(displayID: 1, displayWidth: 10, displayHeight: 10)))

    @Test("The lock gate lets the subscription through and withholds the focus")
    func lockGate() {
        for lock in [MacLockState.unlocked, .screenLocked, .offConsole] {
            #expect(LockPolicy.decide(.system(.watchFocus(on: true)), state: lock) == .allow)
            #expect(LockPolicy.decide(.system(.watchFocus(on: false)), state: lock) == .allow)
        }
        #expect(!LockPolicy.withholdsFocus(.unlocked))
        #expect(LockPolicy.withholdsFocus(.screenLocked))
        #expect(LockPolicy.withholdsFocus(.offConsole))
        #expect(!DisplayWakePolicy.isPersonAction(.system(.watchFocus(on: true))))
    }

    @Test("A remote may ask to watch the focus but never send a focus state")
    func validation() {
        #expect(RemoteInputValidation.sanitize(.system(.watchFocus(on: true))) == .system(.watchFocus(on: true)))
        #expect(RemoteInputValidation.sanitize(Self.state) == nil)
    }

    @Test("A snapshot round-trips through JSON")
    func coding() throws {
        let s = Self.snap(text: "Hi 👋🏽")
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(FocusedFieldSnapshot.self, from: data) == s)
        let none = FocusedFieldSnapshot.nothing(displayID: 3, displayWidth: 1, displayHeight: 1)
        #expect(none.source == .none && none.field == nil && none.text == nil)
    }
}
