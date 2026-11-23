//
//  PointerCaption.swift
//  PixelHandCore
//
//  What the Pointer surface's caption says (UX-004). At rest it teaches the
//  scroll gesture; while a finger works it names what the Mac is doing
//  ("DRAGGING", "MISSION CONTROL"). Captions are dot-matrix: uppercase, only
//  `DotMatrixFont` characters, short enough for the narrowest pad, and each
//  has a plain-language label for VoiceOver.
//  Spec: `Product/Design/04-Interaction-Model.md` §2 (Pointer),
//  `06-Pixel-Identity.md` §2 (dot-matrix rules).
//

/// What the pad is doing right now, as far as the caption cares.
public enum PointerActivity: Equatable, Sendable {
    /// No finger down. `scrollMode` means one finger scrolls.
    case idle(scrollMode: Bool)
    case cursor
    case scroll
    /// Held still: moving now drags.
    case dragArmed
    case dragging
    /// Two-finger drag lock: tap to drop.
    case dragLocked
    case pencilHover
    /// A three- or four-finger gesture, decided at lift.
    case system(MultiFingerGesture)
}

/// The caption pill's content.
public struct PointerCaption: Equatable, Sendable {
    /// Dot-matrix text (uppercase, `DotMatrixFont` characters only).
    public let text: String
    /// What VoiceOver reads.
    public let spoken: String
    /// The leading glyph.
    public let glyph: GlyphBitmap
    /// `true` while a finger works: the pill lights up.
    public let isActive: Bool

    /// The longest caption, in characters: fits a 343 pt pad (iPhone SE,
    /// 16 pt margins) at the AX pitch with the glyph and padding.
    public static let maxLength = 26

    public static func caption(for activity: PointerActivity) -> PointerCaption {
        switch activity {
        case .idle(let scrollMode):
            return scrollMode
                ? PointerCaption(text: "1 FINGER · SCROLL", spoken: "Scroll mode: one finger scrolls", glyph: PixelGlyphs.click, isActive: false)
                : PointerCaption(text: "2 FINGERS · SCROLL", spoken: "Two fingers to scroll", glyph: PixelGlyphs.click, isActive: false)
        case .cursor:
            return PointerCaption(text: "POINTER", spoken: "Moving the pointer", glyph: PixelGlyphs.pointer, isActive: true)
        case .scroll:
            return PointerCaption(text: "SCROLLING", spoken: "Scrolling", glyph: PixelGlyphs.click, isActive: true)
        case .dragArmed:
            return PointerCaption(text: "MOVE TO DRAG", spoken: "Move to drag", glyph: PixelGlyphs.pointer, isActive: true)
        case .dragging:
            return PointerCaption(text: "DRAGGING", spoken: "Dragging", glyph: PixelGlyphs.pointer, isActive: true)
        case .dragLocked:
            return PointerCaption(text: "DRAG LOCKED · TAP TO DROP", spoken: "Drag locked. Tap to drop.", glyph: PixelGlyphs.lock, isActive: true)
        case .pencilHover:
            return PointerCaption(text: "PENCIL", spoken: "Apple Pencil is aiming", glyph: PixelGlyphs.pointer, isActive: true)
        case .system(let gesture):
            switch gesture {
            case .swipe(.left):
                return PointerCaption(text: "NEXT SPACE", spoken: "Next Space", glyph: PixelGlyphs.spaceRight, isActive: true)
            case .swipe(.right):
                return PointerCaption(text: "PREVIOUS SPACE", spoken: "Previous Space", glyph: PixelGlyphs.spaceLeft, isActive: true)
            case .swipe(.up):
                return PointerCaption(text: "MISSION CONTROL", spoken: "Mission Control", glyph: PixelGlyphs.missionControl, isActive: true)
            case .swipe(.down):
                return PointerCaption(text: "APP EXPOSE", spoken: "App Exposé", glyph: PixelGlyphs.missionControl, isActive: true)
            case .pinch:
                return PointerCaption(text: "APPS", spoken: "Apps", glyph: PixelGlyphs.deck, isActive: true)
            case .spread:
                return PointerCaption(text: "DESKTOP", spoken: "Show Desktop", glyph: PixelGlyphs.showDesktop, isActive: true)
            }
        }
    }
}

/// Layout rules for the Pointer surface that don't need SwiftUI.
public enum PointerSurfaceLayout {
    /// The click strip's height: the primary control height.
    public static let clickStripHeight: Double = 52
    /// Below this pad height the strip hides so the pad keeps room to move
    /// (small iPhones with the keyboard panel open). Gestures still work and
    /// VoiceOver keeps the actions.
    public static let minimumPadHeightForStrip: Double = 240

    /// Whether the click strip shows: the person's setting, and enough room.
    public static func showsClickStrip(enabled: Bool, padHeight: Double) -> Bool {
        enabled && padHeight >= minimumPadHeightForStrip
    }
}
