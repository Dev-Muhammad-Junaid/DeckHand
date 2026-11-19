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
            Form {
                Section {
                    TextField("123-4567", text: $text)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
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
                } header: {
                    Text("Code shown on \(macName)")
                } footer: {
                    footer
                }

                Section {
                    Button {
                        isScanning = true
                    } label: {
                        Label("Scan the QR Code Instead", systemImage: "qrcode.viewfinder")
                    }
                }
            }
            .navigationTitle("Pair with \(macName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isAwaitingCodeResult {
                        ProgressView()
                    } else {
                        Button("Pair") { submit(validCode) }
                            .disabled(validCode == nil)
                    }
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

    @ViewBuilder
    private var footer: some View {
        if let notice = store.notice {
            Text(notice).foregroundStyle(DeckHandTheme.danger)
        } else if let result = store.lastCodeResult, let line = ApprovalStatusCopy.codeResult(result, peerName: macName) {
            Text(line).foregroundStyle(DeckHandTheme.danger)
        } else if let hint = ApprovalStatusCopy.codeEntryHint(parse) {
            Text(hint).foregroundStyle(DeckHandTheme.warning)
        } else {
            Text("On \(macName), open Pixel Hand in the menu bar and choose “Pair a Device…”. A paired \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") connects without asking.")
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
