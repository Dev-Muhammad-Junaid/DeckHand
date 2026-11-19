//
//  LayoutMetrics.swift
//  PixelHandCore
//
//  Size classes, the layout grid and the deck's whole-point key size, as
//  plain maths so the boundaries are tested on Linux. Read from the window's
//  (or pane's) size in points; never from the device model or idiom.
//  Spec: `Product/Design/03-Layout-Strategy.md` §0 and Option A,
//  `Product/Design/07-Polish-Spec.md` §1.
//

/// The layout facts for one window or pane.
public struct LayoutMetrics: Sendable, Hashable {
    /// Width class: `compact < 500 ≤ medium < 900 ≤ wide`.
    public enum WidthClass: String, Sendable, Hashable, CaseIterable {
        case compact, medium, wide
    }

    /// Height class: `short < 500 ≤ tall`.
    public enum HeightClass: String, Sendable, Hashable, CaseIterable {
        case short, tall
    }

    /// How the control surface's canvas is arranged (Option A, "Dock & Canvas").
    public enum Arrangement: String, Sendable, Hashable, CaseIterable {
        /// One surface at a time; tab bar at the bottom (iPhone portrait,
        /// Duo cover, Slide Over).
        case single
        /// Short and not compact (iPhone landscape): the surface plus a
        /// leading rail for the strip and dock.
        case rail
        /// Medium and tall (iPad portrait, ½ Split View, Duo laptop): the
        /// screen over the trackpad, split with a handle.
        case split
        /// Wide and tall (iPad landscape, large Stage Manager): centre column
        /// with a deck column and the Macs sidebar.
        case columns
    }

    public static let compactUpperBound: Double = 500
    public static let mediumUpperBound: Double = 900
    public static let shortUpperBound: Double = 500

    /// Fixed column widths on wide layouts (`07-Polish-Spec.md` §1).
    public static let sidebarWidth: Double = 232
    public static let deckColumnWidth: Double = 336
    /// Key size inside the wide deck column (3 × 96 + 2 × 12 + 2 × 12 inset).
    public static let wideKeySize: Double = 96

    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var widthClass: WidthClass {
        if width < Self.compactUpperBound { return .compact }
        if width < Self.mediumUpperBound { return .medium }
        return .wide
    }

    public var heightClass: HeightClass {
        height < Self.shortUpperBound ? .short : .tall
    }

    /// The canvas arrangement for this size.
    public var arrangement: Arrangement {
        switch (widthClass, heightClass) {
        case (.compact, _): return .single
        case (_, .short): return .rail
        case (.medium, .tall): return .split
        case (.wide, .tall): return .columns
        }
    }

    /// Onboarding and other two-column pages: `wide || (medium && short)`
    /// (`06-Pixel-Identity.md` §9).
    public var usesTwoColumnPages: Bool {
        widthClass == .wide || (widthClass == .medium && heightClass == .short)
    }

    // MARK: Grid

    /// Layout-grid columns: 4 · 8 · 12.
    public var gridColumns: Int {
        switch widthClass {
        case .compact: return 4
        case .medium: return 8
        case .wide: return 12
        }
    }

    /// The class margin: 16 · 20 · 24. 20 exists only here.
    public var margin: Double {
        switch widthClass {
        case .compact: return 16
        case .medium: return 20
        case .wide: return 24
        }
    }

    /// Gutter between grid columns and between deck keys: 12 · 12 · 16.
    public var gutter: Double {
        widthClass == .wide ? 16 : 12
    }

    // MARK: Deck

    /// Keys per deck row: 4 on compact, 5–6 on medium (6 from 640 pt), 3 in
    /// the wide deck column.
    public var deckColumns: Int {
        switch widthClass {
        case .compact: return 4
        case .medium: return width >= 640 ? 6 : 5
        case .wide: return 3
        }
    }

    /// The deck grid across the full width, with whole-point keys and the
    /// remainder in the margins. On wide layouts the deck lives in its fixed
    /// column instead (`deckColumnGrid`).
    public var deckGrid: DeckGrid {
        if widthClass == .wide { return Self.deckColumnGrid }
        return DeckGrid(containerWidth: width, columns: deckColumns, margin: margin, gutter: 12)
    }

    /// The wide layout's deck column: 3 keys of 96 with 12 pt gutters and
    /// 12 pt insets.
    public static let deckColumnGrid = DeckGrid(containerWidth: deckColumnWidth, columns: 3, margin: 12, gutter: 12)
}

/// Whole-point key sizing (`07-Polish-Spec.md` §1): key size =
/// floor((width − 2 × margin − (n − 1) × gutter) / n); the remainder goes to
/// the two margins (an odd point to the trailing one), never into gutters.
public struct DeckGrid: Sendable, Hashable {
    public let columns: Int
    public let gutter: Double
    public let keySize: Double
    public let leadingMargin: Double
    public let trailingMargin: Double

    public init(containerWidth: Double, columns: Int, margin: Double, gutter: Double) {
        let n = max(1, columns)
        let available = containerWidth - 2 * margin - Double(n - 1) * gutter
        let key = max(0, (available / Double(n)).rounded(.down))
        let remainder = max(0, containerWidth - Double(n - 1) * gutter - key * Double(n))
        let leading = (remainder / 2).rounded(.down)
        self.columns = n
        self.gutter = gutter
        self.keySize = key
        self.leadingMargin = leading
        self.trailingMargin = remainder - leading
    }

    /// Total width the keys and gutters take.
    public var contentWidth: Double {
        keySize * Double(columns) + gutter * Double(columns - 1)
    }
}
