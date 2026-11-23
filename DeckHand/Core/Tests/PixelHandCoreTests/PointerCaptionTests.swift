//
//  PointerCaptionTests.swift
//  PixelHandCoreTests
//
//  The Pointer surface's dot-matrix caption and click-strip rule (UX-004).
//

import Testing
@testable import PixelHandCore

@Suite("Pointer caption")
struct PointerCaptionTests {
    static let everyActivity: [PointerActivity] = [
        .idle(scrollMode: false), .idle(scrollMode: true),
        .cursor, .scroll, .dragArmed, .dragging, .dragLocked, .pencilHover,
    ] + MultiFingerGesture.Direction.allCases.map { .system(.swipe($0)) }
        + [.system(.pinch), .system(.spread)]

    @Test("Every caption draws in the dot-matrix font, uppercase and short")
    func captionsRenderInDotMatrix() {
        for activity in Self.everyActivity {
            let caption = PointerCaption.caption(for: activity)
            #expect(!caption.text.isEmpty)
            #expect(caption.text == caption.text.uppercased())
            #expect(caption.text.count <= PointerCaption.maxLength, "\(caption.text)")
            for character in caption.text {
                #expect(DotMatrixFont.characters.contains(character), "\(character) in \(caption.text)")
            }
            #expect(!caption.spoken.isEmpty)
        }
    }

    @Test("At rest the caption teaches two-finger scrolling and isn't lit")
    func restingCaption() {
        let rest = PointerCaption.caption(for: .idle(scrollMode: false))
        #expect(rest.text == "2 FINGERS · SCROLL")
        #expect(!rest.isActive)
        let scrollMode = PointerCaption.caption(for: .idle(scrollMode: true))
        #expect(scrollMode.text == "1 FINGER · SCROLL")
        #expect(!scrollMode.isActive)
    }

    @Test("Working captions light up and name the Mac view")
    func activeCaptions() {
        for activity in Self.everyActivity {
            if case .idle = activity { continue }
            #expect(PointerCaption.caption(for: activity).isActive)
        }
        #expect(PointerCaption.caption(for: .system(.swipe(.up))).text == "MISSION CONTROL")
        #expect(PointerCaption.caption(for: .dragLocked).glyph == PixelGlyphs.lock)
    }

    @Test("Space captions follow the gesture map's natural direction")
    func spaceDirections() {
        // Fingers left bring the Space on the right (GestureMap).
        #expect(GestureMap.command(for: .swipe(.left)) == .switchSpace(.next))
        #expect(PointerCaption.caption(for: .system(.swipe(.left))).text == "NEXT SPACE")
        #expect(PointerCaption.caption(for: .system(.swipe(.right))).text == "PREVIOUS SPACE")
    }

    @Test("The click strip follows the setting and hides on a short pad")
    func clickStripRule() {
        #expect(PointerSurfaceLayout.showsClickStrip(enabled: true, padHeight: 400))
        #expect(PointerSurfaceLayout.showsClickStrip(enabled: true, padHeight: 240))
        #expect(!PointerSurfaceLayout.showsClickStrip(enabled: true, padHeight: 239))
        #expect(!PointerSurfaceLayout.showsClickStrip(enabled: false, padHeight: 600))
    }
}
