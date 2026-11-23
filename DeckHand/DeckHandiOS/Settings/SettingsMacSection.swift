//
//  SettingsMacSection.swift
//  DeckHandiOS
//
//  Settings › <connected Mac>: the per-Mac section that comes first (board
//  `v2Settings` "STUDIO", `07-Polish-Spec.md` §7): the Mac with its link
//  badge, then the Mac's sound and the link's mirror behaviour. Hidden when
//  no Mac is connected. The full per-Mac settings (quality, VPN per Mac)
//  follow with My Macs (UX-030).
//

import SwiftUI

struct SettingsMacSection: View {
    @EnvironmentObject private var settings: DeckHandSettings
    private let pairing = PairedMacsStore.shared
    private let linkStatus = RemoteLinkStatus.shared

    var body: some View {
        if let mac = pairing.liveMac {
            Section {
                SettingsRow(mac.name, glyph: PixelGlyphs.mac, subtitle: "Connected", isLit: true) {
                    if let badge = linkBadge {
                        LinkBadge(kind: badge)
                    }
                }
                Toggle(isOn: $settings.mirrorPlaysMacAudio) {
                    SettingsRow("Play the Mac’s sound", glyph: PixelGlyphs.soundOn)
                }
                Toggle(isOn: $settings.mirrorFollowsCursor) {
                    SettingsRow("Follow the cursor between displays", glyph: PixelGlyphs.displays)
                }
            } header: {
                SettingsSectionHeader(mac.name, glyph: PixelGlyphs.mac)
            }
        }
    }

    private var linkBadge: LinkBadge.Kind? {
        switch linkStatus.current {
        case .wired, .ethernet: .wired
        case .tunnel: .vpn
        case .peerToPeer: .direct
        case .some: .wifi
        case nil: nil
        }
    }
}
