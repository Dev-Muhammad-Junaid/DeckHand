//
//  SettingsConnectionSection.swift
//  DeckHandiOS
//
//  Settings › Connection: the live session's link (S13) and same-iCloud
//  recognition. Split out of SettingsView.swift (PH-010). Network lane.
//

import SwiftUI

struct SettingsConnectionSection: View {
    @EnvironmentObject private var settings: DeckHandSettings
    private let linkStatus = RemoteLinkStatus.shared

    var body: some View {
        Section {
            if let link = linkStatus.current {
                LabeledContent {
                    Label(link.displayName, systemImage: link.systemImage)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(link == .wired ? AnyShapeStyle(DeckHandTheme.accent) : AnyShapeStyle(.secondary))
                } label: {
                    Text("Link")
                }
                .accessibilityElement(children: .combine)
            }
            CloudRecognitionRow()
        } header: {
            Text("Connection")
        } footer: {
            Text(Self.footer(link: linkStatus.current))
        }
    }

    static func footer(link: LinkKind?) -> String {
        guard link == .wired else { return CloudRecognitionStatus.footer }
        return "Connected by USB cable: no Wi-Fi in the way, and no keep-alive traffic needed.\n\n" + CloudRecognitionStatus.footer
    }
}
