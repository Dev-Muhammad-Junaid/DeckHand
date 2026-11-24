//
//  SettingsMirrorSection.swift
//  DeckHandiOS
//
//  Settings › Live mirror: sharpness, frame rate, remembered layout,
//  follow cursor, HEVC video (S5), the Mac's sound (S17), Picture in
//  Picture (UX-041, Pro like the mirror) and the stream stats line.
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

            Toggle("Follow the cursor between displays", isOn: $settings.mirrorFollowsCursor)

            Toggle("Efficient video (HEVC)", isOn: $settings.mirrorPrefersHEVC)

            Toggle("Play the Mac’s sound", isOn: $settings.mirrorPlaysMacAudio)

            if MirrorPiPController.isSupported {
                Toggle("Keep watching in Picture in Picture", isOn: $settings.mirrorPiPAutoStart)
                    .requiresPro(.mirror)
            }

            Toggle("Show stream stats", isOn: $settings.showMirrorStats)
        } header: {
            Text("Live mirror")
        } footer: {
            Text("Sharpness and frame rate together decide how much of your network the mirror uses. Drop both if the picture stutters before you blame the Mac. Efficient video sends smooth, sharp HEVC video using much less data; turn it off to get still images instead, or if this device can't decode HEVC. Play the Mac's sound plays what the Mac is playing on this device while the mirror is open, a moment behind, mixed with this device's own sound; it stops when Pixel Hand goes to the background unless Picture in Picture is showing the mirror. Keep watching in Picture in Picture keeps the Mac's screen in a small floating window when you leave Pixel Hand with the mirror open, and keeps the connection alive while it shows; pause it to freeze the picture. Stream stats show the codec, frame rate, timing and data rate on both ends.")
        }
    }
}
