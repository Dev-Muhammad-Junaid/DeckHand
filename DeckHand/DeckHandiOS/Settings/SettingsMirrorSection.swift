//
//  SettingsMirrorSection.swift
//  DeckHandiOS
//
//  Settings › Live mirror: sharpness, frame rate, remembered layout.
//  Split out of SettingsView.swift (PH-010).
//

import SwiftUI

struct SettingsMirrorSection: View {
    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        Section {
            Picker("Sharpness", selection: $settings.mirrorSharpness) {
                ForEach(MirrorSharpness.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Text(settings.mirrorSharpness.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)

            SettingBlock("Frame rate") {
                Picker("Frame rate", selection: $settings.mirrorFrameRate) {
                    ForEach(MirrorFrameRate.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Remember size and position", isOn: $settings.rememberMirrorLayout)
        } header: {
            Text("Live mirror")
        } footer: {
            Text("Sharpness and frame rate together decide how much of your network the mirror uses. Drop both if the picture stutters before you blame the Mac.")
        }
    }
}
