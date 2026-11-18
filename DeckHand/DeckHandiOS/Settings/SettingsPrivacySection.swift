//
//  SettingsPrivacySection.swift
//  DeckHandiOS
//
//  Settings › Privacy: crash reports.
//  Split out of SettingsView.swift (PH-010).
//

import SwiftUI

struct SettingsPrivacySection: View {
    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        Section {
            Toggle("Share crash reports", isOn: $settings.shareCrashReports)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Sends crash, hang and performance reports to the developer so problems can be fixed. They include the device model, system version and what the app was doing — never your screen, your captures, your device names or who you are. Applies to this device; the Mac has its own switch.")
        }
    }
}
