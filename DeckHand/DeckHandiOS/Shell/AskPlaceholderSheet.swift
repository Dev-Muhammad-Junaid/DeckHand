//
//  AskPlaceholderSheet.swift
//  DeckHandiOS – Shell
//
//  What the Ask button opens until Ask ships (UX-022, roadmap 1.4): the Ask
//  glyph on navy and one honest sentence. No sparkles anywhere.
//

import SwiftUI

struct AskPlaceholderSheet: View {
    let macName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PixelSurface(cornerRadius: 0) {
            VStack(spacing: PixelHandTheme.Space.xl) {
                PHEmptyState(
                    glyph: PixelGlyphs.ask,
                    title: "Ask is on its way",
                    message: "Soon you’ll type what you want \(macName) to do, and Pixel Hand will plan the steps."
                )
                Button("Close") { dismiss() }
                    .buttonStyle(.ph(.secondary, size: .regular))
            }
            .padding(PixelHandTheme.Space.xl)
        }
        .ignoresSafeArea()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
