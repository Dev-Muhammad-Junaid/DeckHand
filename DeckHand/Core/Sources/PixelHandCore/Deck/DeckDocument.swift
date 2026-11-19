//
//  DeckDocument.swift
//  PixelHandCore
//
//  The deck model ("Deck 2", release 1.2, D1): an ordered list of pages,
//  each an ordered list of keys, each key running one `Action`. A page
//  stores order, not coordinates: the grid reflows to the space it has.
//
//  Stored on the remote as JSON (`DeckStore` on iOS) with a schema version.
//  `DeckMigration` reads every older shape (the version 1 skeleton, and the
//  chips' `ShortcutStore` data from before decks existed); `DeckValidation`
//  bounds every size and string before a document is used or saved.
//

import Foundation

public struct DeckDocument: Codable, Sendable, Equatable {
    /// Bump when the stored shape changes, and add a migration step to
    /// `DeckMigration`.
    /// - 1: the skeleton (`version`, pages with an optional app, keys with
    ///   an SF Symbol). Never shipped to users' storage.
    /// - 2: page kinds, key appearance (pixel glyphs), follow-front-app and
    ///   pin, hidden curated presets, `menuCommand` / `macShortcut` /
    ///   `sequence` actions.
    public static let currentVersion = 2

    public var schemaVersion: Int
    public var pages: [DeckPage]
    /// "Follow front app": show the frontmost app's page when it changes
    /// (debounced, `DeckFollower`). On by default.
    public var followFrontApp: Bool
    /// The page the user pinned (no auto-switching while set), or `nil`.
    public var pinnedPageID: String?
    /// Apps hidden from the app grid (carried over from the grid's own
    /// preference).
    public var hiddenAppBundleIDs: [String]

    public init(
        schemaVersion: Int = DeckDocument.currentVersion,
        pages: [DeckPage],
        followFrontApp: Bool = true,
        pinnedPageID: String? = nil,
        hiddenAppBundleIDs: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.pages = pages
        self.followFrontApp = followFrontApp
        self.pinnedPageID = pinnedPageID
        self.hiddenAppBundleIDs = hiddenAppBundleIDs
    }

    /// A first-run deck: an empty Home page.
    public static var empty: DeckDocument {
        DeckDocument(pages: [DeckPage(id: DeckPage.homeID, title: "Home", kind: .home, keys: [])])
    }

    /// The page to show when `bundleID` is frontmost: its own app page if
    /// it has one, otherwise Home, otherwise the first page that isn't tied
    /// to an app.
    public func page(forFrontmostApp bundleID: String?) -> DeckPage? {
        if let bundleID, let own = appPage(for: bundleID) { return own }
        return pages.first { $0.kind == .home } ?? pages.first { $0.appBundleID == nil }
    }

    public func appPage(for bundleID: String) -> DeckPage? {
        pages.first { $0.appBundleID == bundleID }
    }

    public func page(id: String) -> DeckPage? {
        pages.first { $0.id == id }
    }

    public func pageIndex(id: String) -> Int? {
        pages.firstIndex { $0.id == id }
    }
}

/// What a page is, and who keeps it (product spec §3.3).
public enum DeckPageKind: Codable, Sendable, Equatable, Hashable {
    /// The user's global keys (launchers, media, system).
    case home
    /// Keys for one app, shown while it is frontmost.
    case app(bundleID: String)
    /// Live: dialog buttons plus the front app's page. Stores no keys of
    /// its own beyond what the user pins to it.
    case context
    /// The Mac's Shortcuts.app shortcuts, kept by Pixel Hand.
    case shortcuts
    /// A page the user made that isn't tied to anything.
    case custom
}

public struct DeckPage: Codable, Sendable, Equatable, Identifiable {
    /// The Home page's ID in a migrated or first-run deck.
    public static let homeID = "home"

    public var id: String
    public var title: String
    public var kind: DeckPageKind
    public var keys: [DeckKey]
    /// Curated presets (`CuratedShortcuts` IDs) the user hid on this app
    /// page. Curated presets aren't stored as keys; they're added at show
    /// time, minus these.
    public var hiddenCuratedIDs: [String]

    public init(id: String, title: String, kind: DeckPageKind = .custom, keys: [DeckKey], hiddenCuratedIDs: [String] = []) {
        self.id = id
        self.title = title
        self.kind = kind
        self.keys = keys
        self.hiddenCuratedIDs = hiddenCuratedIDs
    }

    /// The app this page belongs to, for `.app` pages.
    public var appBundleID: String? {
        if case let .app(bundleID) = kind { return bundleID }
        return nil
    }

    /// The ID an app page gets in a migrated deck.
    public static func appPageID(for bundleID: String) -> String { "app.\(bundleID)" }
}

public struct DeckKey: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var appearance: KeyAppearance
    public var action: Action
    /// "Ask before running".
    public var confirm: Bool
    /// Kept in the grid's first row however it reflows.
    public var pinnedToFirstRow: Bool
    /// The menu a key imported from the Mac's menus came from ("File"),
    /// for sectioning. `nil` for keys the user made.
    public var category: String?

    public init(
        id: String,
        appearance: KeyAppearance,
        action: Action,
        confirm: Bool = false,
        pinnedToFirstRow: Bool = false,
        category: String? = nil
    ) {
        self.id = id
        self.appearance = appearance
        self.action = action
        self.confirm = confirm
        self.pinnedToFirstRow = pinnedToFirstRow
        self.category = category
    }

    /// Shorthand for a key with a label and an optional SF Symbol.
    public init(id: String, label: String, symbol: String? = nil, action: Action) {
        self.init(id: id, appearance: KeyAppearance(label: label, glyph: symbol.map { .symbol(name: $0) }), action: action)
    }

    public var label: String { appearance.label }
}

/// How a key looks: its label, a glyph, and a colour from the brand
/// palette.
public struct KeyAppearance: Codable, Sendable, Equatable, Hashable {
    public var label: String
    public var glyph: KeyGlyph?
    /// A brand palette token name (`"accent"`, `"mint"`, …), resolved by
    /// the app's theme; `nil` for the default.
    public var tint: String?

    public init(label: String, glyph: KeyGlyph? = nil, tint: String? = nil) {
        self.label = label
        self.glyph = glyph
        self.tint = tint
    }
}

public enum KeyGlyph: Codable, Sendable, Equatable, Hashable {
    /// An SF Symbol by name (today's chips).
    case symbol(name: String)
    /// One of the design system's 9 × 9 pixel glyphs, by its ID
    /// (`"missionControl"`, `"build"`, …). An ID the app doesn't know
    /// draws a fallback, so a newer deck still opens.
    case pixel(id: String)
    /// A glyph the user drew in the key inspector.
    case custom(bitmap: PixelGlyphData)
    /// The real icon of a Mac app.
    case appIcon(bundleID: String)
}

/// A user-drawn pixel glyph: `size` rows of `size` dots, each row a bit
/// mask (bit 0 = leftmost dot). 8 × 8 (the editor's first round) or 9 × 9
/// (the design system's grid).
public struct PixelGlyphData: Codable, Sendable, Equatable, Hashable {
    public static let allowedSizes: ClosedRange<Int> = 8...9

    public var size: Int
    public var rows: [UInt16]
    /// The one lit accent dot, if any.
    public var accent: GlyphDot?

    public init(size: Int, rows: [UInt16], accent: GlyphDot? = nil) {
        self.size = size
        self.rows = rows
        self.accent = accent
    }

    /// A blank glyph of `size`.
    public static func blank(size: Int = 9) -> PixelGlyphData {
        PixelGlyphData(size: size, rows: Array(repeating: 0, count: size))
    }

    /// Whether the dot at (`x`, `y`) is lit. Out-of-range is unlit.
    public func isOn(x: Int, y: Int) -> Bool {
        guard (0..<size).contains(x), y >= 0, y < rows.count else { return false }
        return rows[y] & (1 << UInt16(x)) != 0
    }

    /// The same glyph with the dot at (`x`, `y`) set to `on`.
    public func setting(x: Int, y: Int, on: Bool) -> PixelGlyphData {
        guard (0..<size).contains(x), (0..<size).contains(y), y < rows.count else { return self }
        var copy = self
        if on { copy.rows[y] |= 1 << UInt16(x) } else { copy.rows[y] &= ~(1 << UInt16(x)) }
        return copy
    }

    /// Well formed: an allowed size, one row per line, no bits past the
    /// edge, and an accent (if any) on a lit dot.
    public var isWellFormed: Bool {
        guard Self.allowedSizes.contains(size), rows.count == size else { return false }
        let mask: UInt16 = (1 << UInt16(size)) - 1
        guard rows.allSatisfy({ $0 & ~mask == 0 }) else { return false }
        if let accent { return isOn(x: accent.x, y: accent.y) }
        return true
    }

    /// Design rule 1 (strokes one dot wide): no 2 × 2 lit block. A warning
    /// in the editor, never a block.
    public var hasThickStroke: Bool {
        guard size >= 2 else { return false }
        for y in 0..<(size - 1) {
            for x in 0..<(size - 1)
            where isOn(x: x, y: y) && isOn(x: x + 1, y: y) && isOn(x: x, y: y + 1) && isOn(x: x + 1, y: y + 1) {
                return true
            }
        }
        return false
    }
}

public struct GlyphDot: Codable, Sendable, Equatable, Hashable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}
