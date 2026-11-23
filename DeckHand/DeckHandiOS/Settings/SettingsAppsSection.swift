//
//  SettingsAppsSection.swift
//  DeckHandiOS
//
//  Settings › Apps: undo hidden apps. Only shows once something is hidden.
//

import SwiftUI

struct SettingsAppsSection: View {
    @EnvironmentObject private var settings: DeckHandSettings

    /// Only appears once something is hidden. Hiding happens from a context
    /// menu in the Apps grid, which has no way to undo itself.
    @ViewBuilder
    var body: some View {
        let hidden = settings.hiddenAppBundleIDs
        if !hidden.isEmpty {
            Section {
                SettingsRow("Hidden apps", glyph: PixelGlyphs.deck) {
                    SettingsValueText("\(hidden.count)")
                }
                Button("Show hidden apps") {
                    settings.unhideAllApps()
                }
                .foregroundStyle(PixelHandTheme.accent)
            } header: {
                SettingsSectionHeader("Apps", glyph: PixelGlyphs.deck)
            } footer: {
                Text("Hidden apps are removed from the Apps grid and its search results. This puts them all back.")
            }
        }
    }
}
