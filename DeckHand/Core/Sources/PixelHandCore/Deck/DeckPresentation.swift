//
//  DeckPresentation.swift
//  PixelHandCore
//
//  What the Deck surface (UX-020, D2) draws for a page and a key, as plain
//  data so it is tested on Linux: the keys a page shows (curated presets on
//  app pages, the front app's keys on the Context page, first-row pins),
//  the glyph a key draws (custom → 9 × 9 set → app icon → a symbol mapped
//  onto the set → a glyph for the action), the chord and summary lines,
//  and the grid's column count by type size.
//  Spec: `Product/Design/04-Interaction-Model.md` §2 Deck,
//  `06-Pixel-Identity.md` §1, `07-Polish-Spec.md` §1 and §6.
//

import Foundation

// MARK: - Glyphs

/// The glyph a key draws: one from the pixel set (or the user's own), or
/// the real icon of a Mac app.
public enum ResolvedKeyGlyph: Sendable, Equatable {
    case pixel(GlyphBitmap)
    case appIcon(bundleID: String)
}

extension PixelGlyphData {
    /// The glyph as a 9 × 9 `GlyphBitmap` for drawing. An 8 × 8 glyph sits
    /// in the top-left 8 × 8 cells (the ninth row and column stay unlit),
    /// so its dots line up with the editor's grid. A malformed glyph draws
    /// blank rather than trapping.
    public func bitmap(name: String = "custom", label: String = "Custom glyph") -> GlyphBitmap {
        let side = GlyphBitmap.size
        let pattern: [String] = (0..<side).map { y in
            String((0..<side).map { x -> Character in
                guard isWellFormed, isOn(x: x, y: y) else { return "." }
                if let accent, accent.x == x, accent.y == y { return "*" }
                return "#"
            })
        }
        return GlyphBitmap(name: name, label: label, pattern: pattern)
    }

    /// A glyph of `size` from a set glyph, so a user can start from one.
    /// Going to 8 × 8 drops the ninth row and column.
    public init(bitmap: GlyphBitmap, size: Int = 8) {
        let size = min(max(size, Self.allowedSizes.lowerBound), Self.allowedSizes.upperBound)
        let mask: UInt16 = (1 << UInt16(size)) - 1
        let rows = (0..<size).map { bitmap.rows[$0] & mask }
        var accent: GlyphDot?
        if let point = bitmap.accent, point.x < size, point.y < size { accent = GlyphDot(x: point.x, y: point.y) }
        self.init(size: size, rows: rows, accent: accent)
    }

    /// How many dots are lit.
    public var litCount: Int {
        rows.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    /// The same glyph with every dot unlit.
    public var cleared: PixelGlyphData { .blank(size: size) }

    /// Mirrored left to right (the accent moves with its dot).
    public var mirrored: PixelGlyphData {
        var copy = PixelGlyphData.blank(size: size)
        for y in 0..<size {
            for x in 0..<size where isOn(x: x, y: y) {
                copy = copy.setting(x: size - 1 - x, y: y, on: true)
            }
        }
        if let accent { copy.accent = GlyphDot(x: size - 1 - accent.x, y: accent.y) }
        return copy
    }

    /// Moved one dot in a direction; dots pushed past the edge are lost.
    public func shifted(dx: Int, dy: Int) -> PixelGlyphData {
        var copy = PixelGlyphData.blank(size: size)
        for y in 0..<size {
            for x in 0..<size where isOn(x: x, y: y) {
                copy = copy.setting(x: x + dx, y: y + dy, on: true)
            }
        }
        if let accent, copy.isOn(x: accent.x + dx, y: accent.y + dy) {
            copy.accent = GlyphDot(x: accent.x + dx, y: accent.y + dy)
        }
        return copy
    }

    /// Toggles the dot at (`x`, `y`); unlighting the accent dot clears it.
    public func toggling(x: Int, y: Int) -> PixelGlyphData {
        var copy = setting(x: x, y: y, on: !isOn(x: x, y: y))
        if let accent, !copy.isOn(x: accent.x, y: accent.y) { copy.accent = nil }
        return copy
    }

    /// Makes the lit dot at (`x`, `y`) the accent, or clears the accent
    /// when it is already there. An unlit dot is lit first.
    public func togglingAccent(x: Int, y: Int) -> PixelGlyphData {
        guard (0..<size).contains(x), (0..<size).contains(y) else { return self }
        var copy = setting(x: x, y: y, on: true)
        copy.accent = accent == GlyphDot(x: x, y: y) ? nil : GlyphDot(x: x, y: y)
        return copy
    }
}

public enum DeckGlyphs {
    /// SF Symbols today's chips store, mapped onto the pixel set so
    /// migrated keys draw as pixels. The first matching prefix wins.
    static let symbolMap: [(prefix: String, glyph: String)] = [
        ("magnifyingglass", "search"), ("text.magnifyingglass", "search"),
        ("plus", "plus"), ("xmark", "close"), ("trash", "close"),
        ("play.fill", "play"), ("play", "play"), ("pause", "pause"), ("stop", "stop"),
        ("hammer", "build"), ("terminal", "terminal"), ("lock", "lock"),
        ("paperplane", "send"), ("square.and.arrow.up", "share"),
        ("doc.on.clipboard", "paste"), ("clipboard", "paste"),
        ("keyboard", "keyboard"), ("textformat", "type"), ("character", "type"),
        ("camera", "capture"), ("viewfinder", "region"), ("crop", "region"),
        ("doc.text.viewfinder", "ocr"), ("text.viewfinder", "ocr"),
        ("pin", "pin"), ("pip", "pip"), ("wifi", "wifi"), ("gear", "settings"),
        ("slider", "settings"), ("power", "power"), ("display", "displays"),
        ("rectangle.3.group", "mission"), ("macwindow", "screen"), ("desktopcomputer", "screen"),
        ("laptopcomputer", "laptop"), ("iphone", "iphone"), ("speaker.slash", "mute"),
        ("speaker", "audio"), ("chevron.left", "arrowL"), ("arrow.left", "arrowL"),
        ("arrow.uturn.backward", "arrowL"), ("chevron.right", "arrowR"), ("arrow.right", "arrowR"),
        ("checkmark", "test"), ("cursorarrow", "pointer"), ("hand.tap", "click"),
        ("square.grid", "deck"), ("bubble", "ask"), ("sparkles", "ask"),
    ]

    /// A pixel glyph for an SF Symbol name, or `nil` when none fits.
    public static func glyph(forSymbol name: String) -> GlyphBitmap? {
        for entry in symbolMap where name == entry.prefix || name.hasPrefix(entry.prefix + ".") {
            return PixelGlyphs.named(entry.glyph)
        }
        return nil
    }

    /// The glyph an action draws when its key has none of its own.
    public static func glyph(for action: Action) -> GlyphBitmap {
        switch action {
        case .shortcut, .appShortcut: PixelGlyphs.keyboard
        case .launchApp: PixelGlyphs.mac
        case let .system(macro):
            switch macro {
            case .missionControl, .appExpose: PixelGlyphs.missionControl
            case .showDesktop: PixelGlyphs.showDesktop
            case .locateCursor: PixelGlyphs.pointer
            case .launchpad: PixelGlyphs.deck
            }
        case let .media(key):
            switch key {
            case .playPause: PixelGlyphs.play
            case .next: PixelGlyphs.spaceRight
            case .previous: PixelGlyphs.spaceLeft
            }
        case .contextAction: PixelGlyphs.click
        case .menuCommand: PixelGlyphs.deck
        case .macShortcut: PixelGlyphs.run
        case .sequence: PixelGlyphs.build
        }
    }

    /// What `key` draws, in the model's order of preference: the user's
    /// own glyph, a set glyph by ID (an unknown ID draws the action's
    /// glyph, so a newer deck still opens), an app icon, then a symbol
    /// mapped onto the set, then the action's glyph.
    public static func resolve(_ key: DeckKey) -> ResolvedKeyGlyph {
        switch key.appearance.glyph {
        case let .custom(bitmap)?:
            return .pixel(bitmap.bitmap(name: "custom.\(key.id)", label: key.label))
        case let .pixel(id)?:
            return .pixel(PixelGlyphs.named(id) ?? glyph(for: key.action))
        case let .appIcon(bundleID)?:
            return .appIcon(bundleID: bundleID)
        case let .symbol(name)?:
            return .pixel(glyph(forSymbol: name) ?? glyph(for: key.action))
        case nil:
            if case let .launchApp(bundleID) = key.action { return .appIcon(bundleID: bundleID) }
            return .pixel(glyph(for: key.action))
        }
    }
}

// MARK: - Text

extension Action {
    /// The chord a key shows under its label ("⇧⌘K"), or `nil`.
    public var chordText: String? {
        switch self {
        case let .shortcut(keys), let .appShortcut(_, keys):
            let text = ChordText.glyphs(keys)
            return text.isEmpty ? nil : text
        case let .sequence(steps):
            let count = steps.filter { $0.action != nil }.count
            return count == 1 ? "1 step" : "\(count) steps"
        default:
            return nil
        }
    }

    /// One line for the key inspector and the action library: what the key
    /// does, in plain words. `appName` names a bundle ID when known.
    public func summary(appName: (String) -> String? = { _ in nil }) -> String {
        func name(_ bundleID: String) -> String { appName(bundleID) ?? bundleID }
        switch self {
        case let .shortcut(keys):
            return "Press \(ChordText.glyphs(keys))"
        case let .appShortcut(bundleID, keys):
            return "Press \(ChordText.glyphs(keys)) in \(name(bundleID))"
        case let .launchApp(bundleID):
            return "Open \(name(bundleID))"
        case let .system(macro):
            return macro.title
        case let .media(key):
            return key.title
        case .contextAction:
            return "Press a dialog button"
        case let .menuCommand(bundleID, path):
            return "Menu › " + path.joined(separator: " › ") + " in \(name(bundleID))"
        case let .macShortcut(shortcut):
            return "Run the Shortcut “\(shortcut)”"
        case let .sequence(steps):
            let count = steps.filter { $0.action != nil }.count
            return "Run \(count) \(count == 1 ? "step" : "steps") in order"
        }
    }
}

extension SystemMacro {
    /// The macro's name on a key and in the library.
    public var title: String {
        switch self {
        case .locateCursor: "Find Pointer"
        case .missionControl: "Mission Control"
        case .appExpose: "App Windows"
        case .showDesktop: "Show Desktop"
        case .launchpad: "Launchpad"
        }
    }
}

extension MediaKey {
    /// The key's name on a key and in the library.
    public var title: String {
        switch self {
        case .playPause: "Play/Pause"
        case .next: "Next Track"
        case .previous: "Previous Track"
        }
    }
}

// MARK: - Pages

/// One key as a page shows it, with where it came from.
public struct DeckShownKey: Sendable, Equatable, Identifiable {
    public enum Source: Sendable, Equatable {
        /// Stored on the page; editable.
        case stored
        /// A curated preset for the page's app; can be hidden, not edited.
        case curated
        /// Shown on the Context page from the front app's page.
        case frontApp
    }

    public var key: DeckKey
    public var source: Source
    public var id: String { key.id }

    public init(key: DeckKey, source: Source) {
        self.key = key
        self.source = source
    }
}

extension DeckDocument {
    /// The keys `page` shows: on an app page the curated presets the user
    /// hasn't hidden, then its stored keys; on the Context page its own
    /// keys, then the front app's. Keys pinned to the first row come first
    /// (in order), whatever their source.
    public func shownKeys(on page: DeckPage, frontBundleID: String?) -> [DeckShownKey] {
        var keys = page.keys.map { DeckShownKey(key: $0, source: .stored) }
        switch page.kind {
        case let .app(bundleID):
            let hidden = Set(page.hiddenCuratedIDs)
            let stored = Set(page.keys.map(\.id))
            let curated = CuratedShortcuts.bindings(for: bundleID)
                .filter { !hidden.contains($0.id) && !stored.contains($0.id) }
                .map { DeckShownKey(key: DeckKey(binding: $0), source: .curated) }
            keys = curated + keys
        case .context:
            if let frontBundleID, let front = appPage(for: frontBundleID) {
                let own = Set(keys.map(\.id))
                keys += shownKeys(on: front, frontBundleID: nil)
                    .filter { !own.contains($0.id) }
                    .map { DeckShownKey(key: $0.key, source: .frontApp) }
            } else if let frontBundleID {
                keys += CuratedShortcuts.bindings(for: frontBundleID)
                    .map { DeckShownKey(key: DeckKey(binding: $0), source: .frontApp) }
            }
        case .home, .shortcuts, .custom:
            break
        }
        let pinned = keys.filter { $0.key.pinnedToFirstRow }
        return pinned + keys.filter { !$0.key.pinnedToFirstRow }
    }

    /// The pages in the order the deck pages through them: Home first,
    /// then Context, then the rest as stored.
    public var orderedPages: [DeckPage] {
        let home = pages.filter { $0.kind == .home }
        let context = pages.filter { $0.kind == .context }
        let rest = pages.filter { $0.kind != .home && $0.kind != .context }
        return home + context + rest
    }
}

extension DeckPage {
    /// The title a page shows: its own, or for an app page the app's name
    /// when the title is empty.
    public func displayTitle(appName: (String) -> String? = { _ in nil }) -> String {
        if !title.isEmpty { return title }
        switch kind {
        case .home: return "Home"
        case .context: return "Context"
        case .shortcuts: return "Shortcuts"
        case let .app(bundleID): return appName(bundleID) ?? bundleID
        case .custom: return "Page"
        }
    }

    /// Whether the user may delete this page. Home always stays.
    public var isDeletable: Bool { kind != .home }
}

// MARK: - Grid

public enum DeckGridStyle: Sendable, Equatable {
    /// Square keys, `columns` to a row.
    case grid(columns: Int)
    /// AX3–AX5: one key per row (`DeckKeyRow`).
    case rows
}

extension LayoutMetrics {
    /// The deck's layout at a type size (`07-Polish-Spec.md` §6): the
    /// class's columns as designed, at most 3 at AX1–AX2, rows at AX3+.
    public func deckStyle(for band: TypeBand) -> DeckGridStyle {
        switch band {
        case .standard: .grid(columns: deckColumns)
        case .large: .grid(columns: min(3, deckColumns))
        case .huge: .rows
        }
    }

    /// The whole-point grid for `band`: `deckGrid`, or the same width
    /// with fewer columns at AX1–AX2.
    public func deckGrid(for band: TypeBand) -> DeckGrid {
        guard case let .grid(columns) = deckStyle(for: band), columns != deckGrid.columns else { return deckGrid }
        if widthClass == .wide {
            return DeckGrid(containerWidth: Self.deckColumnWidth, columns: columns, margin: 12, gutter: 12)
        }
        return DeckGrid(containerWidth: width, columns: columns, margin: margin, gutter: 12)
    }
}

extension DeckGrid {
    /// Narrower than this, the deck is in a column (the wide layout's
    /// 336 pt deck column, Slide Over): 3 keys with 12 pt insets.
    public static let columnThreshold: Double = 360

    /// The grid for a deck pane `width` × `height` at `band`: 3 columns in
    /// a narrow column (3 × 96 at 336 pt), otherwise the size class's grid.
    public static func pane(width: Double, height: Double, band: TypeBand) -> DeckGrid {
        if width < columnThreshold {
            return DeckGrid(containerWidth: width, columns: 3, margin: 12, gutter: 12)
        }
        return LayoutMetrics(width: width, height: height).deckGrid(for: band)
    }
}
