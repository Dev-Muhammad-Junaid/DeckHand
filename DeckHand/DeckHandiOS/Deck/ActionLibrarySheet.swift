//
//  ActionLibrarySheet.swift
//  DeckHandiOS – Deck
//
//  The action library (UX-020, D3): what a new key can do. "Make your own"
//  lists every kind of action a key can store (key press, key press in an
//  app, menu command, open an app, Mac action, media key, Mac Shortcut,
//  sequence) and opens the inspector to fill it in. Below: the front app's
//  presets, its imported menu items as menu commands, the Mac's actions,
//  media keys and the Mac's apps, each added in one tap.
//

import PixelHandCore
import SwiftUI

struct ActionLibrarySheet: View {
    let frontBundleID: String?
    let apps: [InstalledAppInfo]
    /// The new key, and whether the inspector should open to finish it.
    let onPick: (PixelHandCore.DeckKey, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shortcuts = ShortcutStore.shared
    @State private var query = ""

    private var appsByID: [String: InstalledAppInfo] { InstalledAppInfo.byBundleID(apps) }
    private var frontName: String? { frontBundleID.flatMap { appsByID[$0]?.displayName } }
    private func appName(_ bundleID: String) -> String? { appsByID[bundleID]?.displayName }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        ForEach(ActionKind.allCases) { kind in
                            row(glyph: kind.glyph, title: kind.title, subtitle: kind.help, accessory: "chevron.right") {
                                let action = kind.template(frontBundleID: frontBundleID)
                                onPick(.draft(for: action, appName: appName), true)
                            }
                        }
                    } header: {
                        Text("Make your own")
                    }
                }
                if !menuPresets.isEmpty {
                    Section {
                        ForEach(menuPresets) { preset in
                            presetRow(preset)
                        }
                    } header: {
                        Text("\(frontName ?? "App") menu commands")
                    } footer: {
                        Text("Picks the menu item by name, so it still works if you change its shortcut.")
                    }
                }
                ForEach(ActionLibrary.filter(ActionLibrary.sections(frontBundleID: frontBundleID, frontAppName: frontName), query: query)) { section in
                    Section(section.title) {
                        ForEach(section.presets) { preset in
                            presetRow(preset)
                        }
                    }
                }
                if !filteredApps.isEmpty {
                    Section("Open an app") {
                        ForEach(filteredApps) { app in
                            Button {
                                GestureHaptic.light.trigger()
                                onPick(.draft(for: .launchApp(bundleID: app.bundleID), label: app.displayName), false)
                            } label: {
                                HStack(spacing: PixelHandTheme.Space.md) {
                                    appIcon(app)
                                    Text(app.displayName)
                                        .foregroundStyle(PixelHandTheme.ink)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(PixelHandTheme.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .accessibilityLabel("Open \(app.displayName)")
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search actions and apps")
            .navigationTitle("Add Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// The front app's imported chips whose names carry a menu path
    /// ("File › New Tab"), as menu commands.
    private var menuPresets: [ActionPreset] {
        guard let frontBundleID else { return [] }
        let presets = shortcuts.bindings(for: frontBundleID).compactMap { binding -> ActionPreset? in
            let path = MenuPath.path(fromDisplayName: binding.displayName)
                ?? binding.category.map { [$0, binding.displayName] }
            guard let path else { return nil }
            return ActionPreset(
                id: "menu." + binding.id,
                title: path.joined(separator: " › "),
                glyphName: "deck",
                action: .menuCommand(bundleID: frontBundleID, path: path)
            )
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return presets }
        return presets.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var filteredApps: [InstalledAppInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let sorted = apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.displayName.localizedCaseInsensitiveContains(q) }
    }

    private func presetRow(_ preset: ActionPreset) -> some View {
        row(glyph: preset.glyph, title: preset.title, subtitle: preset.action.chordText ?? preset.action.summary(appName: appName), accessory: "plus.circle.fill") {
            let label = preset.action.bundleID != nil && preset.title.contains(" › ")
                ? preset.title.components(separatedBy: " › ").last
                : preset.title
            onPick(.draft(for: preset.action, label: label, appName: appName), false)
        }
    }

    private func row(glyph: GlyphBitmap, title: String, subtitle: String, accessory: String, action: @escaping () -> Void) -> some View {
        Button {
            GestureHaptic.light.trigger()
            action()
        } label: {
            HStack(spacing: PixelHandTheme.Space.md) {
                PHGlyph(glyph: glyph, pitch: PixelPitch.chip)
                    .foregroundStyle(PixelHandTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(PixelHandTheme.accentTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(PixelHandTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PixelHandTheme.ink2)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: accessory)
                    .foregroundStyle(accessory == "chevron.right" ? PixelHandTheme.ink3 : PixelHandTheme.accent)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func appIcon(_ app: InstalledAppInfo) -> some View {
        if let icon = DeckAppIcons.image(for: app.bundleID, in: appsByID) {
            icon.resizable().interpolation(.high).scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            PHGlyph(glyph: PixelGlyphs.mac, pitch: PixelPitch.chip)
                .foregroundStyle(PixelHandTheme.ink2)
                .frame(width: 36, height: 36)
                .background(PixelHandTheme.fill2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}
