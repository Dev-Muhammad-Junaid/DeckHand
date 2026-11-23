//
//  PairingCodeEntryView.swift
//  DeckHandiOS
//
//  Pair with the code the Mac shows (S4): type the seven digits or scan the
//  QR code. The check digit is verified as you type, so a typo is caught
//  here and never costs one of the Mac's five tries. Sent through the live
//  session (`PairedMacsStore.submit`); the Mac's answer comes back as
//  `pairing.codeResult`.
//

import SwiftUI
import UIKit

struct PairingCodeEntryView: View {
    let macName: String

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isScanning = false
    @FocusState private var isFieldFocused: Bool
    private let store = PairedMacsStore.shared

    private var parse: PairingCode.ParseResult { PairingCode.parse(text) }

    private var validCode: PairingCode? {
        if case let .valid(code) = parse { return code }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PixelHandTheme.Space.xl) {
                    GlyphTile(glyph: PixelGlyphs.lock, side: 56, pitch: 4)
                        .padding(.top, PixelHandTheme.Space.lg)

                    VStack(spacing: PixelHandTheme.Space.sm) {
                        Text("Code shown on \(macName)")
                            .phText(.display)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        DotMatrixText("7 DIGITS", pitch: 1.6, label: "Seven digits")
                            .foregroundStyle(PixelHandTheme.Brand.phosphor)
                    }

                    codeField

                    footer
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: PixelHandTheme.Space.md) {
                        if store.isAwaitingCodeResult {
                            DotWave(pitch: 4, label: "Pairing")
                                .frame(minHeight: PixelHandTheme.ControlHeight.primary)
                        } else {
                            Button("Pair") { submit(validCode) }
                                .buttonStyle(.ph(.primary, fullWidth: true))
                                .disabled(validCode == nil)
                        }
                        Button {
                            isScanning = true
                        } label: {
                            HStack(spacing: PixelHandTheme.Space.sm) {
                                PHGlyph(glyph: PixelGlyphs.region, pitch: CGFloat(PixelPitch.chip), stepsWithType: true)
                                Text("Scan the QR code instead")
                            }
                        }
                        .buttonStyle(.ph(.secondary, size: .regular, fullWidth: true))
                    }
                }
                .padding(.horizontal, PixelHandTheme.Space.xl)
                .padding(.bottom, PixelHandTheme.Space.xl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(DeckHandTheme.brandBackground().ignoresSafeArea())
            .foregroundStyle(.white)
            .pixelOnNavy()
            .navigationTitle("Pair with \(macName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { isFieldFocused = true }
            .onChange(of: store.codeResultCount) {
                if store.lastCodeResult == .accepted {
                    dismiss()
                } else {
                    text = ""
                }
            }
            .sheet(isPresented: $isScanning) {
                PairingQRScannerSheet { invite in
                    guard let mac = store.liveMac else { return }
                    guard invite.macDeviceID == mac.deviceID,
                          invite.macIdentityKeyID == mac.identityKeyID else {
                        store.notice = "That QR code is from a different Mac. Scan the one \(macName) shows."
                        return
                    }
                    submit(invite.code)
                }
            }
        }
    }

    /// The code in SF Mono on a navy plate; a dotted phosphor ring while it
    /// has focus, mint once the check digit passes.
    private var codeField: some View {
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
        return TextField("123-4567", text: $text)
            .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($isFieldFocused)
            .accessibilityLabel("Pairing code")
            .onChange(of: text) { _, newValue in
                // Keep it to what a code can be.
                if newValue.count > PairingCode.maxInputLength {
                    text = String(newValue.prefix(PairingCode.maxInputLength))
                }
            }
            .padding(.vertical, PixelHandTheme.Space.lg)
            .padding(.horizontal, PixelHandTheme.Space.lg)
            .background(shape.fill(PixelHandTheme.Brand.screen))
            .overlay {
                if validCode != nil {
                    shape.strokeBorder(PixelHandTheme.Brand.mint.opacity(0.8), lineWidth: 2)
                } else if isFieldFocused {
                    shape.strokeBorder(
                        PixelHandTheme.Brand.phosphor.opacity(0.8),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5])
                    )
                } else {
                    shape.strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: 1)
                }
            }
    }

    @ViewBuilder
    private var footer: some View {
        if let notice = store.notice {
            Text(notice).foregroundStyle(PixelHandTheme.danger)
        } else if let result = store.lastCodeResult, let line = ApprovalStatusCopy.codeResult(result, peerName: macName) {
            Text(line).foregroundStyle(PixelHandTheme.danger)
        } else if let hint = ApprovalStatusCopy.codeEntryHint(parse) {
            Text(hint).foregroundStyle(PixelHandTheme.warning)
        } else {
            Text("On \(macName), open Pixel Hand in the menu bar and choose “Pair a Device…”. A paired \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") connects without asking.")
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func submit(_ code: PairingCode?) {
        guard let code else { return }
        Task {
            let sent = await store.submit(code)
            if !sent {
                store.notice = "Not connected to \(macName). Connect again, then pair."
            }
        }
    }
}
