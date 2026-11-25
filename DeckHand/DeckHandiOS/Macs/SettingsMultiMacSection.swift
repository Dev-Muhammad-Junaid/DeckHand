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
            SettingsToggle(
                "Swipe between Macs",
                glyph: PixelGlyphs.spaceRight,
                subtitle: "Three fingers left or right switch Macs. Off, they switch Spaces.",
                isOn: $settings.swipeBetweenMacs
            )
            SettingsToggle(
                "Reconnect automatically",
                glyph: PixelGlyphs.wifi,
                subtitle: "To the Mac you used last, when it’s in reach.",
                isOn: $settings.reconnectAutomatically
            )
        } header: {
            SettingsSectionHeader("Several Macs", glyph: PixelGlyphs.displays)
        } footer: {
            Text("Switch Macs from the Mac pill, the iPad sidebar, or ⌘1–⌘4 on a keyboard.")
        }
    }
}
