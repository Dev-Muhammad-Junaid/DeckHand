//
//  QuickActionsIconButton.swift
//  DeckHandiOS
//
//  Minimal icon button for the global macros and media keys.
//  Split out of QuickActionsBar.swift (PH-010).
//

import SwiftUI
import UIKit

// MARK: - Icon Button (minimal — used for global macros & media)

struct IconButton: View {
    let symbol: String
    let colorScheme: ColorScheme
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.primary.opacity(0.75))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
                .scaleEffect(isPressed && !reduceMotion ? 0.88 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}
