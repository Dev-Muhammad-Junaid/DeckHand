//
//  SettingsPointerSection.swift
//  DeckHandiOS
//
//  Settings › Pointer and gestures: sensitivity, haptics, scrolling, the
//  click strip, send rate, Mac gestures (S11) and Pencil hover (S12); and Settings ›
//  Clipboard (S10). Split out of SettingsView.swift (PH-010); owned by the
//  iOS interaction lane.
//

import SwiftUI
import UIKit

struct SettingsPointerSection: View {
    @EnvironmentObject private var settings: DeckHandSettings
    /// The Pointer surface's Click | Right-click strip (UX-004).
    @AppStorage(PointerSurfaceSettings.showsClickStripKey) private var showsClickStrip = true

    var body: some View {
        Section {
            SettingBlock("Sensitivity", value: TrackpadSensitivity.label(for: settings.pointerSensitivity)) {
                Slider(
                    value: Binding(
                        get: { Double(TrackpadSensitivity.nearestIndex(to: settings.pointerSensitivity)) },
                        set: { settings.pointerSensitivity = TrackpadSensitivity.anchors[Int($0.rounded())] }
                    ),
                    in: TrackpadSensitivity.indexRange,
                    step: 1
                )
                .accessibilityLabel("Pointer sensitivity")
                .accessibilityValue(TrackpadSensitivity.label(for: settings.pointerSensitivity))
            }

            SettingBlock("Haptics", caption: "Taps and gestures buzz your iPhone or iPad.") {
                Picker("Haptics", selection: $settings.hapticStrength) {
                    ForEach(HapticStrength.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            SettingsToggle(
                "Natural scrolling",
                glyph: PixelGlyphs.click,
                subtitle: "Content moves with your fingers.",
                isOn: $settings.naturalScrolling
            )

            SettingsToggle("Click strip", glyph: PixelGlyphs.click, subtitle: TrackpadInputCopy.clickStripCaption, isOn: $showsClickStrip)

            SettingsToggle("Mac gestures", glyph: PixelGlyphs.missionControl, subtitle: TrackpadInputCopy.gesturesCaption, isOn: $settings.trackpadGestures)

            if UIDevice.current.userInterfaceIdiom == .pad {
                SettingsToggle(
                    "Apple Pencil hover moves the pointer",
                    glyph: PixelGlyphs.pointer,
                    subtitle: TrackpadInputCopy.pencilCaption,
                    isOn: $settings.pencilHoverPointer
                )
            }

            SettingBlock("Send rate", caption: "How often touches are sent to the Mac. Try 60 Hz if the pointer feels erratic on a busy network.") {
                Picker("Send rate", selection: $settings.inputSendRate) {
                    ForEach(InputSendRate.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        } header: {
            SettingsSectionHeader("Pointer and gestures", glyph: PixelGlyphs.pointer)
        } footer: {
            Text(TrackpadInputCopy.dragFooter)
        }

        Section {
            SettingsToggle("Share clipboard", glyph: PixelGlyphs.paste, isOn: $settings.clipboardSync)
                .requiresPro(.sharing) // Store lane
            SettingsToggle("Paste on the Mac right away", glyph: PixelGlyphs.type, isOn: $settings.pasteRightAway)
        } header: {
            SettingsSectionHeader("Clipboard", glyph: PixelGlyphs.paste)
        } footer: {
            Text(TrackpadInputCopy.clipboardFooter)
        }
    }
}
