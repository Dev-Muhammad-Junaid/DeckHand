//
//  SettingsMultiMacSection.swift
//  DeckHandiOS – Macs
//
//  Settings › Several Macs (UX-030): three-finger switching and quick
//  reconnect. Owned by the Multi-Mac lane.
//

import SwiftUI

struct SettingsMultiMacSection: View {
    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        Section {
            Toggle(isOn: $settings.swipeBetweenMacs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Swipe between Macs")
                    Text("Three fingers left or right on the trackpad switch Macs when another one is in reach. Off, they switch Spaces on the Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $settings.reconnectAutomatically) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reconnect automatically")
                    Text("Connects to the Mac you used last when Pixel Hand opens, if it’s paired and in reach, and tries again when a connection drops.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Several Macs")
        } footer: {
            Text("Switch Macs from the Mac pill (tap for My Macs, swipe for the next one), the iPad sidebar, or ⌘1–⌘4 and ⌘` on a keyboard. Each Mac keeps its own surface, deck page and mirror settings.")
        }
    }
}
