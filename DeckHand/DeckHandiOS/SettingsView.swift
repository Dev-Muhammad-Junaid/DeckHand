//
//  SettingsView.swift
//  DeckHandiOS
//
//  The remote's preferences, in the Pixel Hand design system (board
//  `v2Settings`, `07-Polish-Spec.md` §7 "Settings"): a Geist title, the
//  connected Mac's section first, grouped `raised` sections on the canvas,
//  navy glyph tiles leading rows, trailing values aligned, and the version
//  line in dot-matrix at the foot.
//
//  Segmented controls carry their own titles (`SettingBlock`): a `Picker` in
//  a `Form` drops its label under `.segmented`.
//
//  Each section is its own view in Settings/; the list styling is applied
//  here, so section files only opt into headers and row icons.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    SettingsMacSection()
                    SettingsMirrorSection()
                    SettingsPointerSection()
                    SettingsCaptureSection()
                    SettingsAppsSection()
                    SettingsAppearanceSection()
                    SettingsConnectionSection()
                    SettingsPairingSection()
                    SettingsMultiMacSection() // Multi-Mac lane
                    SettingsSubscriptionSection()
                    SettingsPrivacySection()
                    SettingsAboutSection()
                }
                .phSettingsSection()

                Section {
                    SettingsVersionLine()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .phSettingsList()
            .accessibilityIdentifier("ph.settings")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(OpaqueSettingsBar())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.phDisplay(.headline))
                        .foregroundStyle(PixelHandTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(PixelHandTheme.accent)
                        .accessibilityIdentifier("ph.settings.done")
                }
            }
        }
        // Applied here as well as at the app root: a sheet gets its own
        // presentation host, so without this the appearance change wouldn't
        // reach the very screen you changed it on until it was reopened.
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}
