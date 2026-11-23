//
//  CanvasPlan.swift
//  PixelHandCore
//
//  How the control surface arranges its panes for one window size (UX-007,
//  Option A "Dock & Canvas"). `LayoutMetrics.arrangement` picks the family;
//  this plan turns it into the concrete form, column widths and which chrome
//  shows, as plain maths so every boundary is tested on Linux.
//  Spec: `Product/Design/03-Layout-Strategy.md` (Option A),
//  `Product/Design/07-Polish-Spec.md` §1; board "iPad", "Small & landscape".
//
//    single      compact             one surface, strip, dock, tab bar
//    rail        short, not compact  62 pt leading rail · pad · deck column
//                                    (strip on top, dock folded into it)
//    stacked     medium, < 700 wide  surface over a deck panel (drag handle),
//                                    strip, dock, tab bar (½ Split View)
//    sideBySide  medium, ≥ 700 wide  presets in the header; screen over
//                                    pad | deck column; strip, dock + Ask
//    columns     wide and tall       Macs sidebar · centre (presets, Ask
//                                    field, screen over pad, floating dock)
//                                    · deck column with the strip on top
//

import Foundation

/// The layout presets that replace the tab bar on iPad (`03-Layout-Strategy.md`,
/// "From C"): the same panes, three arrangements of them.
public enum LayoutPreset: String, Sendable, Hashable, CaseIterable, Codable {
    /// The screen over the trackpad.
    case split
    /// The screen takes the centre.
    case screen
    /// The trackpad takes the centre; the screen floats as a tile.
    case pointer

    public var title: String {
        switch self {
        case .split: "Split"
        case .screen: "Screen"
        case .pointer: "Pointer"
        }
    }

    /// What VoiceOver reads for the preset button.
    public var spokenTitle: String {
        switch self {
        case .split: "Split: screen over trackpad"
        case .screen: "Screen focus"
        case .pointer: "Pointer focus"
        }
    }

    public var showsDockedScreen: Bool { self != .pointer }
    public var showsPointer: Bool { self != .screen }
}

/// The concrete arrangement of the canvas for one window size.
public struct CanvasPlan: Sendable, Hashable {
    public enum Form: String, Sendable, Hashable, CaseIterable {
        case single, rail, stacked, sideBySide, columns
    }

    // MARK: Constants (points)

    /// The rail's width: the vertical tab bar's glass column.
    public static let railWidth: Double = 62
    /// The trackpad never gets narrower than this next to a deck column.
    public static let minimumPadWidth: Double = 300
    /// The rail's deck column: 40 % of the space after the rail, clamped.
    public static let railDeckShare: Double = 0.4
    public static let railDeckMinimum: Double = 264
    public static let railDeckMaximum: Double = 320
    /// Medium windows at least this wide put the deck beside the pad.
    public static let sideBySideMinimumWidth: Double = 700
    /// The deck column beside the pad on medium windows (board: iPad portrait).
    public static let sideDeckColumnWidth: Double = 300
    /// The wide centre column never gets narrower than this; the Macs
    /// sidebar collapses first.
    public static let minimumCentreWidth: Double = 480
    /// Gap between the wide layout's columns (the wide gutter).
    public static let columnGap: Double = 16
    /// The floating app dock's widest size on wide windows (board).
    public static let floatingDockMaximumWidth: Double = 520
    /// Room the floating dock takes at the foot of the centre column:
    /// 56 pt dock, 16 pt above and below it.
    public static let floatingDockReserve: Double = 88

    // MARK: Plan

    public let metrics: LayoutMetrics
    public let form: Form
    /// Width of the deck column beside the pad (rail, sideBySide, columns);
    /// 0 when the deck isn't a column.
    public let deckColumnWidth: Double
    /// Whether the Macs sidebar shows (wide only, unless collapsed).
    public let showsSidebar: Bool
    /// Whether the window is wide enough for the sidebar at all; the toggle
    /// is offered only then.
    public let canShowSidebar: Bool

    public init(width: Double, height: Double, sidebarCollapsed: Bool = false) {
        let metrics = LayoutMetrics(width: width, height: height)
        self.metrics = metrics
        switch metrics.arrangement {
        case .single:
            form = .single
            deckColumnWidth = 0
            canShowSidebar = false
        case .rail:
            form = .rail
            deckColumnWidth = Self.railDeckColumn(width: metrics.width, margin: metrics.margin, gutter: metrics.gutter)
            canShowSidebar = false
        case .split:
            if metrics.width >= Self.sideBySideMinimumWidth {
                form = .sideBySide
                deckColumnWidth = Self.sideDeckColumnWidth
            } else {
                form = .stacked
                deckColumnWidth = 0
            }
            canShowSidebar = false
        case .columns:
            form = .columns
            deckColumnWidth = LayoutMetrics.deckColumnWidth
            canShowSidebar = Self.centreWidth(width: metrics.width, sidebar: true) >= Self.minimumCentreWidth
        }
        showsSidebar = canShowSidebar && !sidebarCollapsed
    }

    /// The rail's deck column, or 0 when the pad would get narrower than
    /// `minimumPadWidth` (the deck is then a tab).
    static func railDeckColumn(width: Double, margin: Double, gutter: Double) -> Double {
        // Rail, its leading inset, the gap after it and before the deck,
        // and the trailing margin.
        let available = width - railWidth - 8 - 2 * gutter - margin
        let deck = min(railDeckMaximum, max(railDeckMinimum, (available * railDeckShare).rounded(.down)))
        return available - deck - gutter >= minimumPadWidth ? deck : 0
    }

    /// The wide centre column's width: the window minus the sidebar (232,
    /// its 24 pt leading margin included) or the leading margin, the deck
    /// column, the two gaps and the trailing margin.
    public static func centreWidth(width: Double, sidebar: Bool) -> Double {
        let leading = sidebar ? LayoutMetrics.sidebarWidth : 24
        return max(0, width - leading - 2 * columnGap - LayoutMetrics.deckColumnWidth - 24)
    }

    /// The wide centre column's width for this plan.
    public var centreWidth: Double {
        form == .columns ? Self.centreWidth(width: metrics.width, sidebar: showsSidebar) : metrics.width
    }

    /// Whether the deck shows in its own column beside the pad.
    public var hasDeckColumn: Bool { deckColumnWidth > 0 }

    /// Layout presets replace the tab bar on iPad-sized windows.
    public var usesPresets: Bool { form == .sideBySide || form == .columns }

    /// The bottom (or rail) tab bar shows where presets don't.
    public var showsTabBar: Bool { !usesPresets }

    /// Ask is a field in the wide toolbar (⌘K), a circle next to the dock on
    /// sideBySide, and in the tab bar elsewhere.
    public var asksInToolbar: Bool { form == .columns }

    /// The context strip sits on top of the deck column (rail, columns)
    /// rather than in the bottom chrome.
    public var stripInDeckColumn: Bool { form == .columns || (form == .rail && hasDeckColumn) }

    /// The app dock floats at the foot of the centre column (wide).
    public var floatsDock: Bool { form == .columns }

    /// The rail has no room for a dock row: it folds into the strip's
    /// leading app chip, and the keyboard button moves to the rail.
    public var foldsDockIntoStrip: Bool { form == .rail }

    /// The surfaces the tab bar offers: the deck goes when it has a column.
    public var tabSurfacesIncludeDeck: Bool { !hasDeckColumn }

    /// Deck keys per row in the deck column or panel.
    public var deckColumnKeys: Int {
        switch form {
        case .single: return metrics.deckColumns
        case .stacked: return metrics.deckColumns
        case .rail, .sideBySide, .columns: return 3
        }
    }

    /// The key that remembers the preset for one Mac at this form
    /// ("remembered per Mac and per size class").
    public func presetKey(macName: String) -> String {
        "\(macName)|\(form.rawValue)"
    }
}

// MARK: - Pane splits

/// The screen-over-trackpad split (presets Split; the stacked deck panel),
/// with the drag handle's fraction clamped so both panes stay usable.
public enum PaneSplit {
    /// The docked screen is never shorter than this.
    public static let minimumScreenHeight: Double = 200
    /// The pad under it keeps room for the click strip (the Pointer lane's
    /// `PointerSurfaceLayout.minimumPadHeightForStrip`).
    public static let minimumPadHeight: Double = PointerSurfaceLayout.minimumPadHeightForStrip
    /// The default screen share when the picture would be taller.
    public static let defaultScreenShare: Double = 0.62
    /// Gap between the panes, where the drag handle sits.
    public static let gap: Double = 12

    /// Screen height over the pad in `total` points. `fraction` is the
    /// person's drag (screen ÷ total); `nil` uses the picture's height at
    /// full width (`width / aspect`), capped at `defaultScreenShare`.
    /// Returns `nil` when both panes can't fit: the caller then shows the
    /// pad alone with the floating tile.
    public static func screenHeight(total: Double, width: Double, aspect: Double, fraction: Double?) -> Double? {
        let usable = total - gap
        guard usable >= minimumScreenHeight + minimumPadHeight else { return nil }
        let wanted: Double
        if let fraction {
            wanted = total * fraction
        } else {
            wanted = min(width / max(aspect, 0.1), total * defaultScreenShare)
        }
        let clamped = min(usable - minimumPadHeight, max(minimumScreenHeight, wanted))
        return clamped.rounded(.down)
    }

    /// The fraction to remember after a drag of the handle to `screenHeight`.
    public static func fraction(screenHeight: Double, total: Double) -> Double {
        guard total > 0 else { return defaultScreenShare }
        return min(0.9, max(0.1, screenHeight / total))
    }
}

/// The stacked (½ Split View) deck panel under the surface: one row of keys
/// by default, taller by dragging its handle, never squeezing the pad.
public enum DeckPanelSplit {
    /// The panel's title row (app name and Edit) and its insets.
    public static let headerHeight: Double = 44
    public static let minimumPadHeight: Double = PointerSurfaceLayout.minimumPadHeightForStrip
    public static let gap: Double = 12

    /// Rows-of-keys height: `rows` keys of `keySize` with 12 pt gutters,
    /// plus the header and an 8 pt foot.
    public static func panelHeight(rows: Int, keySize: Double) -> Double {
        let n = Double(max(1, rows))
        return headerHeight + n * keySize + (n - 1) * 12 + 8
    }

    /// The panel's height in `total` points, or `nil` when it doesn't fit
    /// beside a usable pad (the deck is then only a tab).
    public static func height(total: Double, requested: Double, keySize: Double) -> Double? {
        let oneRow = panelHeight(rows: 1, keySize: keySize)
        let maxPanel = total - gap - minimumPadHeight
        guard maxPanel >= oneRow else { return nil }
        return min(maxPanel, max(oneRow, requested)).rounded(.down)
    }
}

// MARK: - Remembered presets

/// The presets people chose, per Mac and form, as one small JSON string
/// for `@AppStorage`. Unknown or damaged data reads as empty.
public struct LayoutPresetMemory: Sendable, Hashable {
    public private(set) var presets: [String: LayoutPreset]

    /// Cap so the stored string stays small across many Macs.
    public static let maximumEntries = 32

    public init(presets: [String: LayoutPreset] = [:]) {
        self.presets = presets
    }

    public init(json: String) {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            self.presets = [:]
            return
        }
        self.presets = raw.compactMapValues(LayoutPreset.init(rawValue:))
    }

    public var json: String {
        let raw = presets.mapValues(\.rawValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(raw), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// The remembered preset, or Split.
    public func preset(for key: String) -> LayoutPreset {
        presets[key] ?? .split
    }

    public mutating func set(_ preset: LayoutPreset, for key: String) {
        presets[key] = preset
        if presets.count > Self.maximumEntries {
            // Drop the alphabetically first other entries; order isn't
            // tracked, and 32 Mac × form pairs is far past real use.
            for extra in presets.keys.sorted() where extra != key && presets.count > Self.maximumEntries {
                presets[extra] = nil
            }
        }
    }
}
