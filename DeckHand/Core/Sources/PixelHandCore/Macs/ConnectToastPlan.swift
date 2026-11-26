//
//  ConnectToastPlan.swift
//  PixelHandCore
//
//  The "Connecting to <Mac>…" toast with its Cancel (VQ-058, VQ-101) at
//  every text size (build 26, VQ-107). At AX3 on the iPhone picker the
//  toast and Cancel shared one row: the text was squeezed into a circle
//  ("Con- / necti…") and, drawn at the top of the window, Cancel sat over
//  the picker's Pair button. Now:
//
//    inline    the text and Cancel side by side, when that fits.
//    stacked   the text on its own full-width line(s), wrapping at words,
//              with Cancel under it. Always at the accessibility sizes;
//              the view also falls back to it when the inline row
//              doesn't fit.
//
//  On the picker (no session yet) the toast sits under the Pair and
//  Settings bar instead of over it.
//

import Foundation

public enum ConnectToastPlan {
    public enum Arrangement: String, Sendable, Hashable {
        case inline, stacked
    }

    /// Stacked at the accessibility sizes (AX1 and up); inline otherwise.
    public static func arrangement(band: TypeBand) -> Arrangement {
        band == .standard ? .inline : .stacked
    }

    /// The most lines the toast's text takes: two in a row with Cancel,
    /// as many as it needs when stacked (it wraps at words, never cut).
    public static func lineLimit(_ arrangement: Arrangement) -> Int? {
        arrangement == .inline ? 2 : nil
    }

    /// The picker's top bar (Pair and Settings): its top padding and the
    /// 44 pt buttons.
    public static let pickerBarHeight: Double = 8 + 44

    /// How far from the top of the window the toast sits. Over a session
    /// it clears the shell's header (`headerClearance`); on the picker it
    /// clears the Pair and Settings bar, with `gap` under it.
    public static func topInset(hasSession: Bool, headerClearance: Double, gap: Double = 8) -> Double {
        hasSession ? headerClearance : pickerBarHeight + gap
    }
}
