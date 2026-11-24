//
//  TextFieldAction.swift
//  DeckHandiOS
//
//  Edit chips shown while a text field is focused on the Mac.
//  Split out of QuickActionsBar.swift (PH-010).
//

import SwiftUI
import UIKit

// MARK: - Text Field Actions

/// One chip in the text/numeric editing row.
struct TextFieldAction: Identifiable {
    let id: String
    let symbol: String
    let label: String
    let keys: [String]
    let isPrimary: Bool  // Return — accent-filled like the default dialog button

    static func actions(for kind: TextFieldContext.Kind) -> [TextFieldAction] {
        switch kind {
        case .text:
            return [
                .init(id: "cut",       symbol: "scissors",             label: "Cut",    keys: ["cmd", "x"],          isPrimary: false),
                .init(id: "copy",      symbol: "doc.on.doc",           label: "Copy",   keys: ["cmd", "c"],          isPrimary: false),
                .init(id: "paste",     symbol: "doc.on.clipboard",     label: "Paste",  keys: ["cmd", "v"],          isPrimary: false),
                .init(id: "undo",      symbol: "arrow.uturn.backward", label: "Undo",   keys: ["cmd", "z"],          isPrimary: false),
                .init(id: "redo",      symbol: "arrow.uturn.forward",  label: "Redo",   keys: ["cmd", "shift", "z"], isPrimary: false),
                .init(id: "selectAll", symbol: "selection.pin.in.out", label: "Select all", keys: ["cmd", "a"],          isPrimary: false),
                .init(id: "left",      symbol: "arrow.left",           label: "Left",   keys: ["left"],              isPrimary: false),
                .init(id: "right",     symbol: "arrow.right",          label: "Right",  keys: ["right"],             isPrimary: false),
                .init(id: "delete",    symbol: "delete.left",          label: "Delete", keys: ["delete"],            isPrimary: false),
                .init(id: "return",    symbol: "return",               label: "Return", keys: ["return"],            isPrimary: true),
            ]

        case .numeric:
            return [
                .init(id: "dec",    symbol: "minus",                label: "Decrease", keys: ["down"],     isPrimary: false),
                .init(id: "inc",    symbol: "plus",                 label: "Increase", keys: ["up"],       isPrimary: false),
                .init(id: "paste",  symbol: "doc.on.clipboard",     label: "Paste",  keys: ["cmd", "v"], isPrimary: false),
                .init(id: "undo",   symbol: "arrow.uturn.backward", label: "Undo",   keys: ["cmd", "z"], isPrimary: false),
                .init(id: "delete", symbol: "delete.left",          label: "Delete", keys: ["delete"],   isPrimary: false),
                .init(id: "return", symbol: "return",               label: "Enter",  keys: ["return"],   isPrimary: true),
            ]

        case .secure:
            // Password fields: macOS blocks cut/copy and many apps will
            // ignore paste too, so keep the row minimal and focused.
            return [
                .init(id: "paste",  symbol: "doc.on.clipboard", label: "Paste",  keys: ["cmd", "v"], isPrimary: false),
                .init(id: "delete", symbol: "delete.left",      label: "Delete", keys: ["delete"],   isPrimary: false),
                .init(id: "return", symbol: "return",           label: "Submit", keys: ["return"],   isPrimary: true),
            ]
        }
    }
}

struct TextFieldChip: View {
    let action: TextFieldAction
    let colorScheme: ColorScheme
    let onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: action.symbol)
                    .font(.system(size: 13, weight: action.isPrimary ? .semibold : .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(foreground)
                Text(action.label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(foreground.opacity(action.isPrimary ? 0.9 : 0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 48)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
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

    private var foreground: Color {
        action.isPrimary ? .white : Color.primary.opacity(0.85)
    }

    private var background: Color {
        action.isPrimary ? PixelHandTheme.accent : PixelHandTheme.color(PaletteTokens.fill, for: colorScheme)
    }
}
