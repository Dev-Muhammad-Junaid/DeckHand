//
//  AppIconPolicyTests.swift
//  PixelHandCoreTests
//
//  Owner testing, build 24: dock icons with transparency (OT-1) and the
//  right column's handle contrast (OT-4).
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("App icons keep their transparency (OT-1)")
struct AppIconPolicyTests {
    @Test("Icons render at 2× the dock's icon size")
    func size() {
        #expect(AppIconPolicy.pixelSide == Int(AppIconPolicy.dockIconSide * 2))
        #expect(AppIconPolicy.pixelSide == 72)
        #expect(AppIconPolicy.fallbackPixelSide < AppIconPolicy.pixelSide)
    }

    @Test("The smallest encode with alpha wins; one without alpha never does")
    func choose() {
        let png = AppIconPolicy.Encoded(format: .png, byteCount: 9_000, keepsAlpha: true)
        let heic = AppIconPolicy.Encoded(format: .heic, byteCount: 4_000, keepsAlpha: true)
        let flatHEIC = AppIconPolicy.Encoded(format: .heic, byteCount: 2_000, keepsAlpha: false)
        #expect(AppIconPolicy.choose([png, heic]) == heic)
        #expect(AppIconPolicy.choose([png, flatHEIC]) == png)
        #expect(AppIconPolicy.choose([flatHEIC]) == nil)
        #expect(AppIconPolicy.choose([]) == nil)
        let emptyPNG = AppIconPolicy.Encoded(format: .png, byteCount: 0, keepsAlpha: true)
        #expect(AppIconPolicy.choose([emptyPNG]) == nil)
    }

    @Test("A tie goes to PNG, the format every iOS decodes")
    func tie() {
        let png = AppIconPolicy.Encoded(format: .png, byteCount: 5_000, keepsAlpha: true)
        let heic = AppIconPolicy.Encoded(format: .heic, byteCount: 5_000, keepsAlpha: true)
        #expect(AppIconPolicy.choose([heic, png]) == png)
    }

    @Test("About 500 apps stay within the list budget")
    func budget() {
        // Worst case: every icon at its per-icon cap until the budget is
        // spent, then the fallback size (≈ a quarter of the bytes).
        var used = 0
        for index in 0..<500 {
            let side = AppIconPolicy.pixelSide(usedBytes: used, isRunning: index < 12)
            used += side == AppIconPolicy.pixelSide
                ? AppIconPolicy.maximumBytesPerIcon
                : AppIconPolicy.maximumBytesPerIcon / 4
        }
        #expect(used < 8 * 1024 * 1024)
        #expect(AppIconPolicy.fitsBudget(.init(format: .png, byteCount: AppIconPolicy.maximumBytesPerIcon, keepsAlpha: true)))
        #expect(!AppIconPolicy.fitsBudget(.init(format: .png, byteCount: AppIconPolicy.maximumBytesPerIcon + 1, keepsAlpha: true)))
    }

    @Test("Running apps always get the full size; others drop to the fallback past the budget")
    func running() {
        #expect(AppIconPolicy.pixelSide(usedBytes: AppIconPolicy.listByteBudget + 1, isRunning: true) == AppIconPolicy.pixelSide)
        #expect(AppIconPolicy.pixelSide(usedBytes: AppIconPolicy.listByteBudget + 1, isRunning: false) == AppIconPolicy.fallbackPixelSide)
        #expect(AppIconPolicy.pixelSide(usedBytes: 0, isRunning: false) == AppIconPolicy.pixelSide)
    }

    @Test("The front-app dot sits on the 4 pt grid under a 36 pt icon")
    func dot() {
        #expect(AppIconPolicy.frontDotSide == 4)
        #expect(AppIconPolicy.frontDotGap.truncatingRemainder(dividingBy: 4) == 0)
        #expect(AppIconPolicy.dockIconSide + AppIconPolicy.frontDotGap + AppIconPolicy.frontDotSide <= 56)
        #expect(AppIconPolicy.pressedScale < 1 && AppIconPolicy.pressedScale >= 0.85)
    }
}

@Suite("Right column handle contrast (OT-4)")
struct RightColumnHandleContrastTests {
    @Test("The handle's edge and chevron reach 3:1 in light, dark and high contrast")
    func contrast() {
        #expect(!ContrastAudit.rightColumnHandle.isEmpty)
        for pair in ContrastAudit.rightColumnHandle {
            #expect(pair.appearances.count == 4, "\(pair.name)")
            #expect(pair.worstRatio >= 3, "\(pair.name): \(pair.worstRatio)")
        }
        // In the audit every token change runs through.
        for pair in ContrastAudit.rightColumnHandle {
            #expect(ContrastAudit.all.contains(pair))
        }
    }

    @Test("Build 24's handle (raised on the canvas) was under 3:1: the bug")
    func oldHandle() {
        let old = ContrastPair("raised on canvas", .token(PaletteTokens.raised), on: .token(PaletteTokens.canvas), use: .nonText)
        #expect(old.worstRatio < 3)
    }

    @Test("The handle keeps a 44 pt target and a chevron glyph")
    func target() {
        #expect(RightColumnPlan.handleHitWidth >= 44)
        #expect(RightColumnPlan.handleHeight >= 44)
        #expect(PixelGlyphs.chevronLeft.accent != nil)
        #expect(PixelGlyphs.layout.contains(PixelGlyphs.chevronLeft))
    }
}
