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
}

/// "Wired" next to the header subtitle while the session runs over a USB
/// cable. Shows nothing on other links, to keep the header quiet.
struct RemoteLinkBadge: View {
    private let status = RemoteLinkStatus.shared

    var body: some View {
        if status.current == .wired {
            Label(LinkKind.wired.displayName, systemImage: LinkKind.wired.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DeckHandTheme.accent)
                .accessibilityLabel("Connected by cable")
        }
    }
}
