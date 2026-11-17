//
//  SettingsAboutSection.swift
//  DeckHandiOS
//
//  Settings › About: replay the welcome tour.
//  Split out of SettingsView.swift (PH-010).
//

import SwiftUI

struct SettingsAboutSection: View {
    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Section {
            Button("Show the welcome tour again") {
                settings.hasCompletedOnboarding = false
                dismiss()
            }
        } footer: {
            Text("Rows marked \(Text("Not available").italic()) are visible so you know they're planned, but they do nothing yet.")
        }
    }
}
