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
            .foregroundStyle(PixelHandTheme.ink)
            Text(settings.mirrorSharpness.detail)
                .font(.footnote)
                .foregroundStyle(PixelHandTheme.ink2)

            SettingBlock("Frame rate") {
                Picker("Frame rate", selection: $settings.mirrorFrameRate) {
                    ForEach(MirrorFrameRate.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .settingsChoicePickerStyle()
                .labelsHidden()
            }

            SettingsToggle("Remember size and position", glyph: PixelGlyphs.region, isOn: $settings.rememberMirrorLayout)

            SettingsToggle("Follow the cursor between displays", glyph: PixelGlyphs.displays, isOn: $settings.mirrorFollowsCursor)

            SettingsToggle(
                "Efficient video (HEVC)",
                glyph: PixelGlyphs.screen,
                subtitle: "Off sends still images instead.",
                isOn: $settings.mirrorPrefersHEVC
            )

            SettingsToggle(
                "Play the Mac’s sound",
                glyph: PixelGlyphs.soundOn,
                subtitle: "While the mirror is open, a moment behind.",
                isOn: $settings.mirrorPlaysMacAudio
            )

            if MirrorPiPController.isSupported {
                SettingsToggle(
                    "Keep watching in Picture in Picture",
                    glyph: PixelGlyphs.pictureInPicture,
                    subtitle: "When you leave Pixel Hand with the mirror open.",
                    isOn: $settings.mirrorPiPAutoStart
                )
                .requiresPro(.mirror)
            }

            SettingsToggle("Show stream stats", glyph: PixelGlyphs.console, isOn: $settings.showMirrorStats)
        } header: {
            SettingsSectionHeader("Live mirror", glyph: PixelGlyphs.screen)
        } footer: {
            // One or two sentences (VQ-053); each switch explains itself.
            Text("Sharpness and frame rate decide how much of your network the mirror uses. If the picture stutters, lower both.")
        }
    }
}
