//
//  QuickActionsFABs.swift
//  DeckHandiOS
//
//  The floating keyboard and numeric toggles and their shared renderer.
//  Split out of QuickActionsBar.swift (PH-010).
//

import SwiftUI
import UIKit

// MARK: - Keyboard FAB

/// Floating circular toggle that force-enables the edit-chip row in the
/// Quick Actions bar. Use when AX didn't surface a focused text field —
/// common in Chromium / Electron apps and custom-drawn controls.
/// Visibility is owned by the parent (StreamDeckGridView) which hides it
/// when a dialog or AX-detected text field is already active.
struct KeyboardFAB: View {
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        FABButton(
            systemImage: "keyboard",
            isActive: isActive,
            tint: PixelHandTheme.accent,
            accessibilityLabel: isActive ? "Hide text edit actions"
                                         : "Show text edit actions",
            onTap: onTap
        )
    }
}

// MARK: - Numeric FAB

/// Floating toggle for the digit row in the Quick Actions bar. Mutually
/// exclusive with `KeyboardFAB` — the parent flips `EditFABMode` so only
/// one auxiliary row is visible at a time.
struct NumericFAB: View {
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        FABButton(
            systemImage: "textformat.123",
            isActive: isActive,
            tint: PixelHandTheme.success,
            accessibilityLabel: isActive ? "Hide number keys"
                                         : "Show number keys",
            onTap: onTap
        )
    }
}

// MARK: - Shared FAB renderer
//
// `KeyboardFAB` and `NumericFAB` are thin shells around a native `Button`
// circular toggle. The actual visual treatment comes from the system:
// iOS 26+ uses Liquid Glass via `.glass` / `.glassProminent`; iOS 17
// falls back to `.bordered` / `.borderedProminent`. Either way, geometry,
// shadow, and press animations are handled by the platform — we only
// pick the icon and the active tint.

struct FABButton: View {
    let systemImage: String
    let isActive: Bool
    let tint: Color
    let accessibilityLabel: String
    let onTap: () -> Void

    var body: some View {
        nativeButton
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var nativeButton: some View {
        // Compile-time guard, not just runtime: `.glass` / `.glassProminent`
        // are iOS 26 SDK symbols (Xcode 26 / Swift 6.2). On Xcode 16 the
        // branch can't compile, so fall back to `.bordered` variants.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if isActive {
                Button(action: onTap) { icon }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            } else {
                Button(action: onTap) { icon }
                    .buttonStyle(.glass)
            }
        } else {
            if isActive {
                Button(action: onTap) { icon }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            } else {
                Button(action: onTap) { icon }
                    .buttonStyle(.bordered)
            }
        }
        #else
        if isActive {
            Button(action: onTap) { icon }
                .buttonStyle(.borderedProminent)
                .tint(tint)
        } else {
            Button(action: onTap) { icon }
                .buttonStyle(.bordered)
        }
        #endif
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
    }
}
