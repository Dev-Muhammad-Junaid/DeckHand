//
//  DeckValidation.swift
//  PixelHandCore
//
//  Limits and checks for a deck before it is used, saved or (later) synced
//  to another device. `issues(in:)` lists every problem; `repaired(_:)`
//  keeps what is good, so one bad key never costs the user their deck.
//

import Foundation

public enum DeckValidation {
    /// Largest stored document `DeckMigration` will decode.
    public static let maxDocumentBytes = 2 * 1024 * 1024
    public static let maxPages = 50
    public static let maxKeysPerPage = 64
    public static let maxLabelLength = 64
    public static let maxTitleLength = 64
    public static let maxIDBytes = 512
    public static let maxSymbolNameBytes = 128
    public static let maxGlyphIDBytes = 64
    public static let maxTintBytes = 32
    public static let maxCategoryBytes = 128
    public static let maxHiddenCuratedPerPage = 500
    public static let maxHiddenApps = 2_000

    public enum Issue: Equatable, Sendable {
        case unsupportedVersion(Int)
        case tooManyPages(Int)
        case tooManyKeys(pageID: String, count: Int)
        case badPageID(String)
        case duplicatePageID(String)
        case badPageTitle(pageID: String)
        case badPageKind(pageID: String)
        /// A second Home, Context or Shortcuts page, or a second page for
        /// the same app.
        case duplicatePageKind(pageID: String)
        case tooManyHiddenCurated(pageID: String)
        case badKeyID(String)
        case duplicateKeyID(String)
        case emptyLabel(keyID: String)
        case labelTooLong(keyID: String)
        case badGlyph(keyID: String)
        case badTint(keyID: String)
        case badCategory(keyID: String)
        case badAction(keyID: String, ActionValidation.Issue)
        case unknownPinnedPage(String)
        case tooManyHiddenApps
    }

    /// Every problem with `document`; empty when it is valid.
    public static func issues(in document: DeckDocument) -> [Issue] {
        var issues: [Issue] = []
        if document.schemaVersion != DeckDocument.currentVersion {
            issues.append(.unsupportedVersion(document.schemaVersion))
        }
        if document.pages.count > maxPages {
            issues.append(.tooManyPages(document.pages.count))
        }
        if document.hiddenAppBundleIDs.count > maxHiddenApps
            || !document.hiddenAppBundleIDs.allSatisfy(ActionValidation.isBundleID) {
            issues.append(.tooManyHiddenApps)
        }
        var pageIDs = Set<String>()
        var keyIDs = Set<String>()
        var kinds = Set<DeckPageKind>()
        for page in document.pages {
            issues += pageIssues(page)
            if !pageIDs.insert(page.id).inserted { issues.append(.duplicatePageID(page.id)) }
            if page.kind != .custom, !kinds.insert(page.kind).inserted {
                issues.append(.duplicatePageKind(pageID: page.id))
            }
            if page.keys.count > maxKeysPerPage {
                issues.append(.tooManyKeys(pageID: page.id, count: page.keys.count))
            }
            for key in page.keys {
                if !keyIDs.insert(key.id).inserted { issues.append(.duplicateKeyID(key.id)) }
                issues += keyIssues(key)
            }
        }
        if let pinned = document.pinnedPageID, !pageIDs.contains(pinned) {
            issues.append(.unknownPinnedPage(pinned))
        }
        return issues
    }

    public static func isValid(_ document: DeckDocument) -> Bool {
        issues(in: document).isEmpty
    }

    /// Problems with one page itself (not its keys, nor duplicates).
    public static func pageIssues(_ page: DeckPage) -> [Issue] {
        var issues: [Issue] = []
        if !isID(page.id) { issues.append(.badPageID(page.id)) }
        if page.title.count > maxTitleLength || page.title.utf8.count > maxTitleLength * 4
            || page.title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            issues.append(.badPageTitle(pageID: page.id))
        }
        if case let .app(bundleID) = page.kind, !ActionValidation.isBundleID(bundleID) {
            issues.append(.badPageKind(pageID: page.id))
        }
        if page.hiddenCuratedIDs.count > maxHiddenCuratedPerPage || !page.hiddenCuratedIDs.allSatisfy(isID) {
            issues.append(.tooManyHiddenCurated(pageID: page.id))
        }
        return issues
    }

    /// Problems with one key itself (not duplicates).
    public static func keyIssues(_ key: DeckKey) -> [Issue] {
        var issues: [Issue] = []
        if !isID(key.id) { issues.append(.badKeyID(key.id)) }
        let label = key.appearance.label
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.emptyLabel(keyID: key.id)) }
        if label.count > maxLabelLength || label.utf8.count > maxLabelLength * 4 {
            issues.append(.labelTooLong(keyID: key.id))
        }
        if let glyph = key.appearance.glyph, !isValid(glyph) { issues.append(.badGlyph(keyID: key.id)) }
        if let tint = key.appearance.tint, !isToken(tint, maxBytes: maxTintBytes) { issues.append(.badTint(keyID: key.id)) }
        if let category = key.category, !ActionValidation.isPlainText(category, maxBytes: maxCategoryBytes) {
            issues.append(.badCategory(keyID: key.id))
        }
        for issue in ActionValidation.issues(in: key.action, storable: true) {
            issues.append(.badAction(keyID: key.id, issue))
        }
        return issues
    }

    public static func isValid(_ glyph: KeyGlyph) -> Bool {
        switch glyph {
        case let .symbol(name): isToken(name, maxBytes: maxSymbolNameBytes)
        case let .pixel(id): isToken(id, maxBytes: maxGlyphIDBytes)
        case let .custom(bitmap): bitmap.isWellFormed
        case let .appIcon(bundleID): ActionValidation.isBundleID(bundleID)
        }
    }

    /// A page or key ID: 1…512 bytes, no control characters.
    public static func isID(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= maxIDBytes
            && !s.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// A symbol, glyph or palette name: ASCII letters, digits, `.`, `-`, `_`.
    public static func isToken(_ s: String, maxBytes: Int) -> Bool {
        guard !s.isEmpty, s.utf8.count <= maxBytes else { return false }
        return s.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" || scalar == "_")
        }
    }

    // MARK: - Repair

    /// `text` cut to `maxLength` characters and `maxLength * 4` bytes.
    static func trimmed(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength || text.utf8.count > maxLength * 4 else { return text }
        var out = String(text.prefix(maxLength))
        while out.utf8.count > maxLength * 4 { out.removeLast() }
        return out
    }

    /// `document` with everything invalid dropped or trimmed: bad pages and
    /// keys go, later duplicates go, lists are cut to their limits, a bad
    /// glyph or tint falls back to none, an unknown pin is cleared. The
    /// result always passes `issues(in:)` (bar `unsupportedVersion`, which
    /// it sets to current).
    public static func repaired(_ document: DeckDocument) -> DeckDocument {
        var pageIDs = Set<String>()
        var keyIDs = Set<String>()
        var kinds = Set<DeckPageKind>()
        var pages: [DeckPage] = []
        for var page in document.pages {
            guard pages.count < maxPages else { break }
            page.hiddenCuratedIDs = Array(page.hiddenCuratedIDs.filter(isID).prefix(maxHiddenCuratedPerPage))
            page.title = trimmed(
                String(String.UnicodeScalarView(page.title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })),
                maxLength: maxTitleLength
            )
            guard pageIssues(page).isEmpty, !pageIDs.contains(page.id) else { continue }
            if page.kind != .custom {
                guard !kinds.contains(page.kind) else { continue }
                kinds.insert(page.kind)
            }
            pageIDs.insert(page.id)
            var keys: [DeckKey] = []
            for var key in page.keys {
                guard keys.count < maxKeysPerPage else { break }
                if let glyph = key.appearance.glyph, !isValid(glyph) { key.appearance.glyph = nil }
                if let tint = key.appearance.tint, !isToken(tint, maxBytes: maxTintBytes) { key.appearance.tint = nil }
                if let category = key.category, !ActionValidation.isPlainText(category, maxBytes: maxCategoryBytes) { key.category = nil }
                key.appearance.label = trimmed(key.appearance.label, maxLength: maxLabelLength)
                guard keyIssues(key).isEmpty, !keyIDs.contains(key.id) else { continue }
                keyIDs.insert(key.id)
                keys.append(key)
            }
            page.keys = keys
            pages.append(page)
        }
        return DeckDocument(
            schemaVersion: DeckDocument.currentVersion,
            pages: pages,
            followFrontApp: document.followFrontApp,
            pinnedPageID: document.pinnedPageID.flatMap { pageIDs.contains($0) ? $0 : nil },
            hiddenAppBundleIDs: Array(document.hiddenAppBundleIDs.filter(ActionValidation.isBundleID).prefix(maxHiddenApps))
        )
    }
}
