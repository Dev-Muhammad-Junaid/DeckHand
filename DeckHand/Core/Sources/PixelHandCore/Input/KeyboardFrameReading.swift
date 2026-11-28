//
//  KeyboardFrameReading.swift
//  PixelHandCore
//
//  Reading the on-screen keyboard's frame in the window's space (build 28
//  bug 6, P1: the Type panel sat under the keyboard in iPad landscape, as
//  in build 25 bug 1). The keyboard notifications give an end frame in
//  screen coordinates. Converting it to the window was one call against
//  the screen's interface-oriented space; in landscape that conversion can
//  come back turned a quarter (a 1210 × 398 keyboard read as 398 × 1210),
//  and a frame from the old orientation can arrive while the window has
//  already turned. Either way the panel's free room ignored the keyboard
//  and a panel parked at the bottom drew under it.
//
//  So the host converts the frame every way it can and Core picks the one
//  that reads as a keyboard in *this* window: wider than tall (the full
//  keyboard, the floating one and the slim shortcut bar all are), shorter
//  than the window, and either reaching the window's bottom, floating
//  inside it, or parked below it (hidden). A frame that reads as none of
//  those is not used, and the last good reading stands.
//
//  Pure rules, tested on Linux; `DeckHandiOS/Keyboard/TypePanelModel.swift`
//  measures.
//

import Foundation

public enum KeyboardFrameReading {
    /// What a candidate frame says about the keyboard.
    public enum Reading: Sendable, Hashable {
        /// The frame covers the window's bottom: its top, in window space,
        /// and how much it covers.
        case covers(top: Double, overlap: Double)
        /// The keyboard is up but covers no bottom edge (floating or
        /// undocked) or is parked below the window (hidden).
        case clear
    }

    /// Whether `frame` (window space) reads as a keyboard in a window this
    /// big. A keyboard is always wider than tall and shorter than the
    /// window; a frame turned a quarter by a wrong conversion is neither.
    public static func isPlausible(_ frame: PanelRect, windowWidth: Double, windowHeight: Double) -> Bool {
        let values = [frame.x, frame.y, frame.width, frame.height, windowWidth, windowHeight]
        guard values.allSatisfy(\.isFinite), windowWidth > 0, windowHeight > 0 else { return false }
        guard frame.width > 0, frame.height > 0 else { return false }
        guard frame.width >= frame.height else { return false }
        guard frame.height < windowHeight else { return false }
        // It overlaps the window horizontally (a docked keyboard spans the
        // screen, which is at least as wide as the window).
        guard frame.maxX > 0, frame.minX < windowWidth else { return false }
        // Not above the window (a frame from a turned space lands there).
        guard frame.maxY > 0 else { return false }
        return true
    }

    /// The first candidate that reads as a keyboard in this window, in
    /// the order the host tried the conversions; `nil` when none does.
    public static func pick(_ candidates: [PanelRect], windowWidth: Double, windowHeight: Double) -> PanelRect? {
        candidates.first { isPlausible($0, windowWidth: windowWidth, windowHeight: windowHeight) }
    }

    /// The reading for the picked frame: whether it covers the window's
    /// bottom (`KeyboardKind.overlap`), and where its top is.
    public static func reading(_ frame: PanelRect, windowHeight: Double) -> Reading {
        let overlap = KeyboardKind.overlap(
            windowMaxY: windowHeight,
            keyboardMinY: frame.minY,
            keyboardMaxY: frame.maxY,
            keyboardHeight: frame.height
        )
        return overlap > 0 ? .covers(top: frame.minY, overlap: overlap) : .clear
    }

    /// One step: the candidates of a new end frame against the window.
    /// `nil` when no candidate reads as a keyboard: keep the last reading.
    public static func read(_ candidates: [PanelRect], windowWidth: Double, windowHeight: Double) -> Reading? {
        guard let frame = pick(candidates, windowWidth: windowWidth, windowHeight: windowHeight) else { return nil }
        return reading(frame, windowHeight: windowHeight)
    }

    // MARK: The keyboard layout guide (build 30 bug 1)

    /// What UIKit's keyboard layout guide says, measured in the window:
    /// the part of a full-window view the docked keyboard covers (`guide`,
    /// zero tall when it covers nothing; the guide ignores a floating or
    /// undocked keyboard). Unlike the notifications it needs no
    /// conversion between spaces and is laid out again whenever the
    /// keyboard, the window or the orientation changes, so it can't be
    /// lost or read turned. `nil` when the guide isn't usable: not a
    /// number, or the view it was read in doesn't reach the window's
    /// bottom (then its zero height says nothing about the keyboard).
    public static func guideReading(_ guide: PanelRect, viewMaxY: Double, windowHeight: Double) -> Reading? {
        let values = [guide.x, guide.y, guide.width, guide.height, viewMaxY, windowHeight]
        guard values.allSatisfy(\.isFinite), windowHeight > 0 else { return nil }
        guard viewMaxY >= windowHeight - 1 else { return nil }
        guard guide.height >= 0.5 else { return .clear }
        // Taller than the window is no keyboard (a frame read mid-turn).
        guard guide.height < windowHeight else { return nil }
        return reading(guide, windowHeight: windowHeight)
    }

    /// The keyboard as both sources see it (build 30 bug 1, P1: in iPad
    /// portrait the notification reading went missing when Live's field
    /// took focus, and the panel drew under the keyboard). The keyboard
    /// covers the window when either source says it does, up to the higher
    /// of their tops, so a reading lost by one source never puts the panel
    /// under the keyboard; it is clear only when every source that has
    /// read anything says clear. `nil` when neither has read anything.
    public static func merged(_ readings: [Reading?]) -> Reading? {
        var top: Double?
        var overlap = 0.0
        var any = false
        for case let reading? in readings {
            any = true
            if case let .covers(t, o) = reading, t.isFinite, o.isFinite {
                top = min(top ?? t, t)
                overlap = max(overlap, o)
            }
        }
        guard any else { return nil }
        guard let top else { return .clear }
        return .covers(top: top, overlap: overlap)
    }
}
