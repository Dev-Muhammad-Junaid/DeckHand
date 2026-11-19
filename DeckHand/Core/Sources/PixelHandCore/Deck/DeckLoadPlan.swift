//
//  DeckLoadPlan.swift
//  PixelHandCore
//
//  What a deck store does at launch, decided from what it found: the
//  stored file (if any) and the chips' data from before decks. Pure, so
//  the iOS `DeckStore` only does the file work.
//

import Foundation

public struct DeckLoadPlan: Equatable, Sendable {
    /// What happened, for the log.
    public enum Source: Equatable, Sendable {
        /// The stored deck, current schema, unchanged.
        case stored
        /// The stored deck, migrated from `fromVersion` or repaired.
        case storedMigrated
        /// First launch with decks: built from the chips' data.
        case legacyChips
        /// First launch, nothing to migrate.
        case fresh
        /// The stored file couldn't be used (damaged, too large, or from a
        /// newer build); it is kept aside and the deck rebuilt from the
        /// chips' data.
        case replaced(DeckMigration.Failure)
    }

    public var document: DeckDocument
    public var source: Source
    /// Write `document` back now.
    public var needsSave: Bool
    /// Keep the stored file aside (under `backupSuffix`) before saving.
    public var backupSuffix: String?

    public static func make(
        storedFile: Data?,
        legacy: () -> DeckMigration.LegacyChips,
        appName: (String) -> String? = { _ in nil }
    ) -> DeckLoadPlan {
        if let storedFile {
            do {
                let document = try DeckMigration.decode(storedFile)
                let unchanged = (try? DeckMigration.encode(document)) == storedFile
                return DeckLoadPlan(document: document, source: unchanged ? .stored : .storedMigrated, needsSave: !unchanged, backupSuffix: nil)
            } catch let failure as DeckMigration.Failure {
                let suffix: String
                if case let .newerVersion(version) = failure {
                    suffix = "schema\(version)"
                } else {
                    suffix = "damaged"
                }
                let rebuilt = fromLegacy(legacy(), appName: appName)
                return DeckLoadPlan(document: rebuilt, source: .replaced(failure), needsSave: true, backupSuffix: suffix)
            } catch {
                let rebuilt = fromLegacy(legacy(), appName: appName)
                return DeckLoadPlan(document: rebuilt, source: .replaced(.unreadable), needsSave: true, backupSuffix: "damaged")
            }
        }
        let chips = legacy()
        if chips.isEmpty {
            return DeckLoadPlan(document: .empty, source: .fresh, needsSave: true, backupSuffix: nil)
        }
        return DeckLoadPlan(document: fromLegacy(chips, appName: appName), source: .legacyChips, needsSave: true, backupSuffix: nil)
    }

    private static func fromLegacy(_ chips: DeckMigration.LegacyChips, appName: (String) -> String?) -> DeckDocument {
        chips.isEmpty ? .empty : DeckMigration.fromLegacy(chips, appName: appName)
    }
}
