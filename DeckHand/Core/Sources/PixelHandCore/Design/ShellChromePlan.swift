//
//  ShellChromePlan.swift
//  PixelHandCore – Design
//
//  Fitting rules for the shell's chrome, as plain maths so every boundary
//  is tested on Linux (build 18 visual QA, VQ-024, VQ-032, VQ-039, VQ-065,
//  VQ-081, VQ-082):
//
//  - `ShellHeaderPlan`: the header keeps the Mac pill readable. When the
//    action circles don't fit beside a pill of `pillMinimumWidth`, they fold
//    into More (first all but capture, then capture too). At the Huge type
//    band the header is the Mac pill and one menu (`07-Polish-Spec.md` §6).
//  - `DeckHeaderPlan`: the deck header goes to two rows (name, then the
//    counter, pin and Edit) when one row would crush the page name or wrap
//    a button; the page number lives only in the dot-matrix counter.
//  - `AppDockFit`: the dock's scrolling row shows whole icons only.
//
//  Spec: `03-Layout-Strategy.md` (Option A header: Mac pill · capture ·
//  more), `07-Polish-Spec.md` §1, §4, §6.
//

import Foundation

/// How the shell header shows its action circles.
public enum ShellHeaderPlan {
    /// Which circles stay in the header row; the rest go into More.
    public enum Actions: Int, Sendable, Hashable, Comparable {
        /// Every circle (screen, capture, send, sidebar) plus More.
        case full
        /// Capture and More (iPhone portrait in `03-Layout-Strategy.md`).
        case captureAndMore
        /// More alone: everything else is inside it.
        case moreOnly

        public static func < (lhs: Actions, rhs: Actions) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The Mac pill never gets narrower than this while circles sit beside
    /// it: tile, gap, about 12 characters of name, chevron and insets.
    public static let pillMinimumWidth: Double = 168
    /// One header circle and the gap before it (44 + 8).
    public static let circleSlot: Double = 52

    /// The actions that fit in `width` points (the header's full width,
    /// padding included). `circles` counts the optional circles (not More);
    /// `reserved` is anything else in the row (presets, Ask field, link
    /// badge), already measured by the caller.
    public static func actions(
        width: Double,
        horizontalPadding: Double,
        circles: Int,
        reserved: Double = 0,
        band: TypeBand = .standard
    ) -> Actions {
        if band == .huge { return .moreOnly }
        let available = width - 2 * horizontalPadding - reserved
        func fits(_ count: Int) -> Bool {
            available >= pillMinimumWidth + Double(count + 1) * circleSlot
        }
        if fits(circles) { return .full }
        if circles >= 1 && fits(1) { return .captureAndMore }
        return .moreOnly
    }

    /// Lines for the Mac's name in the pill: the Huge band gives the name
    /// its own two lines rather than truncating it to "…" (VQ-065).
    public static func pillNameLines(band: TypeBand) -> Int {
        band == .huge ? 2 : 1
    }

    /// Ways to set the Mac's name on `lines` lines, breaking only between
    /// words, best first. The view (`ViewThatFits`) shows the first whose
    /// lines each fit on one line; the last is the fallback, and each of
    /// its lines truncates at the tail. So a name never hyphenates
    /// ("Muham- / mad’s Mac…", build 19, VQ-065): it reads "Muhammad’s /
    /// MacBook Pro", or "Muhammad’s / MacBook P…".
    ///
    /// - One line: the whole name.
    /// - Two lines: the whole name, then the first line taking as many
    ///   words as it can (all but one, down to one), the rest underneath.
    ///   A one-word name has only itself.
    public static func pillNameCandidates(_ name: String, lines: Int) -> [[String]] {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        let whole = words.joined(separator: " ")
        guard lines >= 2, words.count >= 2 else { return [[whole]] }
        var candidates = [[whole]]
        for split in stride(from: words.count - 1, through: 1, by: -1) {
            candidates.append([
                words[..<split].joined(separator: " "),
                words[split...].joined(separator: " "),
            ])
        }
        return candidates
    }

    /// The smallest the fallback's lines shrink to before they truncate:
    /// a long first word gets smaller rather than cut ("Muhamma…", build 22).
    public static let pillNameMinimumScale: Double = 0.7

    /// The pill's name at the Huge band (build 22, VQ-065): `candidates`
    /// are tried in order and the first whose every line fits whole is
    /// shown; `fallback` shows when none does.
    public struct PillNameLayout: Sendable, Hashable {
        /// Whole-word layouts, best first; none truncates. After the word
        /// splits (`pillNameCandidates`) come the tail ones: the first word
        /// alone, then as many next words as fit and "…" ("Muhammad’s /
        /// MacBook…").
        public let candidates: [[String]]
        /// Shown when no candidate fits: the first word alone on line 1
        /// (shrunk to `pillNameMinimumScale` before it truncates), the rest
        /// on line 2, truncating at the tail. Never one line for a name of
        /// two or more words.
        public let fallback: [String]
    }

    /// The pill's name on `lines` lines, broken only between words.
    public static func pillNameLayout(_ name: String, lines: Int) -> PillNameLayout {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        var candidates = pillNameCandidates(name, lines: lines)
        guard lines >= 2, words.count >= 2 else {
            return PillNameLayout(candidates: candidates, fallback: candidates[0])
        }
        if words.count >= 3 {
            for end in stride(from: words.count - 1, through: 2, by: -1) {
                candidates.append([words[0], words[1..<end].joined(separator: " ") + "…"])
            }
        }
        return PillNameLayout(
            candidates: candidates,
            fallback: [words[0], words[1...].joined(separator: " ")]
        )
    }
}

/// How a status banner (the lock banner, missing permissions) lays out
/// (build 22). At AX3 the lock banner kept its glyph, message and Keyboard
/// button on one row; the message column got so narrow that "Muhammad’s"
/// broke mid-word ("Muham-"). Stacked, the button goes under the message,
/// which then has the banner's full width and breaks only between words.
public enum StatusBannerPlan {
    public enum Arrangement: Sendable, Hashable {
        /// Glyph, message and fix button on one row.
        case inline
        /// Glyph and message, then the fix button on its own row.
        case stacked
    }

    /// The message column is never narrower than this beside a fix button.
    public static let inlineMinimumMessageWidth: Double = 160
    /// The fix button (about "Keyboard" in footnote semibold with its
    /// padding) and the gap before it, at the Standard band.
    public static let fixSlot: Double = 108
    /// The glyph, the gap after it, and the banner's own insets (14 + 12).
    public static let chromeWidth: Double = 54

    /// `width` is the banner's measured width (`nil` before the first
    /// measure); `hasFix` says whether it has a fix button.
    public static func arrangement(width: Double?, band: TypeBand, hasFix: Bool) -> Arrangement {
        guard hasFix else { return .inline }
        if band >= .large { return .stacked }
        guard let width else { return .inline }
        return width - chromeWidth - fixSlot >= inlineMinimumMessageWidth ? .inline : .stacked
    }
}

/// How the deck's page header lays out in its column.
public struct DeckHeaderPlan: Sendable, Hashable {
    /// One row needs this much: page badge 32, the page name at about 120,
    /// the counter, pin 44, Edit about 72, and the 12 pt gaps between.
    public static let oneRowMinimumWidth: Double = 340

    /// Name, counter, pin and Edit on one row; otherwise two rows.
    public let isOneRow: Bool
    /// The dot-matrix page counter shows (two or more pages).
    public let showsCounter: Bool
    /// Edit-mode Undo shows only its glyph (Huge band), with the Large
    /// Content Viewer for its label.
    public let undoIsGlyphOnly: Bool

    public init(width: Double, band: TypeBand, pageCount: Int) {
        isOneRow = band == .standard && width >= Self.oneRowMinimumWidth
        showsCounter = pageCount > 1
        undoIsGlyphOnly = band == .huge
    }

    /// The line under the page name: what decides the page, never the page
    /// number (the counter shows it; VQ-082). `nil` hides the line.
    public static func subtitle(isPinned: Bool, followsApp: Bool, followingOn: Bool) -> String? {
        if isPinned { return "Pinned" }
        if followsApp { return "Follows the front app" }
        if !followingOn { return "Following off" }
        return nil
    }
}

/// Fits the app dock's scrolling row to whole icons (VQ-039).
public enum AppDockFit {
    /// One app: the 44 pt target.
    public static let slot: Double = 44
    /// Between apps.
    public static let spacing: Double = 8
    /// Inside the row's ends.
    public static let inset: Double = 12

    /// The row's width for `available` points and `count` apps: as many
    /// whole slots as fit (at least one), never a part of one. `overflows`
    /// says more apps wait past the trailing edge (the row fades its last
    /// slot then).
    public static func row(available: Double, count: Int) -> (width: Double, slots: Int, overflows: Bool) {
        let fitting = max(1, Int(((available - 2 * inset + spacing) / (slot + spacing)).rounded(.down)))
        let shown = max(1, min(fitting, count))
        let width = 2 * inset + Double(shown) * slot + Double(shown - 1) * spacing
        return (width, shown, count > fitting)
    }
}
