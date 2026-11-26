//
//  TypedKeyTests.swift
//  PixelHandCoreTests
//
//  OT-8 (owner testing, build 25): deck keys type text. The owner's plan
//  "Open Safari · Type “youtube” · Press ⏎" ran from Ask but Save as key
//  refused it; now any plan Ask can run saves, and the key asks first.
//

import Foundation
import Testing
@testable import PixelHandCore

private let safari = "com.apple.Safari"

/// The owner's plan, as Ask builds it.
private let ownersPlan = AskPlan(
    request: "open safari and type youtube and press return",
    steps: [
        .action(.launchApp(bundleID: safari)),
        .typeText("youtube"),
        .action(.shortcut(keys: ["return"])),
    ],
    source: .parser
)

@Suite("Typed text on keys (OT-8)")
struct TypedKeyTests {
    @Test("typeText round-trips through JSON, alone and in a sequence")
    func roundTrip() throws {
        let actions: [Action] = [
            .typeText(text: "youtube"),
            .typeText(text: "Hello, “world” ✓\n"),
            .sequence(steps: [
                .run(action: .launchApp(bundleID: safari)),
                .delay(milliseconds: 300),
                .run(action: .typeText(text: "youtube")),
                .run(action: .shortcut(keys: ["return"])),
            ]),
        ]
        for action in actions {
            let data = try JSONEncoder().encode(action)
            #expect(try JSONDecoder().decode(Action.self, from: data) == action)
        }
        let json = String(decoding: try JSONEncoder().encode(Action.typeText(text: "hi")), as: UTF8.self)
        #expect(json == #"{"typeText":{"text":"hi"}}"#)
    }

    @Test("A deck holding a typing key round-trips and validates")
    func deckRoundTrip() throws {
        var deck = DeckDocument.empty
        let saved = deck.saveAskPlan(ownersPlan, appName: { $0 == safari ? "Safari" : nil })
        let result = try #require(saved)
        let data = try JSONEncoder().encode(deck)
        let back = try JSONDecoder().decode(DeckDocument.self, from: data)
        #expect(back == deck)
        #expect(DeckValidation.issues(in: back).isEmpty)
        let key = try #require(back.page(id: result.pageID)?.keys.first { $0.id == result.keyID })
        #expect(key.action.typesText)
    }

    @Test("The owner's plan saves as a key: open, type, Return, in order")
    func ownersPlanSaves() throws {
        #expect(ownersPlan.canRun)
        #expect(ownersPlan.saveBlocker == nil)
        #expect(ownersPlan.savedAction == .sequence(steps: [
            .run(action: .launchApp(bundleID: safari)),
            .run(action: .typeText(text: "youtube")),
            .run(action: .shortcut(keys: ["return"])),
        ]))
        var deck = DeckDocument.empty
        let saved = deck.saveAskPlan(ownersPlan, label: "YouTube")
        let result = try #require(saved)
        // Two apps' worth of steps (it opens one, then types): Home.
        #expect(result.pageID == DeckPage.homeID)
        let key = try #require(deck.page(id: DeckPage.homeID)?.keys.first)
        #expect(key.label == "YouTube")
        #expect(key.confirm)
        #expect(key.asksFirst)
        #expect(key.action.pressesReturn)
    }

    @Test("Pauses and typed steps keep their places in the saved sequence")
    func keepsOrder() {
        let plan = AskPlan(request: "x", steps: [
            .typeText("a"), .delay(milliseconds: 500), .typeText("b\n"), .action(.media(key: .next)),
        ], source: .edited)
        #expect(plan.savedAction == .sequence(steps: [
            .run(action: .typeText(text: "a")),
            .delay(milliseconds: 500),
            .run(action: .typeText(text: "b\n")),
            .run(action: .media(key: .next)),
        ]))
    }

    @Test("A lone typed step saves as a typeText key, normalized like the Mac types it")
    func loneStep() throws {
        let plan = AskPlan(request: "type hello", steps: [.typeText("hello\r\n")], source: .parser)
        #expect(plan.savedAction == .typeText(text: "hello\n"))
        let key = try #require(plan.deckKey())
        #expect(key.asksFirst)
        #expect(DeckValidation.keyIssues(key).isEmpty)
    }

    @Test("A typed step the Mac couldn't type says which step and why, next to it")
    func unsavableStep() {
        // Runs (Ask's own check only bounds the length), but cleaning drops
        // every character, so the key would type nothing.
        let plan = AskPlan(request: "x", steps: [.action(.media(key: .next)), .typeText("\u{1B}")], source: .edited)
        #expect(plan.canRun)
        #expect(plan.saveBlocker == .step(index: 1, reason: ActionValidation.Issue.emptyText.message))
        #expect(plan.saveBlocker?.stepIndex == 1)
        #expect(plan.saveBlocker?.message.hasPrefix("Step 2 can’t be saved on a key: ") == true)
        #expect(plan.savedAction == nil)
        #expect(AskPlanValidation.saveReason(for: .typeText("ok")) == nil)
    }

    @Test("The old refusal is gone")
    func noRefusal() {
        let blockers: [AskPlanValidation.SaveBlocker] = [.cannotRun, .step(index: 0, reason: "r")]
        for blocker in blockers {
            #expect(!blocker.message.contains("can’t type text yet"))
        }
    }

    @Test("Validation: not blank, at most 4 KB, only Return and Tab as control characters")
    func validation() {
        #expect(ActionValidation.isValid(.typeText(text: "youtube"), storable: true))
        #expect(ActionValidation.isValid(.typeText(text: "\n"), storable: true))
        #expect(ActionValidation.isValid(.typeText(text: "a\tb\nc"), storable: true))
        #expect(ActionValidation.issues(in: .typeText(text: ""), storable: true) == [.emptyText])
        #expect(ActionValidation.issues(in: .typeText(text: "   "), storable: true) == [.emptyText])
        #expect(ActionValidation.issues(in: .typeText(text: String(repeating: "x", count: 4_097)), storable: true) == [.textTooLong])
        #expect(ActionValidation.issues(in: .typeText(text: "a\u{1B}b"), storable: true) == [.badText])
        #expect(ActionValidation.issues(in: .typeText(text: "a\r\nb"), storable: true) == [.badText])
        for issue in [ActionValidation.Issue.emptyText, .textTooLong, .badText] {
            #expect(!issue.message.isEmpty)
        }
    }

    @Test("The Mac accepts a valid typing run and drops a bad one whole")
    func remoteValidation() {
        let good = ControlMessage.deck(.run(requestID: "r", action: .typeText(text: "hi\n")))
        #expect(RemoteInputValidation.sanitize(good) == good)
        let bad = ControlMessage.deck(.run(requestID: "r", action: .typeText(text: "hi\u{7}")))
        #expect(RemoteInputValidation.sanitize(bad) == nil)
        let sequence = ControlMessage.deck(.run(requestID: "r", action: ownersPlan.savedAction!))
        #expect(RemoteInputValidation.sanitize(sequence) == sequence)
        let badStep = ControlMessage.deck(.run(requestID: "r", action: .sequence(steps: [
            .run(action: .launchApp(bundleID: safari)), .run(action: .typeText(text: "")),
        ])))
        #expect(RemoteInputValidation.sanitize(badStep) == nil)
    }

    @Test("Locked: typing follows input.typeText")
    func lock() {
        let typing = Action.typeText(text: "hi")
        for state in MacLockState.allCases {
            let expected = LockPolicy.decide(.input(.typeText(text: "hi")), state: state) == .allow
            #expect(LockPolicy.allows(typing, state: state) == expected, "\(state)")
        }
        #expect(LockPolicy.allows(ownersPlan.savedAction!, state: .unlocked))
    }

    @Test("Keys that type always ask first; the inspector says why")
    func asksFirst() {
        var key = DeckKey(id: "k", label: "Hi", action: .typeText(text: "hi"))
        #expect(!key.confirm)
        #expect(key.asksFirst)
        #expect(key.asksFirstLockReason != nil)
        key.action = .media(key: .next)
        #expect(!key.asksFirst)
        #expect(key.asksFirstLockReason == nil)
        key.confirm = true
        #expect(key.asksFirst)
        #expect(AskSafety.reason(for: .typeText(text: "x")) == .typesText)
        #expect(AskSafety.reason(for: ownersPlan.savedAction!) == .typesText)
    }

    @Test("Returns: typed line breaks, a Return chord, or either inside a sequence")
    func pressesReturn() {
        #expect(Action.typeText(text: "a\n").pressesReturn)
        #expect(!Action.typeText(text: "a").pressesReturn)
        #expect(Action.shortcut(keys: ["return"]).pressesReturn)
        #expect(!Action.shortcut(keys: ["cmd", "return", "x"]).pressesReturn)
        #expect(Action.sequence(steps: [.run(action: .typeText(text: "a\n"))]).pressesReturn)
    }

    @Test("It reads sensibly: the inspector, the key's face, the label, widgets")
    func presentation() {
        let action = Action.typeText(text: "youtube\n")
        #expect(action.summary() == "Type “youtube” then Return")
        #expect(action.chordText == "“youtube” ⏎")
        #expect(Action.typeText(text: "a much longer piece of text").chordText == "“a much long…”")
        #expect(Action.typeText(text: "\n").chordText == "⏎")
        #expect(DeckGlyphs.glyph(for: action) == PixelGlyphs.type)
        #expect(DeckKey.draft(for: action).label == "youtube")
        #expect(DeckKey.draft(for: .typeText(text: "\n")).label == "Return")
        #expect(WidgetGlyph.resolve(nil, action: action, label: "YouTube") == .pixel(name: "type"))
        #expect(action.kindName == "typeText")
        #expect(action.message == .input(.typeText(text: "youtube\n")))
        #expect(action.needsAccessibility)
    }

    @Test("The key editor offers Type text, with a valid starting text")
    func library() {
        #expect(ActionKind.allCases.contains(.typeText))
        #expect(ActionKind(.typeText(text: "x")) == .typeText)
        let template = ActionKind.typeText.template(frontBundleID: nil)
        #expect(ActionValidation.isValid(template, storable: true))
        #expect(PixelGlyphs.named(ActionKind.typeText.glyphName) != nil)
        #expect(Action.launchApp(bundleID: safari).converted(to: .typeText, frontBundleID: nil) == template)
    }

    @Test("Widgets leave typing keys out (they can't ask); Shortcuts lists them and asks")
    func widgets() {
        var deck = DeckDocument.empty
        _ = deck.saveAskPlan(ownersPlan)
        let snapshot = WidgetDeckSnapshot.make(from: deck, macs: [], isPro: true, now: Date())
        let listed = snapshot.allKeys.first { $0.label == ownersPlan.keyLabel() }
        #expect(listed?.confirm == true)
        #expect(!snapshot.widgetKeys.contains { $0.label == ownersPlan.keyLabel() })
    }
}
