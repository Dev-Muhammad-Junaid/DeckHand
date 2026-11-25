//
//  TypingTargetGuardTests.swift
//  PixelHandCoreTests
//

import PixelHandCore
import Testing

@Suite("Typing target (VQ-036)")
struct TypingTargetGuardTests {
    @Test("Return asks only after the front app changed from the one typed into")
    func confirmsOnChange() {
        var guardrail = TypingTargetGuard()
        #expect(!guardrail.shouldConfirmReturn(frontApp: "Notes")) // nothing typed yet
        guardrail.typed(into: "Notes")
        #expect(!guardrail.shouldConfirmReturn(frontApp: "Notes"))
        #expect(guardrail.shouldConfirmReturn(frontApp: "Messages"))
        guardrail.confirmed("Messages")
        #expect(!guardrail.shouldConfirmReturn(frontApp: "Messages"))
        #expect(!guardrail.shouldConfirmReturn(frontApp: nil)) // unknown: don't nag
    }

    @Test("Empty or unknown apps don't count as typed into")
    func ignoresUnknown() {
        var guardrail = TypingTargetGuard()
        guardrail.typed(into: nil)
        guardrail.typed(into: "")
        #expect(guardrail.acknowledgedApp == nil)
    }

    @Test("The caption names the app")
    func caption() {
        #expect(TypingTargetGuard.caption(frontApp: "Safari") == "Typing into Safari")
        #expect(TypingTargetGuard.caption(frontApp: nil) == "Typing goes to the app in front on the Mac")
    }
}
