//
//  SettingsPrivacySection.swift
//  DeckHandiOS
//
//  Settings › Privacy: crash reports.
//

import SwiftUI

struct SettingsPrivacySection: View {
    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        Section {
            SettingsToggle("Share crash reports", glyph: PixelGlyphs.send, isOn: $settings.shareCrashReports)
        } header: {
            SettingsSectionHeader("Privacy", glyph: PixelGlyphs.lock)
        } footer: {
            Text("Reports include the device model, system version and what the app was doing, never your screen, captures, device names or who you are. The Mac has its own switch.")
        }
    }
}
