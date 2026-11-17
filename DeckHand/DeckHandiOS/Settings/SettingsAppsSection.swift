//
//  SettingsAppsSection.swift
//  DeckHandiOS
//
//  Settings › Apps: undo hidden apps. Only shows once something is hidden.
//  Split out of SettingsView.swift (PH-010).
//

import SwiftUI

struct SettingsAppsSection: View {
    @EnvironmentObject private var settings: DeckHandSettings

    /// Only appears once something is hidden. Hiding happens from a context
    /// menu in the Apps grid, which has no way to undo itself.
    @ViewBuilder
    var body: some View {
        let hidden = settings.hiddenAppBundleIDs
        if !hidden.isEmpty {
            Section {
                HStack {
                    Text("Hidden apps")
                    Spacer()
                    Text("\(hidden.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button("Show hidden apps") {
                    settings.unhideAllApps()
                }
            } header: {
                Text("Apps")
            } footer: {
                Text("Hidden apps are removed from the Apps grid and its search results. This puts them all back.")
            }
        }
    }
}
