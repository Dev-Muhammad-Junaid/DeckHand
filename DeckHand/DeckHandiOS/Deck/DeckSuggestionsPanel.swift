//
//  DeckSuggestionsPanel.swift
//  DeckHandiOS – Deck
//
//  The suggestions panel under the deck grid (UX-021, board "Deck"): an
//  `accentTint` panel titled "3 suggestions from Xcode’s menus" with
//  **Keep all**, and the suggestions as ghost keys; tap one to keep it,
//  long-press to hide it. After a keep the panel says "Kept 3 keys" with
//  Undo (the deck editor's history, `DeckSurfaceModel`). Pro, like decks:
//  the surface shows it only when decks are unlocked.
//

import PixelHandCore
import SwiftUI

struct DeckSuggestionsPanel: View {
    /// The app the suggestions are for.
    let bundleID: String
    let appName: String
    /// Whether that app is the Mac's front app. Menus load on their own
    /// only then (the Mac brings the app forward to read them).
    let isFrontApp: Bool
    let sender: TrackpadSender
    let apps: [String: InstalledAppInfo]
    let grid: DeckGrid
    let asRows: Bool

    @ObservedObject private var suggestions = DeckSuggestionsModel.shared
    @ObservedObject private var deck = DeckSurfaceModel.shared
    @ObservedObject private var store = DeckStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var existing: [PixelHandCore.DeckKey] { store.document.existingKeys(forApp: bundleID) }
    private var visible: [DeckSuggestion] { suggestions.visible(for: bundleID, existing: existing) }

    var body: some View {
        Group {
            if suggestions.isClosed(bundleID) {
                EmptyView()
            } else {
                panel
            }
        }
        .onAppear(perform: autoload)
        .onChange(of: bundleID) { _, _ in autoload() }
        .onChange(of: isFrontApp) { _, _ in autoload() }
    }

    private func autoload() {
        guard !suggestions.isClosed(bundleID) else { return }
        // Fresh menus show for any app; asking the Mac only for the front app.
        if isFrontApp || suggestions.hasFreshMenus(for: bundleID) {
            suggestions.load(bundleID: bundleID, appName: appName, existing: existing, sender: sender)
        }
    }

    @ViewBuilder
    private var panel: some View {
        let shown = visible
        let note = suggestions.keptNote.flatMap { $0.bundleID == bundleID && $0.undoCount == deck.history.undoCount && deck.history.canUndo ? $0 : nil }
        let phase = suggestions.state(for: bundleID).phase
        if phase == .ready && shown.isEmpty && note == nil {
            // Nothing new: a quiet line, not a panel.
            Text(DeckSuggestionCopy.nothingNew(appName: appName))
                .font(.caption)
                .foregroundStyle(PixelHandTheme.ink3)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, PixelHandTheme.Space.xs)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                header(shown: shown, phase: phase, note: note)
                if phase == .ready && !shown.isEmpty {
                    keys(shown)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelHandTheme.accentTint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .animation(PixelHandMotion.reduced(PixelHandMotion.standard, reduceMotion: reduceMotion), value: shown.map(\.id))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Suggestions")
            .accessibilityIdentifier("ph.deck.suggestions")
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(shown: [DeckSuggestion], phase: DeckSuggestionsModel.Phase, note: DeckSuggestionsModel.KeptNote?) -> some View {
        HStack(spacing: 8) {
            PHGlyph(glyph: PixelGlyphs.ask, pitch: PixelPitch.chip)
                .foregroundStyle(PixelHandTheme.accentInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(shown: shown, phase: phase, note: note))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.accentInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = detail(phase: phase, shown: shown) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(PixelHandTheme.accentInk.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            trailing(shown: shown, phase: phase, note: note)
            Button {
                suggestions.close(bundleID)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PixelHandTheme.accentInk.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close suggestions")
            .phosphorFocusable(cornerRadius: 15)
            .padding(.trailing, -8)
        }
    }

    private func title(shown: [DeckSuggestion], phase: DeckSuggestionsModel.Phase, note: DeckSuggestionsModel.KeptNote?) -> String {
        switch phase {
        case .idle: return "Suggest keys from \(appName)’s menus"
        case .reading: return DeckSuggestionCopy.reading(appName: appName)
        case .failed: return DeckSuggestionCopy.noAnswer
        case .ready:
            if shown.isEmpty, let note { return DeckSuggestionCopy.kept(count: note.count) }
            return DeckSuggestionCopy.title(count: shown.count, appName: appName)
        }
    }

    private func detail(phase: DeckSuggestionsModel.Phase, shown: [DeckSuggestion]) -> String? {
        guard phase == .ready, !shown.isEmpty else { return nil }
        switch suggestions.state(for: bundleID).ranking {
        case .refining: return "Sorting on this device…"
        case .onDevice: return "Sorted on this device by Apple Intelligence"
        case .fallback: return nil
        }
    }

    @ViewBuilder
    private func trailing(shown: [DeckSuggestion], phase: DeckSuggestionsModel.Phase, note: DeckSuggestionsModel.KeptNote?) -> some View {
        switch phase {
        case .idle, .failed:
            Button(phase == .failed ? "Try again" : "Suggest") {
                suggestions.load(bundleID: bundleID, appName: appName, existing: existing, sender: sender, force: phase == .failed)
            }
            .buttonStyle(.ph(.tint, size: .small))
            .accessibilityHint(isFrontApp ? "" : "Brings \(appName) forward on the Mac to read its menus")
        case .reading:
            ProgressView()
                .tint(PixelHandTheme.accentInk)
                .accessibilityLabel(DeckSuggestionCopy.reading(appName: appName))
        case .ready:
            if let note {
                Button("Undo") { undoKeep(note) }
                    .buttonStyle(.ph(.tint, size: .small))
                    .accessibilityLabel("Undo, \(DeckSuggestionCopy.kept(count: note.count))")
            }
            if !shown.isEmpty {
                Button("Keep all") { keep(shown.map { DeckShownKey(key: $0.key, source: .suggested) }) }
                    .buttonStyle(.ph(.tint, size: .small))
                    .accessibilityHint("Adds all \(shown.count) to \(appName)’s page")
            }
        }
    }

    // MARK: Keys

    @ViewBuilder
    private func keys(_ shown: [DeckSuggestion]) -> some View {
        let keys = shown.map { DeckShownKey(key: $0.key, source: .suggested) }
        if asRows {
            VStack(spacing: PixelHandTheme.Space.sm) {
                ForEach(keys) { ghostRow($0) }
            }
        } else {
            // The panel's 12 pt insets come out of the grid's width.
            let columns = max(1, grid.columns)
            let available: Double = grid.contentWidth - 24 - Double(columns - 1) * grid.gutter
            let side = CGFloat(max(44, (available / Double(columns)).rounded(.down)))
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(side), spacing: grid.gutter), count: columns),
                alignment: .leading,
                spacing: grid.gutter
            ) {
                ForEach(keys) { ghostKey($0, size: side) }
            }
        }
    }

    private func ghostKey(_ shown: DeckShownKey, size: CGFloat) -> some View {
        let face = DeckKeyFace(key: shown.key, apps: apps)
        return DeckKey(title: face.title, glyph: face.glyph, chord: face.chord, size: size, kind: .ghost, icon: face.icon) {
            keep([shown])
        }
        .accessibilityLabel("Suggested: \(face.title)")
        .accessibilityHint("Keeps this key on \(appName)’s page")
        .contextMenu { ghostMenu(shown) }
    }

    private func ghostRow(_ shown: DeckShownKey) -> some View {
        let face = DeckKeyFace(key: shown.key, apps: apps)
        return DeckKeyRow(title: face.title, glyph: face.glyph, chord: face.chord, icon: face.icon) {
            keep([shown])
        }
        .opacity(0.85)
        .overlay {
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
                .strokeBorder(PixelHandTheme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Suggested: \(face.title)")
        .accessibilityHint("Keeps this key on \(appName)’s page")
        .contextMenu { ghostMenu(shown) }
    }

    @ViewBuilder
    private func ghostMenu(_ shown: DeckShownKey) -> some View {
        Button {
            keep([shown])
        } label: {
            Label("Keep", systemImage: "plus.square")
        }
        Button {
            suggestions.hide(shown.id)
        } label: {
            Label("Hide suggestion", systemImage: "eye.slash")
        }
    }

    // MARK: Keep and undo

    private func keep(_ shown: [DeckShownKey]) {
        var added = 0
        let keys = shown.map(\.key)
        let title = appName
        deck.edit { added = $0.keepSuggestions(keys, forApp: bundleID, title: title) }
        guard added > 0 else { return }
        GestureHaptic.light.trigger()
        suggestions.noteKept(count: added, bundleID: bundleID, undoCount: deck.history.undoCount)
    }

    private func undoKeep(_ note: DeckSuggestionsModel.KeptNote) {
        guard deck.history.undoCount == note.undoCount else { return }
        deck.undo()
        suggestions.keptNote = nil
    }
}
