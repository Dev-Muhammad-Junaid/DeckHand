//
//  AskPlannerTests.swift
//  PixelHandCoreTests
//
//  Ask (UX-022, A1): the deterministic parser, the on-device plan
//  resolver, plan validation, confirmations and Save as key.
//

import Foundation
@testable import PixelHandCore
import Testing

private let safari = "com.apple.Safari"
private let parser = AskCommandParser(catalog: AskAppCatalog(installed: [
    InstalledAppInfo(bundleID: "com.figma.Desktop", displayName: "Figma", iconData: nil),
    InstalledAppInfo(bundleID: "com.apple.Safari", displayName: "Safari", iconData: nil),
]))

@Suite("Ask parser: the ten example requests")
struct AskParserExampleTests {
    @Test("open Safari and make a new tab → launch Safari, ⌘T in Safari")
    func openSafariNewTab() {
        let plan = parser.plan("Open Safari and make a new tab")
        #expect(plan.steps == [
            .action(.launchApp(bundleID: safari)),
            .action(.appShortcut(bundleID: safari, keys: ["cmd", "t"])),
        ])
        #expect(plan.notes.isEmpty)
        #expect(plan.source == .parser)
    }

    @Test("mute and lock → lock step, a note about volume")
    func muteAndLock() {
        let plan = parser.plan("mute and lock")
        #expect(plan.steps == [.action(.shortcut(keys: ["cmd", "ctrl", "q"]))])
        #expect(plan.notes.count == 1)
        #expect(plan.notes[0].contains("volume"))
        #expect(AskSafety.reasons(in: plan) == [.locks])
    }

    @Test("paste my last screenshot → ⌘V with a clipboard note")
    func pasteScreenshot() {
        let plan = parser.plan("paste my last screenshot")
        #expect(plan.steps == [.action(.shortcut(keys: ["cmd", "v"]))])
        #expect(plan.notes.first?.contains("clipboard") == true)
    }

    @Test("press cmd shift p → the chord")
    func pressChord() {
        #expect(parser.plan("press cmd shift p").steps == [.action(.shortcut(keys: ["cmd", "shift", "p"]))])
        #expect(parser.plan("hit ⌘⇧T").steps == [.action(.shortcut(keys: ["cmd", "shift", "t"]))])
        #expect(parser.plan("press return").steps == [.action(.shortcut(keys: ["return"]))])
        #expect(parser.plan("Control-Command-F").steps == [.action(.shortcut(keys: ["cmd", "ctrl", "f"]))])
    }

    @Test("play and next song → media keys")
    func media() {
        #expect(parser.plan("pause the music").steps == [.action(.media(key: .playPause))])
        #expect(parser.plan("play, then next song").steps == [.action(.media(key: .playPause)), .action(.media(key: .next))])
    }

    @Test("mission control and show desktop → system actions")
    func system() {
        #expect(parser.plan("show mission control then show desktop").steps == [
            .action(.system(action: .missionControl)),
            .action(.system(action: .showDesktop)),
        ])
        #expect(parser.plan("take a screenshot").steps == [.action(.shortcut(keys: ["cmd", "shift", "3"]))])
    }

    @Test("open Figma and type hello and press return")
    func typeThenReturn() {
        let plan = parser.plan("Open Figma and type Hello World and press return")
        #expect(plan.steps == [
            .action(.launchApp(bundleID: "com.figma.Desktop")),
            .typeText("Hello World"),
            .action(.appShortcut(bundleID: "com.figma.Desktop", keys: ["return"])),
        ])
        #expect(AskSafety.reasons(in: plan) == [.typesText])
    }

    @Test("typed text keeps its own 'and' and quoted punctuation")
    func typedTextKeepsAnd() {
        #expect(parser.plan("type salt and pepper").steps == [.typeText("salt and pepper")])
        #expect(parser.plan("write \"a, b and c\" then press return").steps == [
            .typeText("a, b and c"),
            .action(.shortcut(keys: ["return"])),
        ])
    }

    @Test("quit Slack → ⌘Q in Slack, confirmed")
    func quitApp() {
        let plan = parser.plan("quit slack")
        #expect(plan.steps == [.action(.appShortcut(bundleID: "com.tinyspeck.slackmacgap", keys: ["cmd", "q"]))])
        #expect(AskSafety.reasons(in: plan) == [.quits])
    }

    @Test("run the shortcut Morning, wait 2 seconds, go to apple.com")
    func shortcutWaitURL() {
        let plan = parser.plan("run the shortcut Morning Routine, wait 2 seconds, then go to apple.com")
        #expect(plan.steps == [
            .action(.macShortcut(name: "Morning Routine")),
            .delay(milliseconds: 2_000),
            .action(.launchApp(bundleID: safari)),
            .action(.appShortcut(bundleID: safari, keys: ["cmd", "l"])),
            .typeText("apple.com\n"),
        ])
    }

    @Test("a command with 'in <app>' goes to that app")
    func inApp() {
        #expect(parser.plan("reload the page in Safari").steps == [.action(.appShortcut(bundleID: safari, keys: ["cmd", "r"]))])
    }

    @Test("menu path with an app becomes a menu command")
    func menuPath() {
        #expect(parser.plan("choose File > Export > PDF… in Pages").steps == [
            .action(.menuCommand(bundleID: "com.apple.iWork.Pages", path: ["File", "Export", "PDF…"])),
        ])
        let noApp = parser.plan("View > Show Sidebar")
        #expect(noApp.steps.isEmpty)
        #expect(noApp.notes.first?.contains("Name the app") == true)
    }

    @Test("gibberish becomes a note, never a guess")
    func notUnderstood() {
        let plan = parser.plan("fly me to the moon")
        #expect(plan.steps.isEmpty)
        #expect(plan.notes == ["Didn’t understand “fly me to the moon”."])
        #expect(!plan.canRun)
    }

    @Test("every parsed example validates")
    func examplesValidate() {
        for request in ["open safari and make a new tab", "lock the screen", "paste", "press cmd shift p", "next track", "mission control", "type hi", "quit slack", "run the shortcut Focus", "go to apple.com"] {
            let plan = parser.plan(request)
            #expect(plan.canRun, "\(request): \(plan.issues)")
        }
    }
}

@Suite("Ask vocabulary")
struct AskVocabularyTests {
    @Test("chords written many ways resolve to wire names")
    func chords() {
        #expect(ChordParser.parse("Command+T") == ["cmd", "t"])
        #expect(ChordParser.parse("⌘,") == ["cmd", ","])
        #expect(ChordParser.parse("cmd -") == ["cmd", "-"])
        #expect(ChordParser.parse("option shift page down") == ["shift", "option", "pagedown"])
        #expect(ChordParser.parse("cmd t w") == nil)
        #expect(ChordParser.parse("cmd banana") == nil)
        #expect(ChordParser.parse("cmd") == nil)
    }

    @Test("apps by installed name, alias and prefix")
    func apps() {
        let catalog = AskAppCatalog(installed: [InstalledAppInfo(bundleID: "com.example.Thing", displayName: "Thing Pro", iconData: nil)])
        #expect(catalog.app(named: "Thing")?.bundleID == "com.example.Thing")
        #expect(catalog.app(named: "chrome")?.bundleID == "com.google.Chrome")
        #expect(catalog.app(named: "VS Code")?.bundleID == "com.microsoft.VSCode")
        #expect(catalog.app(named: "the Safari app")?.bundleID == safari)
        #expect(catalog.app(named: "xy") == nil)
        #expect(catalog.app(named: "a new tab") == nil)
    }
}

@Suite("Ask on-device plans are resolved and validated")
struct AskResolverTests {
    let catalog = AskAppCatalog()

    @Test("model steps become real actions, context app carries")
    func resolves() {
        let plan = AskPlanResolver.resolve([
            AskDraftStep(kind: "openApp", app: "Safari"),
            AskDraftStep(kind: "shortcut", keys: "Command+T"),
            AskDraftStep(kind: "typeText", text: "news"),
            AskDraftStep(kind: "media", text: "next track"),
        ], request: "x", catalog: catalog)
        #expect(plan.steps == [
            .action(.launchApp(bundleID: safari)),
            .action(.appShortcut(bundleID: safari, keys: ["cmd", "t"])),
            .typeText("news"),
            .action(.media(key: .next)),
        ])
        #expect(plan.source == .onDevice)
        #expect(plan.notes.isEmpty)
    }

    @Test("invented apps, fake chords and unknown kinds are dropped with notes")
    func dropsBadSteps() {
        let plan = AskPlanResolver.resolve([
            AskDraftStep(kind: "openApp", app: "Zzyzx Studio"),
            AskDraftStep(kind: "shortcut", keys: "hyper+banana"),
            AskDraftStep(kind: "deleteAllFiles"),
            AskDraftStep(kind: "menu", menuPath: ["File", "Export"]),
            AskDraftStep(kind: "system", text: "lock screen"),
        ], request: "x", catalog: catalog)
        #expect(plan.steps == [.action(.shortcut(keys: ["cmd", "ctrl", "q"]))])
        #expect(plan.notes.count == 4)
    }

    @Test("a huge wait is clamped, a bad shortcut name refused")
    func clamps() {
        let plan = AskPlanResolver.resolve([
            AskDraftStep(kind: "wait", seconds: 999),
            AskDraftStep(kind: "runShortcut", text: "-rm"),
        ], request: "x", catalog: catalog)
        #expect(plan.steps == [.delay(milliseconds: ActionLimits.maxDelayMilliseconds)])
        #expect(plan.notes.count == 1)
    }
}

@Suite("Ask plans: validation, safety, editing and Save as key")
struct AskPlanTests {
    @Test("validation refuses dialog presses, sequences, long text and long waits")
    func validation() {
        let plan = AskPlan(request: "", steps: [
            .action(.contextAction(id: "ok")),
            .action(.sequence(steps: [.delay(milliseconds: 1)])),
            .typeText(String(repeating: "a", count: AskPlanValidation.maxTextBytes + 1)),
            .delay(milliseconds: 20_000),
            .action(.launchApp(bundleID: "bad id!")),
        ], source: .edited)
        let issues = plan.issues
        #expect(issues.contains(.dialogPress(index: 0)))
        #expect(issues.contains(.nestedSequence(index: 1)))
        #expect(issues.contains(.badText(index: 2)))
        #expect(issues.contains(.badDelay(index: 3)))
        #expect(issues.contains(.badAction(index: 4, .badBundleID)))
        #expect(AskPlan(request: "", steps: [], source: .parser).issues == [.empty])
        let tooMany = AskPlan(request: "", steps: Array(repeating: .action(.media(key: .next)), count: 21), source: .parser)
        #expect(tooMany.issues.contains(.tooManySteps))
    }

    @Test("confirmation reasons for destructive chords, menus and Shortcuts")
    func safety() {
        #expect(AskSafety.reason(for: .shortcut(keys: ["cmd", "w"])) == .closes)
        #expect(AskSafety.reason(for: .shortcut(keys: ["cmd", "option", "escape"])) == .forceQuit)
        #expect(AskSafety.reason(for: .shortcut(keys: ["cmd", "shift", "q"])) == .logsOut)
        #expect(AskSafety.reason(for: .shortcut(keys: ["cmd", "delete"])) == .deletes)
        #expect(AskSafety.reason(for: .menuCommand(bundleID: "com.apple.finder", path: ["Finder", "Empty Trash…"])) == .deletes)
        #expect(AskSafety.reason(for: .macShortcut(name: "x")) == .runsShortcut)
        #expect(AskSafety.reason(for: .shortcut(keys: ["cmd", "t"])) == nil)
        #expect(AskSafety.reason(for: .launchApp(bundleID: safari)) == nil)
        #expect(AskSafety.confirmationMessage(for: [.quits, .typesText], macName: "Studio") == "This plan quits an app and types on Studio.")
    }

    @Test("Save as key: one action alone, several as a sequence, typing blocks")
    func save() {
        let one = AskPlan(request: "next", steps: [.action(.media(key: .next))], source: .parser)
        #expect(one.savedAction == .media(key: .next))
        #expect(one.keyLabel() == "Next Track")

        let two = parser.plan("open safari and make a new tab")
        #expect(two.savedAction == .sequence(steps: [
            .run(action: .launchApp(bundleID: safari)),
            .run(action: .appShortcut(bundleID: safari, keys: ["cmd", "t"])),
        ]))
        #expect(two.keyLabel() == "Open safari and make a new tab")
        if let action = two.savedAction { #expect(ActionValidation.isValid(action, storable: true)) }

        let typing = parser.plan("type hi")
        #expect(typing.saveBlocker == .typesText)
        #expect(typing.savedAction == nil)
    }

    @Test("editing removes, moves, replaces and marks the plan edited")
    func editing() {
        var plan = parser.plan("play, next song, show desktop")
        plan.move(from: 0, by: 1)
        #expect(plan.steps.first == .action(.media(key: .next)))
        plan.remove(at: 2)
        #expect(plan.steps.count == 2)
        plan.replace(at: 0, with: .delay(milliseconds: 500))
        #expect(plan.steps.first == .delay(milliseconds: 500))
        plan.move(from: 1, by: 1)
        #expect(plan.steps.count == 2)
        #expect(plan.source == .edited)
    }

    @Test("step summaries read plainly")
    func summaries() {
        #expect(AskStep.typeText("hello").summary() == "Type “hello”")
        // VQ-049: Return never breaks the quote across lines.
        #expect(AskStep.typeText("apple.com\n").summary() == "Type “apple.com” then Return")
        #expect(AskStep.typeText("a\nb").summary() == "Type “a ↩ b”")
        #expect(AskStep.typeText("\n").summary() == "Press Return")
        #expect(!AskStep.typeText("x\r\n").summary().contains("\n"))
        #expect(AskStep.delay(milliseconds: 1_500).summary() == "Wait 1.5 s")
        #expect(AskStep.delay(milliseconds: 2_000).summary() == "Wait 2 s")
        #expect(AskStep.action(.launchApp(bundleID: safari)).summary { $0 == safari ? "Safari" : nil } == "Open Safari")
    }

    @Test("a plan round-trips through JSON")
    func coding() throws {
        let plan = parser.plan("open safari, type hi, wait 1 second")
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(AskPlan.self, from: data) == plan)
    }
}

@Suite("Ask Save as key lands on the right page")
struct AskSaveTests {
    @Test("a one-app plan goes on that app's page, created if missing")
    func appPage() {
        var deck = DeckDocument.empty
        let plan = parser.plan("reload the page in Safari, then zoom in in Safari")
        let result = deck.saveAskPlan(plan) { $0 == safari ? "Safari" : nil }
        #expect(result?.pageID == DeckPage.appPageID(for: safari))
        #expect(deck.appPage(for: safari)?.title == "Safari")
        #expect(deck.appPage(for: safari)?.keys.first?.action == plan.savedAction)
    }

    @Test("a mixed plan goes on Home; a destructive one asks before running")
    func home() {
        var deck = DeckDocument.empty
        let result = deck.saveAskPlan(parser.plan("open safari and close the tab"))
        #expect(result?.pageID == DeckPage.homeID)
        let key = deck.page(id: DeckPage.homeID)?.keys.first
        #expect(key?.confirm == true)
        #expect(key.map { DeckValidation.keyIssues($0).isEmpty } == true)
    }

    @Test("a typing plan isn't saved; a full deck refuses")
    func refuses() {
        var deck = DeckDocument.empty
        #expect(deck.saveAskPlan(parser.plan("type hello")) == nil)
        deck.pages[0].keys = (0..<DeckValidation.maxKeysPerPage).map { DeckKey(id: "k\($0)", label: "K", action: .media(key: .next)) }
        #expect(deck.saveAskPlan(parser.plan("next song")) == nil)
    }
}
