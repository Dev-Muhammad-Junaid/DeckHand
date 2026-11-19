//
//  DeckStore.swift
//  DeckHandiOS
//
//  The remote's deck (Deck 2, D1): one `DeckDocument` in Application
//  Support/Deck/deck.json, loaded at launch, migrated and repaired by
//  Core (`DeckLoadPlan`, `DeckMigration`), written atomically after every
//  change. On the first launch with decks it is built from the chips' data
//  (`ShortcutStore`'s `customShortcuts.v1` / `hiddenCuratedShortcuts.v1`
//  and the app grid's pinned and hidden apps). Those keys are left as they
//  were, so an older build still finds its chips.
//
//  No UI here: today's chips read and edit it through `ShortcutStore`;
//  the Deck 2 UI (UX-020) builds on `document` and `update(_:)`.
//

import Combine
import Foundation

@MainActor
final class DeckStore: ObservableObject {
    static let shared = DeckStore()

    /// Always valid (`DeckValidation`).
    @Published private(set) var document: DeckDocument

    /// The keys the chips and the app grid stored before decks.
    enum LegacyKey {
        static let customShortcuts = "customShortcuts.v1"
        static let hiddenCurated = "hiddenCuratedShortcuts.v1"
        /// `StreamDeckGridView`'s `@AppStorage` keys.
        static let pinnedApps = "pinnedBundleIDs"
        static let hiddenApps = "hiddenBundleIDs"
    }

    private let fileURL: URL?

    init(fileURL: URL? = DeckStore.defaultFileURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        let stored = fileURL.flatMap { try? Data(contentsOf: $0) }
        let plan = DeckLoadPlan.make(storedFile: stored, legacy: {
            DeckMigration.LegacyChips.decode(
                customShortcuts: defaults.data(forKey: LegacyKey.customShortcuts),
                hiddenCurated: defaults.data(forKey: LegacyKey.hiddenCurated),
                pinnedApps: defaults.data(forKey: LegacyKey.pinnedApps),
                hiddenApps: defaults.data(forKey: LegacyKey.hiddenApps)
            )
        })
        document = plan.document
        DeckHandLog.app.info("Deck loaded (\(String(describing: plan.source), privacy: .public)): \(plan.document.pages.count, privacy: .public) pages")
        if let suffix = plan.backupSuffix, let fileURL {
            let backup = fileURL.deletingPathExtension().appendingPathExtension("\(suffix).json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
        if plan.needsSave { save() }
    }

    static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Deck", isDirectory: true)
            .appendingPathComponent("deck.json")
    }

    // MARK: - Changes

    /// Applies `change` and saves. The result is repaired first, so the
    /// stored deck is always valid; nothing is written when nothing changed.
    func update(_ change: (inout DeckDocument) -> Void) {
        var draft = document
        change(&draft)
        if !DeckValidation.isValid(draft) { draft = DeckValidation.repaired(draft) }
        guard draft != document else { return }
        document = draft
        save()
    }

    /// Replaces the whole deck (an import, a restored backup).
    func replace(with newDocument: DeckDocument) {
        update { $0 = newDocument }
    }

    // MARK: - File

    private func save() {
        guard let fileURL else { return }
        do {
            let data = try DeckMigration.encode(document)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: fileURL, options: [.atomic])
            #endif
        } catch {
            DeckHandLog.app.error("Deck save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
