//
//  SettingsCaptureSection.swift
//  DeckHandiOS
//
//  Settings › Screenshots: capture button, quality, auto-save.
//  Split out of SettingsView.swift (PH-010).
//

import SwiftUI

struct SettingsCaptureSection: View {
    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        Section {
            Picker("Capture button", selection: $settings.defaultCapture) {
                ForEach(DefaultCapture.allCases) { option in
                    Label(option.label, systemImage: option.icon).tag(option)
                }
            }

            SettingBlock("Quality", caption: settings.screenshotQuality.detail) {
                Picker("Quality", selection: $settings.screenshotQuality) {
                    ForEach(CaptureQuality.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Save to Photos automatically", isOn: $settings.autoSaveToPhotos)
        } header: {
            Text("Screenshots")
        } footer: {
            Text("Quality applies to full-screen captures. Region and window captures already ship at close to native resolution. Saving automatically asks for Photos access the first time a capture lands.")
        }
    }
}
