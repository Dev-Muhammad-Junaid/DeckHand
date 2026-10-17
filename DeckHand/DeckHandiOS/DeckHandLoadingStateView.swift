//
//  DeckHandLoadingStateView.swift
//  DeckHandiOS
//

import SwiftUI

/// Shared progress + copy for in-app loading states (control shell, apps
/// grid, window list, text recognition, screenshot capture). Waiting on the
/// Mac is the remote talking to it, so progress is a small dot scan rather
/// than a spinner.
struct DeckHandLoadingStateView: View {
    let title: String
    var subtitle: String?
    var verticalPadding: CGFloat = 60
    var titleColor: Color = .secondary
    var subtitleColor: Color?

    var body: some View {
        VStack(spacing: subtitle == nil ? 14 : 10) {
            DotScan(columns: 11, rows: 3, pitch: 7, plateCornerRadius: 10, platePadding: 8)
                // The title says what's happening.
                .accessibilityHidden(true)
            Text(title)
                .font(DeckHandTheme.TypeStyle.loadingTitle)
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(DeckHandTheme.TypeStyle.captionRounded)
                    .foregroundStyle(subtitleColor ?? titleColor.opacity(0.88))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, verticalPadding)
    }
}
