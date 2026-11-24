//
//  DeckHandLoadingStateView.swift
//  DeckHandiOS
//

import SwiftUI

/// Shared progress + copy for in-app loading states (control shell, apps
/// grid, window list, text recognition, screenshot capture). Waiting on the
/// Mac is the remote talking to it, so progress is the dot wave rather than
/// a spinner.
struct DeckHandLoadingStateView: View {
    let title: String
    var subtitle: String?
    var verticalPadding: CGFloat = 60
    var titleColor: Color = .secondary
    var subtitleColor: Color?

    var body: some View {
        VStack(spacing: subtitle == nil ? 14 : 10) {
            // UX-018: the dot wave on a navy plate. The title says what's
            // happening.
            DotWave(pitch: 7)
                .padding(10)
                .background(PixelHandTheme.Brand.screen, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
