//
//  SettingsPointerSection.swift
//  DeckHandiOS
//
//  Settings › Pointer and gestures: sensitivity, haptics, scrolling, send
//  rate, Mac gestures (S11) and Pencil hover (S12); and Settings ›
//  Clipboard (S10). Split out of SettingsView.swift (PH-010); owned by the
//  iOS interaction lane.
//

import SwiftUI
import UIKit

struct SettingsPointerSection: View {
    @EnvironmentObject private var settings: DeckHandSettings

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

            SettingBlock("Haptics", caption: "Taps and gestures buzz the iPad.") {
                Picker("Haptics", selection: $settings.hapticStrength) {
                    ForEach(HapticStrength.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Natural scrolling", isOn: $settings.naturalScrolling)

            Toggle(isOn: $settings.trackpadGestures) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac gestures")
                    Text(TrackpadInputCopy.gesturesCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if UIDevice.current.userInterfaceIdiom == .pad {
                Toggle(isOn: $settings.pencilHoverPointer) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Pencil hover moves the pointer")
                        Text(TrackpadInputCopy.pencilCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingBlock("Send rate", caption: "How often touches are sent to the Mac.") {
                Picker("Send rate", selection: $settings.inputSendRate) {
                    ForEach(InputSendRate.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        } header: {
            Text("Pointer and gestures")
        } footer: {
            Text("Natural scrolling moves the content with your fingers. 120 Hz matches ProMotion so no touch is discarded; 60 Hz halves the packets if the pointer feels erratic on a busy network. \(TrackpadInputCopy.dragFooter)")
        }

        Section {
            Toggle("Share clipboard", isOn: $settings.clipboardSync)
            Toggle("Paste on the Mac right away", isOn: $settings.pasteRightAway)
        } header: {
            Text("Clipboard")
        } footer: {
            Text(TrackpadInputCopy.clipboardFooter)
        }
    }
}
