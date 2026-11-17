//
//  AppSwitcherMenu.swift
//  DeckHandiOS
//
//  The Cmd+Tab-style running-apps menu.
//  Split out of QuickActionsBar.swift (PH-010).
//

import SwiftUI
import UIKit

// MARK: - App Switcher Menu (Cmd+Tab style)

/// Small chevron button next to the active-app pill. Tap opens a native
/// `Menu` listing every other running app on the Mac in Cmd+Tab order;
/// selecting one sends a `launchApp` which the Mac handles as an activate.
struct AppSwitcherMenu: View {
    let apps: [InstalledAppInfo]
    let colorScheme: ColorScheme
    let onSelect: (InstalledAppInfo) -> Void

    var body: some View {
        Menu {
            ForEach(apps) { app in
                Button {
                    onSelect(app)
                } label: {
                    if let data = app.iconData, let ui = UIImage(data: data) {
                        Label {
                            Text(app.displayName)
                        } icon: {
                            Image(uiImage: ui)
                        }
                    } else {
                        Label(app.displayName, systemImage: "app")
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 20, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
    }
}
