//
//  HostCapabilityBanner.swift
//  DeckHandiOS
//

import SwiftUI

/// Compact warning strip shown when the host reports a missing macOS
/// permission. The remote can't fix it, but it CAN say why nothing works.
struct HostCapabilityBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(DeckHandTheme.warning)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DeckHandTheme.warning.opacity(0.12))
        .transition(.opacity)
    }
}
