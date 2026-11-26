//
//  TypePanelTests.swift
//  PixelHandCoreTests
//
//  Owner testing, build 24: the keyboard loop (OT-2) and the Type panel
//  (OT-3).
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("Keyboard never changes the arrangement (OT-2)")
struct ShellKeyboardTests {
    /// Window sizes the owner and QA use: iPad Air 11" (M3) landscape and
    /// portrait, iPad 13", Stage Manager windows, ½ and ⅓ Split View,
    /// iPhone portrait and landscape.
    static let windows: [(String, Double, Double)] = [
        ("iPad Air 11 landscape", 1180, 820),
        ("iPad Air 11 portrait", 820, 1180),
        ("iPad 13 landscape", 1366, 1024),
        ("Stage Manager large", 1000, 760),
        ("Stage Manager small", 700, 600),
        ("Split ½ landscape", 590, 820),
        ("Split ⅓", 375, 820),
        ("iPhone portrait", 402, 874),
        ("iPhone landscape", 874, 402),
    ]

    /// Typical on-screen keyboard heights (iPad landscape ≈ 400, iPhone
    /// landscape ≈ 200, with the predictive bar).
    static let keyboards: [Double] = [0, 55, 200, 300, 400, 420]

    @Test("The form is planned from the window, whatever the keyboard covers")
    func formIgnoresKeyboard() {
        for (name, width, height) in Self.windows {
            let open = ShellPlanningSize.size(measuredWidth: width, measuredHeight: height)
            let expected = CanvasPlan(width: open.width, height: open.height).form
            for overlap in Self.keyboards {
                // A host that could only measure the keyboard-shortened
                // frame gives the keyboard's height back.
                let shortened = ShellPlanningSize.size(
                    measuredWidth: width,
                    measuredHeight: height - overlap,
                    keyboardShortening: overlap
                )
                #expect(CanvasPlan(width: shortened.width, height: shortened.height).form == expected, "\(name) with \(overlap) pt keyboard")
            }
        }
    }

    @Test("Regression: planning from the keyboard-shortened frame flips iPad landscape to the rail")
    func shortenedFrameWasTheBug() {
        // Build 24: 820 − 400 = 420 pt tall reads as "short", the shell
        // switched to the rail, rebuilt the field, the keyboard dropped,
        // the layout went back to columns, and round it went.
        #expect(CanvasPlan(width: 1180, height: 820).form == .columns)
        #expect(CanvasPlan(width: 1180, height: 420).form == .rail)
        let fixed = ShellPlanningSize.size(measuredWidth: 1180, measuredHeight: 420, keyboardShortening: 400)
        #expect(CanvasPlan(width: fixed.width, height: fixed.height).form == .columns)
    }

    @Test("A negative shortening is ignored")
    func negativeShortening() {
        let size = ShellPlanningSize.size(measuredWidth: 800, measuredHeight: 600, keyboardShortening: -50)
        #expect(size.height == 600)
    }

    @Test("Keyboard classification: on-screen, hardware's shortcut bar, none")
    func classify() {
        #expect(KeyboardKind.classify(overlap: 400, hardwareAttached: false) == .software)
        #expect(KeyboardKind.classify(overlap: 400, hardwareAttached: true) == .software)
        #expect(KeyboardKind.classify(overlap: 55, hardwareAttached: true) == .hardware)
        #expect(KeyboardKind.classify(overlap: 0, hardwareAttached: true) == .hardware)
        #expect(KeyboardKind.classify(overlap: 0, hardwareAttached: false) == .none)
        #expect(KeyboardKind.classify(overlap: 119, hardwareAttached: false) == .none)
        #expect(KeyboardKind.classify(overlap: 120, hardwareAttached: false) == .software)
    }

    @Test("Overlap: docked covers the foot; floating, undocked and hidden cover nothing")
    func overlap() {
        // Docked keyboard, 400 tall, on an 820 pt window.
        #expect(KeyboardKind.overlap(windowMaxY: 820, keyboardMinY: 420, keyboardMaxY: 820, keyboardHeight: 400) == 400)
        // Stage Manager window that ends above the keyboard's top.
        #expect(KeyboardKind.overlap(windowMaxY: 380, keyboardMinY: 420, keyboardMaxY: 820, keyboardHeight: 400) == 0)
        // Stage Manager window partly over the keyboard.
        #expect(KeyboardKind.overlap(windowMaxY: 820, keyboardMinY: 500, keyboardMaxY: 1024, keyboardHeight: 524) == 320)
        // Floating keyboard in the middle of the screen.
        #expect(KeyboardKind.overlap(windowMaxY: 820, keyboardMinY: 300, keyboardMaxY: 560, keyboardHeight: 260) == 0)
        // Hidden: off-screen frame.
        #expect(KeyboardKind.overlap(windowMaxY: 820, keyboardMinY: 820, keyboardMaxY: 1220, keyboardHeight: 400) == 0)
        #expect(KeyboardKind.overlap(windowMaxY: 820, keyboardMinY: 420, keyboardMaxY: 820, keyboardHeight: 0) == 0)
    }
}

@Suite("Type panel presence: one owner for shown (OT-2)")
struct TypePanelPresenceTests {
    @Test("Toggle opens on Keys with a focus request, and closes")
    func toggle() {
        var presence = TypePanelPresence()
        #expect(!presence.isShown && !presence.wantsFocus)
        presence.toggle()
        #expect(presence.isShown && presence.tab == .keys && presence.wantsFocus)
        #expect(presence.focusRequest == 1)
        presence.toggle()
        #expect(!presence.isShown && !presence.wantsFocus)
    }

    @Test("Opening while open only asks for focus again (the lock banner's Keyboard)")
    func openTwice() {
        var presence = TypePanelPresence()
        presence.open()
        presence.select(.numpad)
        presence.open()
        #expect(presence.isShown)
        #expect(presence.tab == .numpad)
        #expect(presence.focusRequest == 2)
    }

    @Test("Numpad lets the system keyboard go; Keys asks for it back")
    func tabs() {
        var presence = TypePanelPresence()
        presence.open()
        presence.select(.numpad)
        #expect(!presence.wantsFocus)
        let before = presence.focusRequest
        presence.select(.keys)
        #expect(presence.wantsFocus)
        #expect(presence.focusRequest == before + 1)
    }

    @Test("Closing lets go of modifiers and the fn row")
    func closeClears() {
        var presence = TypePanelPresence(mode: .compose)
        presence.open()
        presence.modifiers.tap(.command)
        presence.showsFunctionKeys = true
        presence.close()
        #expect(presence.modifiers.isEmpty)
        #expect(!presence.showsFunctionKeys)
        #expect(presence.mode == .compose)
    }

    @Test("The last mode is remembered; unknown or missing restores Live")
    func restoredMode() {
        #expect(TypeMode.restored("compose") == .compose)
        #expect(TypeMode.restored("live") == .live)
        #expect(TypeMode.restored(nil) == .live)
        #expect(TypeMode.restored("dictate") == .live)
    }
}

@Suite("Type panel keys (OT-3)")
struct TypeKeysTests {
    @Test("Every key in the row and the fn row exists in the Mac's key table")
    func keysResolve() {
        for key in TypeKeysRow.main + TypeKeysRow.functionKeys {
            #expect(KeyTable.keyCode(for: key.wireName) != nil, "\(key.wireName)")
            #expect(!key.cap.isEmpty && !key.spokenName.isEmpty)
        }
        #expect(TypeKeysRow.functionKeys.map(\.cap) == (1...12).map { "F\($0)" })
    }

    @Test("The row has esc, tab, ⌫, ⏎, the arrows, home/end and page up/down")
    func rowContents() {
        let names = TypeKeysRow.main.map(\.wireName)
        #expect(names == ["escape", "tab", "delete", "return", "left", "down", "up", "right", "home", "end", "pageup", "pagedown"])
        #expect(TypeKeysRow.keys(showsFunctionKeys: true) == TypeKeysRow.functionKeys)
        #expect(TypeKeysRow.keys(showsFunctionKeys: false) == TypeKeysRow.main)
    }

    @Test("Chords press modifiers in the Mac's order")
    func chords() {
        #expect(TypeKey.remote(.left).chord(with: [.shift, .option]) == ["shift", "option", "left"])
        #expect(TypeKey.function(5).chord(with: []) == ["f5"])
        #expect(KeyTable.chord(TypeKey.remote(.left).chord(with: [.command, .shift])) != nil)
        #expect(TypeKey.remote(.return).isReturn)
        #expect(!TypeKey.remote(.tab).isReturn)
    }
}

@Suite("Sticky modifiers (OT-3)")
struct ModifierLatchTests {
    @Test("Tap: once, again: locked, again: off")
    func cycle() {
        var latch = ModifierLatch()
        latch.tap(.command)
        #expect(latch.state(.command) == .once && latch.isLit(.command))
        latch.tap(.command)
        #expect(latch.state(.command) == .locked && latch.isLit(.command))
        latch.tap(.command)
        #expect(latch.state(.command) == .off && !latch.isLit(.command))
    }

    @Test("A key uses up once-modifiers and keeps locked ones")
    func consume() {
        var latch = ModifierLatch()
        latch.tap(.shift)
        latch.tap(.command)
        latch.tap(.command) // locked
        let used = latch.consume()
        #expect(used == [.command, .shift])
        #expect(latch.held == [.command])
        #expect(latch.consume() == [.command])
        #expect(latch.held == [.command])
    }

    @Test("Held modifiers come out in press order, and VoiceOver hears the state")
    func order() {
        var latch = ModifierLatch()
        latch.tap(.shift)
        latch.tap(.control)
        latch.tap(.option)
        #expect(latch.held == [.shift, .option, .control])
        #expect(latch.spokenValue(.shift) == "Held for the next key")
        #expect(latch.spokenValue(.command) == "Off")
        latch.clear()
        #expect(latch.isEmpty)
        #expect(ModifierLatch.chips.map(\.chipGlyph) == ["⌘", "⌥", "⌃", "⇧"])
    }
}

@Suite("Numpad (OT-3)")
struct NumpadTests {
    @Test("A 4 × 5 grid with every cell filled once: 0 spans two columns, Enter two rows")
    func grid() {
        var covered = Set<String>()
        for key in NumpadKey.allCases {
            let cell = key.cell
            for column in cell.column..<(cell.column + cell.columnSpan) {
                for row in cell.row..<(cell.row + cell.rowSpan) {
                    let spot = "\(column),\(row)"
                    #expect(!covered.contains(spot), "\(key) overlaps at \(spot)")
                    covered.insert(spot)
                }
            }
        }
        #expect(covered.count == NumpadKey.columns * NumpadKey.rows)
        #expect(NumpadKey.zero.cell.columnSpan == 2)
        #expect(NumpadKey.enter.cell.rowSpan == 2)
        #expect(NumpadKey.row(4) == [.zero, .point])
    }

    @Test("Digits, point and operators type text; Enter and ⌫ press keys the Mac knows")
    func outputs() {
        for key in NumpadKey.allCases {
            switch key.output {
            case let .text(text):
                #expect(!text.isEmpty)
                let ascii = text.allSatisfy { $0.isASCII }
                #expect(ascii, "\(key)")
            case let .key(name):
                #expect(KeyTable.keyCode(for: name) != nil, "\(key)")
            }
        }
        #expect(NumpadKey.seven.output == .text("7"))
        #expect(NumpadKey.multiply.output == .text("*"))
        #expect(NumpadKey.divide.output == .text("/"))
        #expect(NumpadKey.enter.output == .key("keypadenter"))
        #expect(NumpadKey.delete.output == .key("delete"))
    }

    @Test("Every cap draws in the dot-matrix font")
    func capsDraw() {
        for key in NumpadKey.allCases where key != .delete {
            for character in key.cap {
                #expect(DotMatrixFont.characters.contains(character), "\(key): \(character)")
            }
        }
        #expect(NumpadKey.allCases.filter(\.isOperator).count == 5)
    }
}

@Suite("Compose send (OT-3)")
struct ComposeSendTests {
    @Test("Send types the draft, then Return when asked")
    func send() {
        #expect(ComposeSend.messages(draft: "hello", withReturn: false) == [.text("hello")])
        #expect(ComposeSend.messages(draft: "hello", withReturn: true) == [.text("hello"), .key("return")])
    }

    @Test("A blank draft sends nothing, except a bare Return when asked")
    func blank() {
        #expect(ComposeSend.messages(draft: "  \n", withReturn: false).isEmpty)
        #expect(ComposeSend.messages(draft: "", withReturn: true) == [.key("return")])
        #expect(!ComposeSend.canSend(draft: " ", withReturn: false))
        #expect(ComposeSend.canSend(draft: " ", withReturn: true))
        #expect(ComposeSend.canSend(draft: "x", withReturn: false))
    }

    @Test("A long draft goes in pieces the Mac accepts")
    func chunks() {
        let draft = String(repeating: "abcdefghij", count: 1_000)
        let messages = ComposeSend.messages(draft: draft, withReturn: true)
        let texts = messages.compactMap { message -> String? in
            if case let .text(text) = message { return text }
            return nil
        }
        #expect(texts.count > 1)
        #expect(texts.joined() == draft)
        #expect(texts.allSatisfy { $0.utf8.count <= TypingPolicy.maxMessageBytes })
        #expect(messages.last == .key("return"))
    }
}

@Suite("Type panel layout (OT-2, OT-3)")
struct TypePanelLayoutTests {
    @Test("A hardware keyboard shows the keys row and modifiers only")
    func hardware() {
        #expect(TypePanelLayout(width: 1180, height: 820, keyboard: .hardware).body == .keysOnly)
        #expect(TypePanelLayout(width: 1180, height: 820, keyboard: .software, keyboardOverlap: 400).body == .full)
        #expect(TypePanelLayout(width: 1180, height: 820, keyboard: .none).body == .full)
    }

    @Test("Wide windows cap the panel and put the chips in the keys row")
    func wide() {
        let layout = TypePanelLayout(width: 1180, height: 820, keyboard: .software, keyboardOverlap: 400)
        #expect(layout.maximumWidth == TypePanelLayout.wideMaximumWidth)
        #expect(layout.modifiersInKeysRow)
        #expect(layout.showsHeader && layout.targetInHeader)
        let portrait = TypePanelLayout(width: 820, height: 1180, keyboard: .software, keyboardOverlap: 320)
        #expect(portrait.modifiersInKeysRow && portrait.showsHeader)
        let phone = TypePanelLayout(width: 402, height: 874, keyboard: .software, keyboardOverlap: 336)
        #expect(phone.maximumWidth == 402 - 32)
        #expect(!phone.modifiersInKeysRow)
        #expect(phone.showsHeader && !phone.targetInHeader)
    }

    @Test("iPhone landscape with the keyboard up: no header, chips in the keys row")
    func shortRoom() {
        let landscape = TypePanelLayout(width: 874, height: 402, keyboard: .software, keyboardOverlap: 200)
        #expect(!landscape.showsHeader)
        #expect(landscape.modifiersInKeysRow)
        #expect(landscape.body == .full)
        // The keyboard dismissed: the header comes back.
        #expect(TypePanelLayout(width: 874, height: 402, keyboard: .none).showsHeader)
        // Hardware keyboard: keys only, no header.
        #expect(!TypePanelLayout(width: 1180, height: 820, keyboard: .hardware).showsHeader)
    }

    @Test("Compose grows with the room above the keyboard")
    func composeLines() {
        #expect(TypePanelLayout(width: 874, height: 402, keyboard: .software, keyboardOverlap: 200).composeLines == 1)
        #expect(TypePanelLayout(width: 1180, height: 820, keyboard: .software, keyboardOverlap: 400).composeLines == 2)
        #expect(TypePanelLayout(width: 820, height: 1180, keyboard: .software, keyboardOverlap: 320).composeLines == 4)
        #expect(TypePanelLayout(width: 820, height: 1180, keyboard: .hardware).composeLines == 4)
    }

    @Test("Numpad keys are whole points, at least 44, and the grid fits the panel")
    func numpad() {
        for (_, width, height) in ShellKeyboardTests.windows {
            let layout = TypePanelLayout(width: width, height: height, keyboard: .none)
            #expect(layout.numpadKeySize >= TypePanelLayout.numpadMinimumKey)
            #expect(layout.numpadKeySize <= TypePanelLayout.numpadMaximumKey)
            #expect(layout.numpadKeySize == layout.numpadKeySize.rounded())
            #expect(layout.numpadSize.width <= max(layout.maximumWidth, 4 * 44 + 24))
        }
    }

    @Test("The panel sits on the keyboard, or above the dock when nothing covers it")
    func bottomPadding() {
        // iPad landscape, 820 tall: keyboard top 420 covers the dock (740).
        #expect(TypePanelLayout.bottomPadding(containerMaxY: 800, keyboardMinY: 420, dockMinY: 740) == 388)
        // No keyboard: above the dock.
        #expect(TypePanelLayout.bottomPadding(containerMaxY: 800, keyboardMinY: nil, dockMinY: 740) == 68)
        // Hardware keyboard's shortcut bar only, no dock (rail, laptop).
        #expect(TypePanelLayout.bottomPadding(containerMaxY: 800, keyboardMinY: 770, dockMinY: nil) == 38)
        // Nothing under it.
        #expect(TypePanelLayout.bottomPadding(containerMaxY: 800, keyboardMinY: nil, dockMinY: nil) == 8)
        // A keyboard frame below the container (Stage Manager window above it).
        #expect(TypePanelLayout.bottomPadding(containerMaxY: 380, keyboardMinY: 420, dockMinY: nil) == 8)
    }
}
