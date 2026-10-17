//
//  AuthorizationOverlay.swift
//  DeckHandiOS
//

import SwiftUI

struct AuthorizationOverlay: View {
    let status: String
    let peerName: String
    let onDisconnect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// True when the only sensible action is to dismiss the overlay (the
    /// connection is already gone). Drives both the button label and its
    /// destructive role.
    private var isTerminalState: Bool {
        status == "denied" || status == "host_disconnected"
    }

    var body: some View {
        ZStack {
            DeckHandTheme.authScrim(colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                statusContent
                disconnectButton
                    .padding(.top, 8)
                    // Approved shows for a moment before the card leaves;
                    // keep the button's space so the card doesn't jump.
                    .opacity(status == "granted" ? 0 : 1)
                    .disabled(status == "granted")
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Native button (matches main-page toolbar styling)
    //
    // iOS 26 picks up Liquid Glass via `.glass`. The destructive role tints
    // the label red (matching the main-page disconnect button). On iOS 17
    // we fall back to `.bordered`, which gives the same shape language.

    @ViewBuilder
    private var disconnectButton: some View {
        let label = isTerminalState ? "Dismiss" : "Disconnect"
        let role: ButtonRole? = isTerminalState ? .cancel : .destructive
        // Compile-time guard, not just runtime: `.glass` only exists in the
        // iOS 26 SDK (Xcode 26 / Swift 6.2). On Xcode 16 the whole branch
        // would fail to compile, so gate it out and use `.bordered`.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Button(label, role: role, action: onDisconnect)
                .buttonStyle(.glass)
                .controlSize(.large)
        } else {
            Button(label, role: role, action: onDisconnect)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        #else
        Button(label, role: role, action: onDisconnect)
            .buttonStyle(.bordered)
            .controlSize(.large)
        #endif
    }

    // MARK: - Native dialog card (Liquid Glass on iOS 26, material on iOS 17)

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: DeckHandTheme.Radius.xxl, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            shape
                .fill(.regularMaterial)
                .glassEffect(in: shape)
        } else {
            shape
                .fill(.regularMaterial)
                .shadow(color: DeckHandTheme.dialogCardShadow(colorScheme), radius: 24, y: 12)
        }
        #else
        shape
            .fill(.regularMaterial)
            .shadow(color: DeckHandTheme.dialogCardShadow(colorScheme), radius: 24, y: 12)
        #endif
    }

    /// One glyph for every state, outside any `switch`, so it's the same
    /// view across status changes and can rearrange its dots from one
    /// state into the next.
    private var statusContent: some View {
        VStack(spacing: 16) {
            PixelScreen(cornerRadius: 18, padding: 12) {
                PixelMorph(glyph: ApprovalGlyph(status: status))
            }

            VStack(spacing: 8) {
                Text(copy.title)
                    .font(DeckHandTheme.TypeStyle.titleRounded)
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)

                if !copy.message.isEmpty {
                    Text(copy.message)
                        .font(DeckHandTheme.TypeStyle.bodyRounded)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
            }
        }
    }

    private var copy: (title: String, message: String) {
        switch status {
        case "pending":
            ("Waiting for Approval", "Please allow the connection request on \(peerName).")
        case "granted":
            ("Approved", "You’re connected to \(peerName).")
        case "host_disconnected":
            ("Disconnected", "The connection to \(peerName) was closed.")
        case "denied":
            ("Access Denied", "Your request to control \(peerName) was declined.")
        default:
            ("Unknown state", "")
        }
    }
}
