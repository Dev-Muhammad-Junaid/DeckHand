//
//  QuickActionsChips.swift
//  DeckHandiOS
//
//  Shortcut chips, the "Add shortcuts" call to action and the placeholder chip.
//  Split out of QuickActionsBar.swift (PH-010).
//

import SwiftUI
import UIKit

// MARK: - Shortcut Chip (contextual — label + glyph)

struct ShortcutChip: View {
    let binding: AppShortcutBinding
    let colorScheme: ColorScheme
    /// Sends the shortcut and reports whether the Mac confirmed it.
    let onTap: @MainActor () async -> CommandDelivery

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var delivery = DeliveryTracker()

    var body: some View {
        Button {
            Task { await DeliveryTracker.run($delivery, send: onTap) }
        } label: {
            VStack(spacing: 2) {
                Text(binding.keyGlyphs)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(binding.displayName)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 56)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PixelHandTheme.color(PaletteTokens.fill, for: colorScheme))
            )
            .deliveryDots(delivery.state)
            .scaleEffect(isPressed && !reduceMotion ? 0.93 : 1.0)
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

// MARK: - Add Shortcuts CTA (empty contextual segment)

struct AddShortcutsChip: View {
    let appName: String
    let colorScheme: ColorScheme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                Text("Add shortcuts")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12),
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
        }
        .buttonStyle(.plain)
    }
}

struct PlaceholderChip: View {
    let text: String
    let systemImage: String
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary.opacity(0.5))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
