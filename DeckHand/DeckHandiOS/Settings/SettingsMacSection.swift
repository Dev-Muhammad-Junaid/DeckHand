//
//  SettingsMacSection.swift
//  DeckHandiOS
//
//  Settings › <connected Mac>: the per-Mac section that comes first (board
//  `v2Settings` "STUDIO", `07-Polish-Spec.md` §7): the Mac with its link
//  badge. Hidden when no Mac is connected. The mirror's sound and
//  follow-cursor switches apply to every Mac, so they live only in Live
//  mirror (VQ-053); per-Mac overrides would show here as "Uses default"
//  rows once they exist (UX-030).
//

import SwiftUI

struct SettingsMacSection: View {
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
