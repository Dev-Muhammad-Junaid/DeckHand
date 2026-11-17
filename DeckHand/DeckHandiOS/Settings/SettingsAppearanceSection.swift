//
//  SettingsAppearanceSection.swift
//  DeckHandiOS
//
//  Settings › Appearance: theme.
//  Split out of SettingsView.swift (PH-010).
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
            Text("Appearance")
        } footer: {
            Text("Applies to the control screens. The device picker stays dark to match the app icon.")
        }
    }
}
