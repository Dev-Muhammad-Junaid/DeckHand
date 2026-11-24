//
//  WidgetDeckSnapshot.swift
//  PixelHandCore
//
//  What the app hands its widgets, Control Center controls and App Intent
//  entity queries through the shared App Group container: a few keys to
//  draw, every key's name for the "Deck key" picker, the Macs the remote
//  has controlled, and whether Pro is unlocked. The widget extension never
//  reads `deck.json` or talks to a Mac itself.
//
//  Written by the app whenever `DeckStore` saves, a session starts, or the
//  entitlement changes (`DeckHandiOS/Intents/WidgetSnapshotWriter.swift`).
//

import Foundation

public struct WidgetDeckSnapshot: Codable, Sendable, Equatable {
    /// Bumped when a field changes meaning; a newer snapshot reads as empty
    /// in an older widget rather than wrong.
    public static let currentVersion = 1
    /// The widget shows at most this many keys (a medium widget: 2 × 4).
    public static let maxWidgetKeys = 8
    /// Entity queries list at most this many keys.
    public static let maxListedKeys = 512
    /// The file the snapshot is stored in, inside the App Group container.
    public static let fileName = "widget-deck.json"

    public var version: Int
    public var generatedAt: Date
    /// The keys a widget draws, in order.
    public var widgetKeys: [WidgetKey]
    /// Every key, for the Shortcuts "Deck key" parameter and Spotlight.
    public var allKeys: [WidgetKey]
    /// The Macs this remote has controlled, most recent first.
    public var macs: [RecentMac]
    /// Pro (or trial) was unlocked when the snapshot was written.
    public var isPro: Bool

    public init(
        version: Int = WidgetDeckSnapshot.currentVersion,
        generatedAt: Date,
        widgetKeys: [WidgetKey],
        allKeys: [WidgetKey],
        macs: [RecentMac],
        isPro: Bool
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.widgetKeys = widgetKeys
        self.allKeys = allKeys
        self.macs = macs
        self.isPro = isPro
    }

    public static let empty = WidgetDeckSnapshot(generatedAt: .distantPast, widgetKeys: [], allKeys: [], macs: [], isPro: false)

    /// The Mac shown on the widget (the last one controlled).
    public var currentMac: RecentMac? { macs.first }

    /// Builds the snapshot from the deck. Widget keys: Home's first-row
    /// pins, then Home's other keys, then custom pages' keys, in order.
    /// App pages are left out of the widget (their keys only make sense
    /// with that app in front) but listed for Shortcuts, and so are keys
    /// set to "Ask before running" (Shortcuts and Siri ask; a widget
    /// button can't). Dialog presses are never listed: they only exist
    /// while that dialog is up.
    public static func make(
        from document: DeckDocument,
        macs: [RecentMac],
        isPro: Bool,
        now: Date
    ) -> WidgetDeckSnapshot {
        var seen = Set<String>()
        var all: [WidgetKey] = []
        for page in document.pages {
            for key in page.keys where isListable(key) && !seen.contains(key.id) {
                seen.insert(key.id)
                all.append(WidgetKey(key, pageTitle: page.title))
                if all.count == maxListedKeys { break }
            }
            if all.count == maxListedKeys { break }
        }

        var chosen: [WidgetKey] = []
        var chosenIDs = Set<String>()
        func take(_ keys: [DeckKey], from page: DeckPage) {
            for key in keys where chosen.count < maxWidgetKeys && isListable(key) && !key.confirm && !chosenIDs.contains(key.id) {
                chosenIDs.insert(key.id)
                chosen.append(WidgetKey(key, pageTitle: page.title))
            }
        }
        let homes = document.pages.filter { $0.kind == .home }
        for page in homes { take(page.keys.filter(\.pinnedToFirstRow), from: page) }
        for page in homes { take(page.keys, from: page) }
        for page in document.pages where page.kind == .custom { take(page.keys, from: page) }

        return WidgetDeckSnapshot(
            generatedAt: now,
            widgetKeys: chosen,
            allKeys: all,
            macs: Array(macs.prefix(RecentMac.maxRemembered)),
            isPro: isPro
        )
    }

    private static func isListable(_ key: DeckKey) -> Bool {
        if case .contextAction = key.action { return false }
        return true
    }

    // MARK: - Coding

    public static func encode(_ snapshot: WidgetDeckSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(snapshot)
    }

    /// The stored snapshot, or `.empty` for a missing, damaged or newer
    /// file. A widget always has something to draw.
    public static func decode(_ data: Data?) -> WidgetDeckSnapshot {
        guard let data, data.count <= 4 * 1024 * 1024 else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(WidgetDeckSnapshot.self, from: data),
              snapshot.version <= currentVersion
        else { return .empty }
        return snapshot
    }

    /// The key with `id`, from the full list.
    public func key(id: String) -> WidgetKey? {
        allKeys.first { $0.id == id }
    }

    /// Keys whose label or page title contains `text` (case and diacritics
    /// ignored), for entity search.
    public func keys(matching text: String) -> [WidgetKey] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return allKeys }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return allKeys.filter {
            $0.label.range(of: needle, options: options) != nil
                || $0.pageTitle.range(of: needle, options: options) != nil
        }
    }
}

/// One key as a widget draws it.
public struct WidgetKey: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var pageTitle: String
    public var glyph: WidgetGlyph
    /// A brand palette token name, or `nil` for the default.
    public var tint: String?
    /// The key asks before running ("Ask before running"); a widget or
    /// Siri opens the app instead of running it blind.
    public var confirm: Bool

    public init(id: String, label: String, pageTitle: String, glyph: WidgetGlyph, tint: String? = nil, confirm: Bool = false) {
        self.id = id
        self.label = label
        self.pageTitle = pageTitle
        self.glyph = glyph
        self.tint = tint
        self.confirm = confirm
    }

    public init(_ key: DeckKey, pageTitle: String) {
        self.init(
            id: key.id,
            label: key.label,
            pageTitle: pageTitle,
            glyph: WidgetGlyph.resolve(key.appearance.glyph, action: key.action, label: key.label),
            tint: key.appearance.tint,
            confirm: key.confirm
        )
    }
}

/// A glyph a widget can draw without the app's asset catalogue or the
/// Mac's app icons.
public enum WidgetGlyph: Codable, Sendable, Equatable, Hashable {
    /// A `PixelGlyphs` glyph by board name.
    case pixel(name: String)
    /// A user-drawn bitmap (`PixelGlyphData`).
    case bitmap(PixelGlyphData)
    /// An SF Symbol.
    case symbol(name: String)
    /// Up to two letters, drawn in dot-matrix.
    case monogram(String)

    /// The glyph for a key: its own glyph when a widget can draw it,
    /// otherwise one that fits its action, otherwise its initials. Mac app
    /// icons can't be drawn in a widget, so an app-icon key shows the
    /// app's initials.
    public static func resolve(_ glyph: KeyGlyph?, action: Action, label: String) -> WidgetGlyph {
        switch glyph {
        case let .pixel(id) where PixelGlyphs.named(id) != nil:
            return .pixel(name: id)
        case let .custom(bitmap) where bitmap.isWellFormed:
            return .bitmap(bitmap)
        case let .symbol(name) where !name.isEmpty:
            return .symbol(name: name)
        default:
            break
        }
        switch action {
        case let .system(macro):
            switch macro {
            case .missionControl, .appExpose: return .pixel(name: "mission")
            case .showDesktop: return .pixel(name: "desktop")
            case .launchpad: return .pixel(name: "deck")
            case .locateCursor: return .pixel(name: "pointer")
            }
        case let .media(key):
            return .pixel(name: key == .playPause ? "play" : (key == .next ? "arrowR" : "arrowL"))
        case .macShortcut: return .pixel(name: "run")
        case .sequence: return .pixel(name: "build")
        case .menuCommand: return .pixel(name: "terminal")
        default: return .monogram(monogram(for: label))
        }
    }

    /// The first letters of the first two words, upper-cased, only from
    /// characters the dot-matrix font has; `"?"` when there are none.
    public static func monogram(for label: String) -> String {
        let words = label.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        var letters = ""
        for word in words {
            guard let first = word.uppercased().first(where: { DotMatrixFont.characters.contains($0) }) else { continue }
            letters.append(first)
            if letters.count == 2 { break }
        }
        if letters.count == 1, let word = words.first {
            let rest = word.uppercased().dropFirst().filter { DotMatrixFont.characters.contains($0) && $0.isLetter }
            if let second = rest.first { letters.append(second) }
        }
        return letters.isEmpty ? "?" : letters
    }
}

/// A Mac this remote has controlled, for the "Mac" entity and the widget's
/// status line.
public struct RecentMac: Codable, Sendable, Equatable, Identifiable, Hashable {
    /// Remembered Macs are capped (the picker shows the rest).
    public static let maxRemembered = 8

    /// The Loom device ID, as a string.
    public var id: String
    public var name: String
    public var lastConnected: Date

    public init(id: String, name: String, lastConnected: Date) {
        self.id = id
        self.name = name
        self.lastConnected = lastConnected
    }

    /// `macs` with `mac` moved to the front (replacing an older record of
    /// the same Mac), capped at `maxRemembered`.
    public static func recording(_ mac: RecentMac, in macs: [RecentMac]) -> [RecentMac] {
        let name = mac.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mac.id.isEmpty, !name.isEmpty else { return macs }
        var trimmed = mac
        trimmed.name = String(name.prefix(64))
        return Array(([trimmed] + macs.filter { $0.id != mac.id }).prefix(maxRemembered))
    }
}
