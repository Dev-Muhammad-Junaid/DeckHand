//
//  MirrorToolbarPlanTests.swift
//  PixelHandCoreTests
//
//  Build 23: VQ-060 (no PiP button on iPhone) and VQ-061 (the iPhone
//  toolbar never hid).
//

import Testing
@testable import PixelHandCore

@Suite("MirrorToolbarPlan: PiP button and auto-hide on every device")
struct MirrorToolbarPlanTests {
    @Test("Phones always show the PiP button; iPads only when PiP is supported")
    func pipButton() {
        #expect(MirrorToolbarPlan.pipButton(systemSupportsPiP: true, isPhone: true) == .available)
        #expect(MirrorToolbarPlan.pipButton(systemSupportsPiP: true, isPhone: false) == .available)
        #expect(MirrorToolbarPlan.pipButton(systemSupportsPiP: false, isPhone: true) == .explainsUnavailable)
        #expect(MirrorToolbarPlan.pipButton(systemSupportsPiP: false, isPhone: false) == .hidden)
    }

    @Test("Build 23: the first frame arriving after the pane appears restarts the timer, which then hides")
    func firstFrameLate() {
        let appeared = MirrorToolbarPlan.HideKey(touches: 0, hasPicture: false, isPickerPresented: false, voiceOverOn: false)
        #expect(!MirrorToolbarPlan.mayHide(appeared))
        let framed = MirrorToolbarPlan.HideKey(touches: 0, hasPicture: true, isPickerPresented: false, voiceOverOn: false)
        #expect(framed != appeared) // a new key restarts the timer
        #expect(MirrorToolbarPlan.mayHide(framed))
    }

    @Test("A sheet or VoiceOver holds the toolbar up; it hides again once they end")
    func holds() {
        let picker = MirrorToolbarPlan.HideKey(touches: 2, hasPicture: true, isPickerPresented: true, voiceOverOn: false)
        #expect(!MirrorToolbarPlan.mayHide(picker))
        var closed = picker
        closed.isPickerPresented = false
        #expect(closed != picker)
        #expect(MirrorToolbarPlan.mayHide(closed))
        let voiceOver = MirrorToolbarPlan.HideKey(touches: 2, hasPicture: true, isPickerPresented: false, voiceOverOn: true)
        #expect(!MirrorToolbarPlan.mayHide(voiceOver))
        #expect(MirrorToolbarPlan.hideDelay == 3)
    }
}
