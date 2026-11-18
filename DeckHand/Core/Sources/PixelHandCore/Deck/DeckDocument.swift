//
//  DeckDocument.swift
//  PixelHandCore
//
//  The skeleton of the deck model ("Deck 2", release 1.2): pages of keys,
//  each key running one `Action`. Nothing persists or shows this yet; it
//  fixes the shape and its validation so the deck work starts from tested
//  types. The deck lane owns this file.
//

import Foundation

public struct DeckDocument: Codable, Sendable, Equatable {
    /// Bump when the stored shape changes, and add a migration.
    public static let currentVersion = 1

    public var version: Int
    public var pages: [DeckPage]

    public init(version: Int = DeckDocument.currentVersion, pages: [DeckPage]) {
        self.version = version
        self.pages = pages
    }

    /// The page to show when `bundleID` is frontmost: its own page if it
    /// has one, otherwise the first page that isn't tied to an app.
    public func page(forFrontmostApp bundleID: String?) -> DeckPage? {
        if let bundleID, let own = pages.first(where: { $0.appBundleID == bundleID }) {
            return own
        }
        return pages.first { $0.appBundleID == nil }
    }
}

public struct DeckPage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// When set, the page belongs to this app and shows while it is
    /// frontmost.
    public var appBundleID: String?
    public var keys: [DeckKey]

    public init(id: String, title: String, appBundleID: String? = nil, keys: [DeckKey]) {
        self.id = id
        self.title = title
        self.appBundleID = appBundleID
        self.keys = keys
    }
}

public struct DeckKey: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    /// SF Symbol name, if the key shows one.
    public var symbol: String?
    public var action: Action

    public init(id: String, label: String, symbol: String? = nil, action: Action) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.action = action
    }
}

/// Limits and checks for a deck before it is saved or sent.
public enum DeckValidation {
    public static let maxPages = 50
    public static let maxKeysPerPage = 64
    public static let maxLabelLength = 64

    public enum Issue: Equatable, Sendable {
        case unsupportedVersion(Int)
        case tooManyPages(Int)
        case tooManyKeys(pageID: String, count: Int)
        case duplicatePageID(String)
        case duplicateKeyID(String)
        case emptyLabel(keyID: String)
        case labelTooLong(keyID: String)
        case emptyChord(keyID: String)
        case tooManyChordKeys(keyID: String)
        /// Dialog buttons only exist while their dialog is open, so a saved
        /// key can't press one.
        case contextActionNotStorable(keyID: String)
    }

    /// Every problem with `document`; empty when it is valid.
    public static func issues(in document: DeckDocument) -> [Issue] {
        var issues: [Issue] = []
        if document.version != DeckDocument.currentVersion {
            issues.append(.unsupportedVersion(document.version))
        }
        if document.pages.count > maxPages {
            issues.append(.tooManyPages(document.pages.count))
        }
        var pageIDs = Set<String>()
        var keyIDs = Set<String>()
        for page in document.pages {
            if !pageIDs.insert(page.id).inserted { issues.append(.duplicatePageID(page.id)) }
            if page.keys.count > maxKeysPerPage {
                issues.append(.tooManyKeys(pageID: page.id, count: page.keys.count))
            }
            for key in page.keys {
                if !keyIDs.insert(key.id).inserted { issues.append(.duplicateKeyID(key.id)) }
                let label = key.label.trimmingCharacters(in: .whitespacesAndNewlines)
                if label.isEmpty { issues.append(.emptyLabel(keyID: key.id)) }
                if key.label.count > maxLabelLength { issues.append(.labelTooLong(keyID: key.id)) }
                switch key.action {
                case let .shortcut(keys), let .appShortcut(_, keys):
                    if keys.isEmpty { issues.append(.emptyChord(keyID: key.id)) }
                    if keys.count > ProtocolLimits.maxChordKeys { issues.append(.tooManyChordKeys(keyID: key.id)) }
                case .contextAction:
                    issues.append(.contextActionNotStorable(keyID: key.id))
                case .launchApp, .system, .media:
                    break
                }
            }
        }
        return issues
    }
}
