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
            Toggle(isOn: $settings.shareCrashReports) {
                SettingsRow("Share crash reports", glyph: PixelGlyphs.send)
            }
        } header: {
            SettingsSectionHeader("Privacy", glyph: PixelGlyphs.lock)
        } footer: {
            Text("Sends crash, hang and performance reports to the developer so problems can be fixed. They include the device model, system version and what the app was doing — never your screen, your captures, your device names or who you are. Applies to this device; the Mac has its own switch.")
        }
    }
}
