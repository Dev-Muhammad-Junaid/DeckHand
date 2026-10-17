//
//  DeckHandEmptyState.swift
//  DeckHandiOS
//

import SwiftUI

/// Shared layout for "nothing here yet" states: a dot-matrix glyph on a
/// piece of the icon's screen, a line of copy, and optional actions. The
/// glyphs are the website's (`PixelArt`), so an empty sheet reads as part of
/// the same product.
struct DeckHandEmptyState<Actions: View>: View {
    let glyph: PixelBitmap
    let title: String
    var message: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            PixelScreen(cornerRadius: 14, padding: 12) {
                PixelGlyph(bitmap: glyph, pitch: 4)
            }
            .padding(.bottom, 2)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color.secondary)
                if let message {
                    Text(message)
                        .font(DeckHandTheme.TypeStyle.captionRounded)
                        .foregroundStyle(Color.secondary.opacity(0.8))
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)

            actions
        }
    }
}

extension DeckHandEmptyState where Actions == EmptyView {
    init(glyph: PixelBitmap, title: String, message: String? = nil) {
        self.init(glyph: glyph, title: title, message: message) { EmptyView() }
    }
}
