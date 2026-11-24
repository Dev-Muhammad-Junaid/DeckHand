//
//  QuickActionsNumpad.swift
//  DeckHandiOS
//
//  Digit chips shown for numeric fields.
//  Split out of QuickActionsBar.swift (PH-010).
//

import SwiftUI
import UIKit

// MARK: - Numpad

struct NumpadAction: Identifiable {
    let id: String
    /// Shown under the key glyph (digit or symbol).
    let label: String
    let symbol: String?
    let keys: [String]
    let isPrimary: Bool

    /// Keys 1–9, 0, decimal, minus, delete, return — sent as raw
    /// keyboard events to whatever field is focused on the Mac.
    static let all: [NumpadAction] = [
        .init(id: "1", label: "1", symbol: nil, keys: ["1"], isPrimary: false),
        .init(id: "2", label: "2", symbol: nil, keys: ["2"], isPrimary: false),
        .init(id: "3", label: "3", symbol: nil, keys: ["3"], isPrimary: false),
        .init(id: "4", label: "4", symbol: nil, keys: ["4"], isPrimary: false),
        .init(id: "5", label: "5", symbol: nil, keys: ["5"], isPrimary: false),
        .init(id: "6", label: "6", symbol: nil, keys: ["6"], isPrimary: false),
        .init(id: "7", label: "7", symbol: nil, keys: ["7"], isPrimary: false),
        .init(id: "8", label: "8", symbol: nil, keys: ["8"], isPrimary: false),
        .init(id: "9", label: "9", symbol: nil, keys: ["9"], isPrimary: false),
        .init(id: "0", label: "0", symbol: nil, keys: ["0"], isPrimary: false),
        .init(id: "dot", label: ".", symbol: nil, keys: ["."], isPrimary: false),
        .init(id: "minus", label: "−", symbol: "minus", keys: ["-"], isPrimary: false),
        .init(id: "del", label: "Del", symbol: "delete.left", keys: ["delete"], isPrimary: false),
        .init(id: "ret", label: "Enter", symbol: "return", keys: ["return"], isPrimary: true),
    ]
}

struct NumpadChip: View {
    let key: NumpadAction
    let colorScheme: ColorScheme
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            Group {
                if let sym = key.symbol {
                    VStack(spacing: 2) {
                        Image(systemName: sym)
                            .font(.system(size: 13, weight: key.isPrimary ? .semibold : .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(foreground)
                        Text(key.label)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(foreground.opacity(0.78))
                            .lineLimit(1)
                    }
                } else {
                    Text(key.label)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(foreground)
                }
            }
            .frame(minWidth: key.symbol == nil ? 34 : 40, minHeight: 36)
            .padding(.horizontal, key.symbol == nil ? 6 : 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
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
        key.isPrimary ? .white : Color.primary.opacity(0.85)
    }

    private var background: Color {
        key.isPrimary ? PixelHandTheme.accent : PixelHandTheme.color(PaletteTokens.fill, for: colorScheme)
    }
}
