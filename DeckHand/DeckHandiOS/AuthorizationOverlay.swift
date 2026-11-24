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
    /// Pairing (S4): the code sheet, and the live session's pairing state
    /// (the Mac's answer to a code sent from a scanned QR invite).
    @State private var isEnteringCode = false
    private let pairing = PairedMacsStore.shared

    /// True when the only sensible action is to dismiss the overlay (the
    /// connection is already gone). Drives both the button label and its
    /// destructive role.
    private var isTerminalState: Bool {
        ApprovalStatusCopy.isTerminal(status)
    }

    var body: some View {
        ZStack {
            PixelHandTheme.color(PaletteTokens.scrim, for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: PixelHandTheme.Space.xl) {
                statusContent
                if status == "pending" {
                    pairingPrompt
                }
                disconnectButton
                    .padding(.top, PixelHandTheme.Space.xs)
                    // Approved shows for a moment before the card leaves;
                    // keep the button's space so the card doesn't jump.
                    .opacity(status == "granted" ? 0 : 1)
                    .disabled(status == "granted")
            }
            .padding(PixelHandTheme.Space.xxl)
            .frame(maxWidth: 480)
            .background(cardBackground)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(copy.title)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("ph.authorization")
            .padding(.horizontal, PixelHandTheme.Space.xl)
            // Scrolls instead of clipping at AX sizes or in landscape.
            .frame(maxWidth: .infinity)
            .modifier(ScrollsWhenTall())
        }
        .sheet(isPresented: $isEnteringCode) {
            PairingCodeEntryView(macName: peerName)
        }
    }

    // MARK: - Pairing (S4)

    /// While waiting: pair with the Mac's code instead, so next time there
    /// is no prompt. Shows the Mac's answer to a code sent from a QR code
    /// scanned in the picker.
    @ViewBuilder
    private var pairingPrompt: some View {
        VStack(spacing: PixelHandTheme.Space.md) {
            if pairing.isAwaitingCodeResult {
                VStack(spacing: PixelHandTheme.Space.sm) {
                    DotWave(pitch: 4, label: "Pairing")
                    Text("Pairing…")
                        .font(.subheadline)
                        .foregroundStyle(PixelHandTheme.ink2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pairing with \(peerName)")
            } else if let notice = pairing.notice {
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(PixelHandTheme.danger)
                    .multilineTextAlignment(.center)
            } else if let result = pairing.lastCodeResult,
                      let line = ApprovalStatusCopy.codeResult(result, peerName: peerName) {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(PixelHandTheme.danger)
                    .multilineTextAlignment(.center)
            }
            Button {
                isEnteringCode = true
            } label: {
                HStack(spacing: PixelHandTheme.Space.sm) {
                    PHGlyph(glyph: PixelGlyphs.lock, pitch: CGFloat(PixelPitch.chip), stepsWithType: true)
                    Text("Enter pairing code")
                }
            }
            .buttonStyle(.ph(.tint, size: .regular))
            .disabled(pairing.liveMac == nil || pairing.isAwaitingCodeResult)
            .accessibilityHint("Pairs this device with \(peerName) so it connects without asking next time")
            .accessibilityIdentifier("ph.authorization.enterCode")
        }
    }

    // MARK: - Native button (matches main-page toolbar styling)
    //
    // iOS 26 picks up Liquid Glass via `.glass`. The destructive role tints
    // the label red (matching the main-page disconnect button). On iOS 17
    // we fall back to `.bordered`, which gives the same shape language.

    @ViewBuilder
    private var disconnectButton: some View {
        if isTerminalState {
            Button("Dismiss", role: .cancel, action: onDisconnect)
                .buttonStyle(.ph(.secondary, size: .regular))
                .accessibilityIdentifier("ph.authorization.dismiss")
        } else {
            Button("Disconnect", role: .destructive, action: onDisconnect)
                .buttonStyle(.ph(.destructive, size: .regular))
                .accessibilityIdentifier("ph.authorization.disconnect")
        }
    }

    // MARK: - Native dialog card (Liquid Glass on iOS 26, material on iOS 17)

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.sheet, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            shape
                .fill(.regularMaterial)
                .glassEffect(in: shape)
        } else {
            shape
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 24, y: 12)
        }
        #else
        shape
            .fill(.regularMaterial)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 24, y: 12)
        #endif
    }

    /// One glyph for every state, outside any `switch`, so it's the same
    /// view across status changes and can rearrange its dots from one
    /// state into the next.
    private var statusContent: some View {
        VStack(spacing: PixelHandTheme.Space.lg) {
            PixelScreen(cornerRadius: 18, padding: 12) {
                PixelMorph(glyph: ApprovalGlyph(status: status))
            }

            VStack(spacing: PixelHandTheme.Space.sm) {
                Text(copy.title)
                    .phText(.display)
                    .foregroundStyle(PixelHandTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)

                if !copy.message.isEmpty {
                    Text(copy.message)
                        .font(.body)
                        .foregroundStyle(PixelHandTheme.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
            }
        }
        // Title and message read as one status line.
        .accessibilityElement(children: .combine)
    }

    private var copy: (title: String, message: String) {
        ApprovalStatusCopy.overlay(status: status, peerName: peerName)
    }
}

/// Centres the card while it fits and scrolls once it doesn't (AX sizes,
/// iPhone landscape).
private struct ScrollsWhenTall: ViewModifier {
    func body(content: Content) -> some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content.padding(.vertical, PixelHandTheme.Space.xl)
            }
            .scrollIndicators(.hidden)
        }
    }
}
