//
//  SettingsAppearanceSection.swift
//  DeckHandiOS
//
//  Settings › Appearance: theme.
//

import SwiftUI

struct SettingsAppearanceSection: View {
    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        Section {
            SettingBlock("Theme") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        } header: {
            SettingsSectionHeader("Appearance", glyph: PixelGlyphs.screen)
        } footer: {
            Text("Applies to the control screens. The Mac picker stays dark to match the app icon.")
        }
    }
}
