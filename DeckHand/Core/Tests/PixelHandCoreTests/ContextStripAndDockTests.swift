//
//  ContextStripAndDockTests.swift
//  PixelHandCoreTests
//
//  The app dock's stable order and the context strip's priority (UX-005).
//

import Testing
@testable import PixelHandCore

@Suite("App dock plan")
struct AppDockPlanTests {
    @Test("The first order is the Mac's Cmd-Tab order")
    func firstOrder() {
        #expect(AppDockPlan.order(previous: [], running: ["xcode", "safari", "music"]) == ["xcode", "safari", "music"])
    }

    @Test("Switching apps doesn't reshuffle the dock")
    func stableOnSwitch() {
        let before = ["xcode", "safari", "music"]
        // Safari comes to the front: Cmd-Tab order changes, the dock doesn't.
        #expect(AppDockPlan.order(previous: before, running: ["safari", "xcode", "music"]) == before)
    }

    @Test("New apps join at the end; quit apps leave")
    func joinAndLeave() {
        let before = ["xcode", "safari", "music"]
        let after = AppDockPlan.order(previous: before, running: ["figma", "xcode", "music", "notes"])
        #expect(after == ["xcode", "music", "figma", "notes"])
    }

    @Test("Duplicates and empty IDs are dropped")
    func duplicates() {
        #expect(AppDockPlan.order(previous: ["a", "a"], running: ["", "b", "a", "b"]) == ["a", "b"])
    }

    @Test("Entries keep only known apps and mark the front app and its dialog")
    func entries() {
        let entries = AppDockPlan.entries(order: ["xcode", "helper", "music"], known: ["xcode", "music"], front: "music", frontHasDialog: true)
        #expect(entries.map(\.bundleID) == ["xcode", "music"])
        #expect(entries.map(\.isFront) == [false, true])
        #expect(entries.map(\.hasDialog) == [false, true])
    }

    @Test("The front app is shown even before the running list has it")
    func frontAlwaysShown() {
        let entries = AppDockPlan.entries(order: ["xcode"], known: ["xcode", "notes"], front: "notes", frontHasDialog: false)
        #expect(entries.map(\.bundleID) == ["xcode", "notes"])
        #expect(entries.last?.isFront == true)
        #expect(entries.last?.hasDialog == false)
    }
}

@Suite("Context strip plan")
struct ContextStripPlanTests {
    private let save = DialogButton(id: "1", title: "Save", isDefault: true, isCancel: false)
    private let cancel = DialogButton(id: "2", title: "Cancel", isDefault: false, isCancel: true)
    private let dontSave = DialogButton(id: "3", title: "Don’t Save", isDefault: false, isCancel: false)

    private func dialog(_ buttons: [DialogButton]) -> UIContextSnapshot {
        .dialog(DialogContext(revision: "r", title: "Save changes?", message: nil, buttons: buttons))
    }

    @Test("A dialog takes over, default first on compact")
    func dialogCompact() {
        let mode = ContextStripPlan.mode(context: dialog([dontSave, cancel, save]), hasFrontApp: true, widthClass: .compact)
        #expect(mode == .dialog(title: "Save changes?", message: nil, buttons: [save, dontSave, cancel]))
    }

    @Test("On wider widths the dialog keeps the Mac's order")
    func dialogWide() {
        for width in [LayoutMetrics.WidthClass.medium, .wide] {
            let mode = ContextStripPlan.mode(context: dialog([dontSave, cancel, save]), hasFrontApp: true, widthClass: width)
            #expect(mode == .dialog(title: "Save changes?", message: nil, buttons: [dontSave, cancel, save]))
        }
    }

    @Test("A dialog with no buttons falls back to the app's chips")
    func emptyDialog() {
        #expect(ContextStripPlan.mode(context: dialog([]), hasFrontApp: true, widthClass: .compact) == .app(chipLimit: 6, editing: nil))
    }

    @Test("Button order without a default is unchanged")
    func noDefault() {
        #expect(ContextStripPlan.buttonOrder([cancel, dontSave], defaultFirst: true) == [cancel, dontSave])
    }

    @Test("A focused text field keeps three app chips and appends editing")
    func textField() {
        let mode = ContextStripPlan.mode(context: .textField(TextFieldContext(kind: .secure)), hasFrontApp: true, widthClass: .compact)
        #expect(mode == .app(chipLimit: 3, editing: .secure))
    }

    @Test("No front app is idle; the free plan shows media keys")
    func idleAndFree() {
        #expect(ContextStripPlan.mode(context: .none, hasFrontApp: false, widthClass: .compact) == .idle)
        #expect(ContextStripPlan.mode(context: dialog([save]), hasFrontApp: true, widthClass: .compact, allowsAppChips: false) == .free)
    }

    @Test("The strip's spoken label names the app or the dialog")
    func labels() {
        #expect(ContextStripPlan.accessibilityLabel(mode: .app(chipLimit: 6, editing: nil), appName: "Xcode") == "Actions for Xcode")
        #expect(ContextStripPlan.accessibilityLabel(mode: .dialog(title: "Save changes?", message: nil, buttons: []), appName: "Xcode") == "Dialog: Save changes?")
        #expect(ContextStripPlan.accessibilityLabel(mode: .idle, appName: nil) == "Actions")
    }
}

@Suite("Chord text")
struct ChordTextTests {
    @Test("Modifiers in the Mac's order, then the key")
    func order() {
        #expect(ChordText.glyphs(["cmd", "shift", "z"]) == "⇧⌘Z")
        #expect(ChordText.glyphs(["shift", "ctrl", "option", "cmd", "p"]) == "⌃⌥⇧⌘P")
    }

    @Test("Named keys use their symbols")
    func named() {
        #expect(ChordText.glyphs(["return"]) == "↩")
        #expect(ChordText.glyphs(["delete"]) == "⌫")
        #expect(ChordText.glyphs(["escape"]) == "esc")
        #expect(ChordText.glyphs(["left"]) == "←")
    }
}

@Suite("Version line")
struct VersionLineTests {
    @Test("Drawn and spoken forms")
    func forms() {
        #expect(VersionLine.text(version: "1.1", build: "52") == "PIXEL HAND 1.1 - 52")
        #expect(VersionLine.spoken(version: "1.1", build: "52") == "Pixel Hand version 1.1, build 52")
        #expect(VersionLine.text(version: nil, build: nil) == "PIXEL HAND")
    }

    @Test("Every drawn character is in the dot-matrix font")
    func drawable() {
        let line = VersionLine.text(version: "1.2b(3)", build: "52_x")
        #expect(line.allSatisfy { DotMatrixFont.pattern(for: $0) != nil })
        #expect(line == "PIXEL HAND 1.2B3 - 52X")
    }

    @Test("Pixel Hand's own Mac panel never becomes the front app (VQ-063)")
    func hostAppIgnored() {
        #expect(!ContextStripPlan.acceptsFrontApp(bundleID: "com.widgetsflow.pixelhand.mac"))
        #expect(ContextStripPlan.acceptsFrontApp(bundleID: "com.apple.Safari"))
        #expect(ContextStripPlan.acceptsFrontApp(bundleID: nil))
    }
}
