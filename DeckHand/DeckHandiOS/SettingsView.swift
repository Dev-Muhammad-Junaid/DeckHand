//
//  SettingsView.swift
//  DeckHandiOS
//
//  The remote's preferences. Grouped so the two costly sections — mirror and
//  pointer — read as the ones worth touching, with footers that say what a
//  choice actually costs rather than just what it does.
//
//  Segmented controls carry their own titles: a `Picker` in a `Form` drops
//  its label under `.segmented`, which leaves bare options like "Off / Light
//  / Full" floating with nothing to say what they belong to.
//
//  Each section is its own view in Settings/.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SettingsMirrorSection()
                SettingsPointerSection()
                SettingsCaptureSection()
                SettingsAppsSection()
                SettingsAppearanceSection()
                SettingsConnectionSection()
                SettingsPairingSection()
                SettingsPrivacySection()
                SettingsAboutSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(OpaqueSettingsBar())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Applied here as well as at the app root: a sheet gets its own
        // presentation host, so without this the appearance change wouldn't
        // reach the very screen you changed it on until it was reopened.
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}
