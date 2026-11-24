//
//  ContrastAudit.swift
//  PixelHandCore
//
//  The colour pairs the app actually draws, with the WCAG 2 AA minimum each
//  one must meet, resolved for every appearance (light, dark and both
//  Increase Contrast variants). Pure maths over `PaletteTokens`, so the
//  accessibility pass (UX-013) is checked on Linux.
//  Spec: `Product/Design/02-Design-System.md` §1.2, `04-Interaction-Model.md` §8.
//

import Foundation

/// One appearance a semantic token resolves for.
public struct ContrastAppearance: Sendable, Hashable, CustomStringConvertible {
    public let isDark: Bool
    public let highContrast: Bool

    public init(isDark: Bool, highContrast: Bool) {
        self.isDark = isDark
        self.highContrast = highContrast
    }

    public static let all: [ContrastAppearance] = [
        .init(isDark: false, highContrast: false),
        .init(isDark: true, highContrast: false),
        .init(isDark: false, highContrast: true),
        .init(isDark: true, highContrast: true),
    ]

    public var description: String {
        (isDark ? "dark" : "light") + (highContrast ? " + Increase Contrast" : "")
    }
}

/// A colour as a pair names it: a semantic token or a fixed brand colour.
public enum ContrastColor: Sendable, Hashable {
    case token(ColorToken)
    case fixed(Swatch)

    public static func brand(_ color: RGBColor) -> ContrastColor { .fixed(Swatch(color)) }

    /// The opaque colour a viewer sees over `background`.
    public func resolved(_ appearance: ContrastAppearance, over background: RGBColor) -> RGBColor {
        switch self {
        case .token(let token):
            token.swatch(dark: appearance.isDark, highContrast: appearance.highContrast).resolved(over: background)
        case .fixed(let swatch):
            swatch.resolved(over: background)
        }
    }

    /// True for brand colours, which don't change with the appearance.
    var isFixed: Bool {
        if case .fixed = self { return true }
        return false
    }
}

/// A foreground drawn on a background, and what it's used for.
public struct ContrastPair: Sendable, Hashable {
    /// WCAG 2 AA use classes.
    public enum Use: Sendable, Hashable {
        /// Body-size text: 4.5:1 (SC 1.4.3).
        case text
        /// Text at 18 pt, or 14 pt bold and up (button labels in the
        /// `.headline` role): 3:1 (SC 1.4.3).
        case largeText
        /// Control boundaries, selection outlines, status dots, glyphs: 3:1
        /// (SC 1.4.11).
        case nonText

        public var minimum: Double {
            switch self {
            case .text: 4.5
            case .largeText, .nonText: 3
            }
        }
    }

    public let name: String
    public let foreground: ContrastColor
    public let background: ContrastColor
    public let use: Use

    public init(_ name: String, _ foreground: ContrastColor, on background: ContrastColor, use: Use) {
        self.name = name
        self.foreground = foreground
        self.background = background
        self.use = use
    }

    /// The ratio in one appearance. Translucent backgrounds (tints) are
    /// composited over that appearance's canvas first.
    public func ratio(_ appearance: ContrastAppearance) -> Double {
        let canvas = PaletteTokens.canvas.swatch(dark: appearance.isDark, highContrast: appearance.highContrast).color
        let back = background.resolved(appearance, over: canvas)
        let front = foreground.resolved(appearance, over: back)
        return RGBColor.contrast(front, back)
    }

    /// The appearances this pair is drawn in: one for a pair of fixed brand
    /// colours (navy surfaces look the same in light and dark), all four
    /// otherwise.
    public var appearances: [ContrastAppearance] {
        foreground.isFixed && background.isFixed ? [ContrastAppearance.all[1]] : ContrastAppearance.all
    }

    /// The lowest ratio across `appearances`.
    public var worstRatio: Double {
        appearances.map(ratio).min() ?? 0
    }

    public var passes: Bool { worstRatio >= use.minimum }
}

/// The pairs the app draws. Every one must pass; `ContrastAuditTests`
/// fails if a token edit breaks one.
public enum ContrastAudit {
    private typealias T = PaletteTokens
    private typealias B = PaletteTokens.Brand

    /// Semantic text and controls on the canvas, cards and sheets.
    public static let semantic: [ContrastPair] = {
        var pairs: [ContrastPair] = []
        let surfaces: [(String, ColorToken)] = [("canvas", T.canvas), ("raised", T.raised), ("elevated", T.elevated)]
        for (surfaceName, surface) in surfaces {
            pairs.append(ContrastPair("ink on \(surfaceName)", .token(T.ink), on: .token(surface), use: .text))
            pairs.append(ContrastPair("ink2 on \(surfaceName)", .token(T.ink2), on: .token(surface), use: .text))
            pairs.append(ContrastPair("accentInk on \(surfaceName)", .token(T.accentInk), on: .token(surface), use: .text))
            pairs.append(ContrastPair("success on \(surfaceName)", .token(T.success), on: .token(surface), use: .text))
            pairs.append(ContrastPair("warning on \(surfaceName)", .token(T.warning), on: .token(surface), use: .text))
            pairs.append(ContrastPair("danger on \(surfaceName)", .token(T.danger), on: .token(surface), use: .text))
            // Selection outlines, toggles, edit outlines, accent glyphs.
            pairs.append(ContrastPair("accent on \(surfaceName)", .token(T.accent), on: .token(surface), use: .nonText))
        }
        pairs += [
            // Pills, banners, AI panels and destructive buttons: text on its tint.
            ContrastPair("accentInk on accentTint", .token(T.accentInk), on: .token(T.accentTint), use: .text),
            ContrastPair("success on successTint", .token(T.success), on: .token(T.successTint), use: .text),
            ContrastPair("warning on warningTint", .token(T.warning), on: .token(T.warningTint), use: .text),
            ContrastPair("danger on dangerTint", .token(T.danger), on: .token(T.dangerTint), use: .text),
            // Primary button labels use the `.headline` role (semibold).
            ContrastPair("white on accent", .brand(.white), on: .token(T.accent), use: .largeText),
        ]
        return pairs
    }()

    /// Phosphor, cobalt and the lit colours on the always-navy surfaces
    /// (trackpad, mirror pane, status strip, onboarding, paywall).
    public static let navy: [ContrastPair] = {
        var pairs: [ContrastPair] = []
        let surfaces: [(String, RGBColor)] = [
            ("screen", B.screen), ("screenRaised", B.screenRaised), ("screenLift", B.screenLift),
            ("screenHigh", B.screenHigh), ("navBar", B.navBar),
        ]
        for (surfaceName, surface) in surfaces {
            pairs.append(ContrastPair("phosphor on \(surfaceName)", .brand(B.phosphor), on: .brand(surface), use: .text))
            pairs.append(ContrastPair("ray on \(surfaceName)", .brand(B.ray), on: .brand(surface), use: .text))
            pairs.append(ContrastPair("glow on \(surfaceName)", .brand(B.glow), on: .brand(surface), use: .text))
            pairs.append(ContrastPair("mint on \(surfaceName)", .brand(B.mint), on: .brand(surface), use: .text))
            pairs.append(ContrastPair("sky on \(surfaceName)", .brand(B.sky), on: .brand(surface), use: .text))
        }
        pairs += [
            // Dim dot-matrix text: the status strip and display picker sit on
            // the mirror pane (`screen`); the Mac panel's version line sits on
            // `screenRaised` at Mac text sizes (large text).
            ContrastPair("stripDim on screen", .brand(B.stripDim), on: .brand(B.screen), use: .text),
            ContrastPair("stripDim on screenRaised", .brand(B.stripDim), on: .brand(B.screenRaised), use: .largeText),
            // Cobalt on navy: accent keys, the icon tile, glow edges. Never text.
            ContrastPair("cobalt on screen", .brand(B.cobalt), on: .brand(B.screen), use: .nonText),
            ContrastPair("cobaltHigh on screen", .brand(B.cobaltHigh), on: .brand(B.screen), use: .nonText),
            ContrastPair("cobaltHigh on screenRaised", .brand(B.cobaltHigh), on: .brand(B.screenRaised), use: .nonText),
            // Text on the cobalt accent key.
            ContrastPair("white on cobalt", .brand(.white), on: .brand(B.cobalt), use: .text),
            ContrastPair("phosphor on cobalt", .brand(B.phosphor), on: .brand(B.cobalt), use: .text),
        ]
        return pairs
    }()

    public static var all: [ContrastPair] { semantic + navy }

    /// Pairs below their minimum. Empty when the palette passes.
    public static var failures: [ContrastPair] { all.filter { !$0.passes } }

    /// Known limits, kept out of `all` on purpose and checked by the tests so
    /// they're reviewed if a token moves:
    /// - `ink3` is for tertiary text, placeholders and chords, which repeat
    ///   information spoken in the key's accessibility value; it sits at
    ///   about 2.5:1 light and 3.3:1 dark.
    /// - `accent` as body text on dark surfaces is about 4.1–4.4:1; accent
    ///   text uses `accentInk` (about 9:1) instead.
    /// - Plain `cobalt` drops below 3:1 on `screenRaised` and `screenHigh`,
    ///   so it never draws a control's only boundary there.
    public static let documentedLimits: [ContrastPair] = [
        ContrastPair("ink3 on canvas", .token(T.ink3), on: .token(T.canvas), use: .nonText),
        ContrastPair("accent as text on canvas", .token(T.accent), on: .token(T.canvas), use: .text),
        ContrastPair("cobalt on screenRaised", .brand(B.cobalt), on: .brand(B.screenRaised), use: .nonText),
    ]
}
