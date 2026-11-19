//
//  HostLinkBadge.swift
//  DeckHandMac
//
//  The link under one connection in the menu bar's device row: "Wired"
//  (accent) over a USB cable, otherwise the link's name in secondary text.
//  Nothing until `HostLinkMonitor` has judged it.
//

import SwiftUI

struct HostLinkBadge: View {
    let connectionID: UUID
    private let monitor = HostLinkMonitor.shared

    var body: some View {
        if let kind = monitor.kinds[connectionID], kind != .unknown {
            Label(kind.displayName, systemImage: kind.systemImage)
                .font(.system(size: 10, weight: kind == .wired ? .semibold : .regular))
                .foregroundStyle(kind == .wired ? AnyShapeStyle(DeckHandTheme.accent) : AnyShapeStyle(.secondary))
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Link: \(kind.displayName)")
        }
    }
}
