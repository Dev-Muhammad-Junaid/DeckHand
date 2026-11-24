//
//  QuickActionsPills.swift
//  DeckHandiOS
//
//  The app context pill and the idle pill at the start of the bar.
//  Split out of QuickActionsBar.swift (PH-010).
//

import SwiftUI
import UIKit

// MARK: - App Context Pill

struct AppContextPill: View {
    let app: InstalledAppInfo
    let colorScheme: ColorScheme
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                icon.frame(width: 28, height: 28)
                Text(app.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(minWidth: 52)
            .padding(.horizontal, 4)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }

    @ViewBuilder
    private var icon: some View {
        if let data = app.iconData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PixelHandTheme.color(PaletteTokens.fill, for: colorScheme))
                .overlay(
                    Image(systemName: "app")
                        .font(.system(size: 13, weight: .thin))
                        .foregroundStyle(Color.primary.opacity(0.4))
                )
        }
    }
}

// MARK: - Idle Pill (no active app yet)

struct IdlePill: View {
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "app.dashed")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .frame(width: 28, height: 28)
            Text("No app")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary.opacity(0.6))
        }
        .frame(minWidth: 52)
        .padding(.horizontal, 4)
    }
}
