//
//  SettingsConnectionSection.swift
//  DeckHandiOS
//
//  Settings › Connection: same-iCloud recognition.
//  Split out of SettingsView.swift (PH-010).
//

import SwiftUI

struct SettingsConnectionSection: View {
    @EnvironmentObject private var settings: DeckHandSettings

    var body: some View {
        Section {
            CloudRecognitionRow()
        } header: {
            Text("Connection")
        } footer: {
            Text(CloudRecognitionStatus.footer)
        }
    }
}
