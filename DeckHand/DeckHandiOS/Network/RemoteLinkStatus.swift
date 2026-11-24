//
//  RemoteLinkStatus.swift
//  DeckHandiOS
//
//  The live session's link, for views that don't hold the session model
//  (the toolbar badge, Settings › Connection). `ControlSessionModel+Network`
//  writes it; `nil` when no session is running.
//

import Observation
import SwiftUI

@MainActor
@Observable
final class RemoteLinkStatus {
    static let shared = RemoteLinkStatus()
    var current: LinkKind?
    /// S15: the mirror runs at "away" quality (VPN or a slow link).
    var isAway = false
}

/// "Wired" next to the header subtitle while the session runs over a USB
/// cable, "VPN" while it runs through a tunnel (S15). Shows nothing on
/// other links, to keep the header quiet.
struct RemoteLinkBadge: View {
    private let status = RemoteLinkStatus.shared

    var body: some View {
        switch status.current {
        case .wired:
            Label(LinkKind.wired.displayName, systemImage: LinkKind.wired.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PixelHandTheme.accent)
                .accessibilityLabel("Connected by cable")
        case .tunnel:
            Label(LinkKind.tunnel.displayName, systemImage: LinkKind.tunnel.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Connected over a VPN")
        default:
            EmptyView()
        }
    }
}
