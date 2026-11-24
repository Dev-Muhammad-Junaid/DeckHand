//
//  SettingsAboutSection.swift
//  DeckHandiOS
//
//  Settings › About: replay the welcome tour. The version line sits under
//  the last section in dot-matrix (`SettingsVersionLine`).
//

import SwiftUI

struct SettingsAboutSection: View {
    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Section {
            Button {
                settings.hasCompletedOnboarding = false
                dismiss()
            } label: {
                SettingsRow("Show the welcome tour again", glyph: PixelGlyphs.iPhone)
            }
            .buttonStyle(.plain)
        } header: {
            SettingsSectionHeader("About", glyph: PixelGlyphs.ask)
        }
    }
}
