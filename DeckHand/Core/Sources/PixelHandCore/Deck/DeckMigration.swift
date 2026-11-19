//
//  DeckMigration.swift
//  PixelHandCore
//
//  Reads every stored deck shape into the current `DeckDocument`:
//
//  - schema 2 (current) as it is;
//  - schema 1, the skeleton (`version`, pages with `appBundleID`, keys
//    with `label` + `symbol`);
//  - the chips' data from before decks existed: `ShortcutStore`'s
//    `customShortcuts.v1` (custom and imported shortcuts per app) and
//    `hiddenCuratedShortcuts.v1` (hidden presets per app), plus the app
//    grid's pinned and hidden apps.
//
//  Every result goes through `DeckValidation.repaired`, so what comes out
//  is always valid and bounded, whatever was stored.
//

import Foundation

public enum DeckMigration {
    public enum Failure: Error, Equatable {
        /// Larger than `DeckValidation.maxDocumentBytes`.
        case tooLarge(bytes: Int)
        /// Not JSON, or not any deck shape this build knows.
        case unreadable
        /// Written by a newer build. The caller keeps the file and doesn't
        /// overwrite it with an older shape.
        case newerVersion(Int)
    }

    // MARK: - Stored document

    /// Decodes a stored deck of any known schema, migrated to the current
    /// one and repaired.
    public static func decode(_ data: Data) throws -> DeckDocument {
        guard data.count <= DeckValidation.maxDocumentBytes else {
            throw Failure.tooLarge(bytes: data.count)
        }
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else {
            throw Failure.unreadable
        }
        let version = probe.schemaVersion ?? probe.version ?? 0
        switch version {
        case DeckDocument.currentVersion:
            guard let document = try? decoder.decode(DeckDocument.self, from: data) else { throw Failure.unreadable }
            return DeckValidation.repaired(document)
        case 1:
            guard let v1 = try? decoder.decode(V1Document.self, from: data) else { throw Failure.unreadable }
            return DeckValidation.repaired(v1.migrated())
        case let newer where newer > DeckDocument.currentVersion:
            throw Failure.newerVersion(newer)
        default:
            throw Failure.unreadable
        }
    }

    /// Encodes `document` for storage: sorted keys, so an unchanged deck
    /// writes the same bytes.
    public static func encode(_ document: DeckDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int?
        var version: Int?
    }

    // MARK: - Schema 1

    private struct V1Document: Decodable {
        var version: Int
        var pages: [V1Page]

        func migrated() -> DeckDocument {
            var sawGeneral = false
            let pages = pages.map { page -> DeckPage in
                let kind: DeckPageKind
                if let bundleID = page.appBundleID {
                    kind = .app(bundleID: bundleID)
                } else if !sawGeneral {
                    // The first page not tied to an app was the one shown
                    // by default: it becomes Home.
                    sawGeneral = true
                    kind = .home
                } else {
                    kind = .custom
                }
                return DeckPage(id: page.id, title: page.title, kind: kind, keys: page.keys.map { key in
                    DeckKey(id: key.id, label: key.label, symbol: key.symbol, action: key.action)
                })
            }
            return DeckDocument(pages: pages)
        }
    }

    private struct V1Page: Decodable {
        var id: String
        var title: String
        var appBundleID: String?
        var keys: [V1Key]
    }

    private struct V1Key: Decodable {
        var id: String
        var label: String
        var symbol: String?
        var action: Action
    }

    // MARK: - Chips (before decks)

    /// What the app stored for chips and the app grid before decks.
    public struct LegacyChips: Sendable, Equatable {
        /// `customShortcuts.v1`: custom and imported shortcuts per app.
        public var customBindings: [String: [AppShortcutBinding]]
        /// `hiddenCuratedShortcuts.v1`: hidden preset IDs per app.
        public var hiddenCuratedIDs: [String: [String]]
        /// The app grid's `pinnedBundleIDs`.
        public var pinnedApps: [String]
        /// The app grid's `hiddenBundleIDs`.
        public var hiddenApps: [String]

        public init(
            customBindings: [String: [AppShortcutBinding]] = [:],
            hiddenCuratedIDs: [String: [String]] = [:],
            pinnedApps: [String] = [],
            hiddenApps: [String] = []
        ) {
            self.customBindings = customBindings
            self.hiddenCuratedIDs = hiddenCuratedIDs
            self.pinnedApps = pinnedApps
            self.hiddenApps = hiddenApps
        }

        /// Reads the stored values (any may be missing or damaged; a
        /// damaged one counts as empty).
        public static func decode(customShortcuts: Data?, hiddenCurated: Data?, pinnedApps: Data?, hiddenApps: Data?) -> LegacyChips {
            let decoder = JSONDecoder()
            func read<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
                guard let data, data.count <= DeckValidation.maxDocumentBytes else { return nil }
                return try? decoder.decode(type, from: data)
            }
            return LegacyChips(
                customBindings: read([String: [AppShortcutBinding]].self, customShortcuts) ?? [:],
                hiddenCuratedIDs: read([String: [String]].self, hiddenCurated) ?? [:],
                pinnedApps: read([String].self, pinnedApps) ?? [],
                hiddenApps: read([String].self, hiddenApps) ?? []
            )
        }

        public var isEmpty: Bool {
            customBindings.values.allSatisfy(\.isEmpty) && hiddenCuratedIDs.values.allSatisfy(\.isEmpty)
                && pinnedApps.isEmpty && hiddenApps.isEmpty
        }
    }

    /// The deck the chips' data becomes: a Home page launching the pinned
    /// apps, and one app page per app with custom shortcuts or hidden
    /// presets (curated presets stay out of storage; only the hidden ones
    /// are recorded). `appName` names an app for page titles and key
    /// labels when the caller knows it. Deterministic: apps are sorted.
    public static func fromLegacy(_ legacy: LegacyChips, appName: (String) -> String? = { _ in nil }) -> DeckDocument {
        func name(_ bundleID: String) -> String {
            if let known = appName(bundleID), !known.isEmpty { return known }
            return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        }

        let pinned = Array(Set(legacy.pinnedApps)).sorted()
        let home = DeckPage(id: DeckPage.homeID, title: "Home", kind: .home, keys: pinned.map { bundleID in
            DeckKey(
                id: "launch.\(bundleID)",
                appearance: KeyAppearance(label: name(bundleID), glyph: .appIcon(bundleID: bundleID)),
                action: .launchApp(bundleID: bundleID)
            )
        })

        let apps = Set(legacy.customBindings.keys).union(legacy.hiddenCuratedIDs.keys).sorted()
        var pages = [home]
        for bundleID in apps {
            let keys = (legacy.customBindings[bundleID] ?? [])
                .filter { !$0.isCurated && $0.bundleID == bundleID }
                .map(DeckKey.init(binding:))
            let hidden = Array(Set(legacy.hiddenCuratedIDs[bundleID] ?? [])).sorted()
            guard !keys.isEmpty || !hidden.isEmpty else { continue }
            pages.append(DeckPage(
                id: DeckPage.appPageID(for: bundleID),
                title: name(bundleID),
                kind: .app(bundleID: bundleID),
                keys: keys,
                hiddenCuratedIDs: hidden
            ))
        }
        let document = DeckDocument(pages: pages, hiddenAppBundleIDs: Array(Set(legacy.hiddenApps)).sorted())
        return DeckValidation.repaired(document)
    }
}
