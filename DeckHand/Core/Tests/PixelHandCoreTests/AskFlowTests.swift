//
//  AskFlowTests.swift
//  PixelHandCoreTests
//
//  Owner testing, build 24, OT-5: Ask got stuck after one use. Every stage
//  keeps a way back and the request field.
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("Ask flow (OT-5)")
struct AskFlowTests {
    /// Ask, plan, run to the end.
    private func ranOnce() -> AskFlow {
        var flow = AskFlow()
        flow.apply(.submit("Open Safari"))
        flow.apply(.planReady)
        flow.apply(.runStarted)
        flow.apply(.stepStarted(1))
        flow.apply(.runEnded(succeeded: true))
        return flow
    }

    @Test("Ask → plan → run → result offers New request, Run again, Save as key and Edit")
    func afterRun() {
        let flow = ranOnce()
        #expect(flow.stage == .result(succeeded: true))
        #expect(flow.actions == [.newRequest, .runAgain, .saveAsKey, .edit])
        #expect(flow.canSubmitRequest)
        #expect(flow.showsPlan)
    }

    @Test("The owner's walk: ask, run, new request, save as key, cancel, ask again")
    func ownerWalk() {
        var flow = ranOnce()
        let resets = flow.fieldResetRequest
        flow.apply(.newRequest)
        #expect(flow.stage == .request)
        #expect(flow.fieldResetRequest == resets + 1)
        flow.apply(.submit("Take a screenshot"))
        flow.apply(.planReady)
        flow.apply(.saveAsKey(suggestedName: "Screenshot"))
        #expect(flow.namingName == "Screenshot")
        #expect(flow.actions == [.save, .cancel])
        flow.apply(.cancelNaming)
        #expect(flow.stage == .plan)
        flow.apply(.submit("Show Mission Control"))
        #expect(flow.stage == .planning)
        flow.apply(.planReady)
        #expect(flow.stage == .plan)
        #expect(flow.recent == ["Show Mission Control", "Take a screenshot", "Open Safari"])
    }

    @Test("Save as key from the result: name, save, back to the result with a note")
    func saveFromResult() {
        var flow = ranOnce()
        flow.apply(.saveAsKey(suggestedName: "Safari"))
        flow.apply(.rename("  "))
        #expect(!flow.canSaveName)
        flow.apply(.rename("Browse"))
        #expect(flow.canSaveName)
        flow.apply(.saved(note: "Saved as a key on Home."))
        #expect(flow.stage == .result(succeeded: true))
        #expect(flow.note == "Saved as a key on Home.")
        #expect(flow.actions.contains(.newRequest))
    }

    @Test("A failed save keeps the name field with the reason; Cancel still goes back")
    func saveFails() {
        var flow = AskFlow()
        flow.apply(.submit("next song"))
        flow.apply(.planReady)
        flow.apply(.saveAsKey(suggestedName: "Next"))
        flow.apply(.saveFailed("The deck is full."))
        #expect(flow.namingName == "Next")
        #expect(flow.note == "The deck is full.")
        flow.apply(.cancelNaming)
        #expect(flow.stage == .plan)
        #expect(flow.note == nil)
    }

    @Test("Edit returns to the plan; Done leaves editing")
    func edit() {
        var flow = ranOnce()
        flow.apply(.edit)
        #expect(flow.isEditing)
        #expect(flow.actions == [.doneEditing])
        flow.apply(.doneEditing)
        #expect(flow.stage == .plan)
        #expect(flow.actions == [.run, .saveAsKey, .edit, .newRequest])
    }

    @Test("Run again from the result runs; Stop goes back to the plan")
    func runAgainAndStop() {
        var flow = ranOnce()
        flow.apply(.runStarted)
        #expect(flow.isRunning)
        #expect(flow.actions == [.stop])
        flow.apply(.stopped)
        #expect(flow.stage == .plan)
    }

    @Test("A request can start over from every stage but planning")
    func fieldAlwaysThere() {
        var stages: [AskFlow] = []
        var flow = AskFlow()
        stages.append(flow)
        flow.apply(.submit("Open Safari"))
        #expect(!flow.canSubmitRequest)
        flow.apply(.submit("Ignored while planning"))
        #expect(flow.recent == ["Open Safari"])
        flow.apply(.planReady); stages.append(flow)
        flow.apply(.edit); stages.append(flow)
        flow.apply(.doneEditing)
        flow.apply(.runStarted); stages.append(flow)
        flow.apply(.runEnded(succeeded: false)); stages.append(flow)
        flow.apply(.saveAsKey(suggestedName: "x")); stages.append(flow)
        for var stage in stages {
            #expect(stage.canSubmitRequest)
            stage.apply(.submit("Lock the screen"))
            #expect(stage.stage == .planning)
        }
    }

    @Test("Planning can be cancelled back to the request")
    func cancelPlanning() {
        var flow = AskFlow()
        flow.apply(.submit("Open Safari"))
        #expect(flow.actions == [.cancel])
        flow.apply(.cancelPlanning)
        #expect(flow.stage == .request)
    }

    @Test("Late callbacks can't strand the flow")
    func lateEvents() {
        var flow = AskFlow()
        flow.apply(.planReady)
        flow.apply(.runEnded(succeeded: true))
        flow.apply(.stepStarted(2))
        flow.apply(.saved(note: "x"))
        flow.apply(.doneEditing)
        #expect(flow.stage == .request)
        // A run that ended after New request doesn't jump back to a result.
        var ran = ranOnce()
        ran.apply(.runStarted)
        ran.apply(.newRequest)
        ran.apply(.runEnded(succeeded: true))
        #expect(ran.stage == .request)
    }

    @Test("Recent requests: newest first, no repeats (any case), at most five")
    func recent() {
        var flow = AskFlow()
        for request in ["a", "b", "c", "A", "d", "e", "f"] {
            flow.apply(.submit(request))
            flow.apply(.cancelPlanning)
        }
        #expect(flow.recent == ["f", "e", "d", "A", "c"])
        flow.apply(.submit("   "))
        #expect(flow.stage == .request)
        flow.forgetRecent()
        #expect(flow.recent.isEmpty)
        #expect(AskFlow(recent: ["1", "2", "3", "4", "5", "6"]).recent.count == 5)
    }

    @Test("Every action has a title and a ph.ask identifier")
    func actionNames() {
        for action in AskFlow.Action.allCases {
            #expect(!action.title.isEmpty)
            #expect(action.accessibilityID.hasPrefix("ph.ask."))
        }
    }
}

@Suite("Save as key takes the person's name (OT-5)")
struct AskSaveNameTests {
    private let plan = AskPlan(request: "next song", steps: [.action(.media(key: .next))], source: .parser)

    @Test("A given name labels the key; blank keeps the plan's label")
    func label() {
        #expect(plan.deckKey(label: "Skip")?.label == "Skip")
        #expect(plan.deckKey(label: "   ")?.label == plan.keyLabel())
        #expect(plan.deckKey()?.label == plan.keyLabel())
        #expect(plan.suggestedKeyName() == plan.keyLabel())
    }

    @Test("A long name is cut to the deck's label length and still saves")
    func longName() {
        var deck = DeckDocument.empty
        let long = String(repeating: "x", count: DeckValidation.maxLabelLength + 20)
        let result = deck.saveAskPlan(plan, label: long)
        #expect(result != nil)
        let key = deck.page(id: DeckPage.homeID)?.keys.first
        #expect(key?.label.count == DeckValidation.maxLabelLength)
    }
}

@Suite("Ask's field starts a new request after a plan (build 25 bug 2)")
struct AskFieldSelectionTests {
    @Test("After a plan, a result or Save as key › Cancel, focusing the field selects the old request")
    func selects() {
        var flow = AskFlow()
        #expect(!flow.selectsFieldOnFocus)
        flow.apply(.submit("Take a screenshot"))
        #expect(!flow.selectsFieldOnFocus) // planning
        flow.apply(.planReady)
        #expect(flow.selectsFieldOnFocus)
        flow.apply(.saveAsKey(suggestedName: "Screenshot"))
        #expect(flow.selectsFieldOnFocus)
        flow.apply(.cancelNaming)
        #expect(flow.selectsFieldOnFocus) // the owner's case: back on the plan
        flow.apply(.runStarted)
        flow.apply(.runEnded(succeeded: true))
        #expect(flow.selectsFieldOnFocus)
        flow.apply(.newRequest)
        #expect(!flow.selectsFieldOnFocus) // a cleared field: just the caret
    }
}
