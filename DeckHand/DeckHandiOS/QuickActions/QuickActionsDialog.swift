//
//  QuickActionsDialog.swift
//  DeckHandiOS
//
//  Dialog takeover chips: the info button with its popover, and the dialog button chip with delivery dots.
//  Split out of QuickActionsBar.swift (PH-010).
//

import SwiftUI
import UIKit

// MARK: - Dialog Info Button (tap-to-reveal tooltip)

/// Compact accent alert icon shown inside the takeover bar. Tap to pop
/// over the dialog's title + full message, so long AX copy doesn't steal
/// horizontal space from the action buttons. Hidden entirely when AX
/// surfaced neither a title nor a message — in that case the actions
/// alone carry the context.
struct DialogInfoButton: View {
    let title: String?
    let message: String?
    let colorScheme: ColorScheme

    @State private var showingPopover = false

    private var hasInfo: Bool {
        (title?.isEmpty == false) || (message?.isEmpty == false)
    }

    var body: some View {
        if hasInfo {
            Button {
                GestureHaptic.light.trigger()
                showingPopover.toggle()
            } label: {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DeckHandTheme.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                DialogInfoPopover(title: title, message: message, colorScheme: colorScheme)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

struct DialogInfoPopover: View {
    let title: String?
    let message: String?
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
            }
            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 220, maxWidth: 320, alignment: .leading)
    }
}

// MARK: - Dialog Button Chip

struct DialogButtonChip: View {
    let button: DialogButton
    let colorScheme: ColorScheme
    /// Presses the button on the Mac and reports whether it confirmed.
    let onTap: @MainActor () async -> CommandDelivery

    @State private var isPressed = false
    @State private var delivery = DeliveryTracker()

    var body: some View {
        Button {
            Task { await DeliveryTracker.run($delivery, send: onTap) }
        } label: {
            HStack(spacing: 5) {
                Text(button.title)
                    .font(.system(size: 12, weight: button.isDefault ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                if button.isDefault {
                    Text("⏎")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(foreground.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 1)
                    )
            )
            .deliveryDots(delivery.state)
            .scaleEffect(isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }

    private var foreground: Color {
        if button.isDefault { return .white }
        if button.isCancel  { return Color.secondary }
        return Color.primary
    }

    private var background: Color {
        if button.isDefault { return DeckHandTheme.accent }
        if button.isCancel  { return Color.clear }
        return DeckHandTheme.subtleWellFill(colorScheme)
    }

    private var stroke: Color {
        if button.isDefault { return DeckHandTheme.accent.opacity(0.8) }
        if button.isCancel  { return Color.primary.opacity(0.14) }
        return Color.primary.opacity(0.08)
    }
}
