//
//  PickerTopBarPlanTests.swift
//  PixelHandCoreTests
//
//  The picker's top bar backdrop (build 24, VQ-102).
//

import Foundation
import PixelHandCore
import Testing

@Suite struct PickerTopBarPlanTests {
    @Test("At rest, or nudged, there is no backdrop; scrolled under the bar, there is")
    func backdrop() {
        #expect(!PickerTopBarPlan.showsBackdrop(contentTop: 0))
        #expect(!PickerTopBarPlan.showsBackdrop(contentTop: -1))
        #expect(!PickerTopBarPlan.showsBackdrop(contentTop: 12)) // pulled down
        #expect(PickerTopBarPlan.showsBackdrop(contentTop: -3))
        #expect(PickerTopBarPlan.showsBackdrop(contentTop: -400))
    }

    @Test("The opaque part reaches just under the buttons, then fades")
    func extent() {
        #expect(PickerTopBarPlan.opaqueBottom(buttonRowBottom: 106) == 114)
        #expect(PickerTopBarPlan.opaqueBottom(buttonRowBottom: -20) == 0)
        #expect(PickerTopBarPlan.fadeHeight > 0)
    }
}
