//
//  PairingCodeEntryView.swift
//  DeckHandiOS
//
//  Pair with the code the Mac shows (S4): type the eight digits or scan the
//  QR code. One format everywhere (VQ-005, VQ-029): two groups of four,
//  grouped as you type and drawn in dot-matrix numerals. The field is
//  focused when the sheet opens (VQ-031) and the code goes out by itself
//  once all eight digits pass the check digit, so the number pad never has
//  to be dismissed to reach a button (VQ-030). The check digit is verified
//  as you type, so a typo is caught here and never costs one of the Mac's
//  five tries.
//
//  Sent through the live session (`PairedMacsStore.submit`). Without one
//  (opened from the picker, or the Mac dropped or refused the request) the
//  code is held and this device connects to the Mac first; the session
//  sends it once the Mac answers (`PairedMacsStore.pendingCode`, VQ-003,
//  VQ-037). The Mac's answer comes back as `pairing.codeResult`.
//

import SwiftUI
import UIKit

struct PairingCodeEntryView: View {
    /// A Mac this sheet can pair with.
    struct Target: Identifiable, Hashable {
        var id: UUID
        var name: String
    }

    let macName: String
    /// The Mac's Loom device ID, when known: lets the sheet reconnect to it
    /// if there is no live session.
    var macDeviceID: UUID?
    /// Opened from the picker with several Macs in reach: the person picks
    /// which one shows the code.
    var choices: [Target] = []

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isScanning = false
    @State private var chosen: Target?
    /// The last complete code sent automatically, so the same digits
    /// aren't sent twice after a wrong answer.
    @State private var autoSubmitted: String?
    @FocusState private var isFieldFocused: Bool
    private let store = PairedMacsStore.shared

    private var parse: PairingCode.ParseResult { PairingCode.parse(text) }

    private var validCode: PairingCode? {
        if case let .valid(code) = parse { return code }
        return nil
    }

    private var target: Target? {
        if let chosen { return chosen }
        if let macDeviceID { return Target(id: macDeviceID, name: macName) }
        if let live = store.liveMac { return Target(id: live.deviceID, name: macName) }
        if choices.count == 1 { return choices[0] }
        if let last = store.lastMacDeviceID { return Target(id: last, name: macName) }
        return nil
    }

    private var targetName: String { target?.name ?? macName }

    /// A live session with the target Mac: the code goes out now.
    private var isConnected: Bool {
        store.canSendNow(to: target?.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PixelHandTheme.Space.xl) {
                    GlyphTile(glyph: PixelGlyphs.lock, side: 56, pitch: 4)
                        .padding(.top, PixelHandTheme.Space.lg)

                    VStack(spacing: PixelHandTheme.Space.sm) {
                        Text("Type the code showing on \(targetName)")
                            .phText(.display)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        DotMatrixText("\(PairingCode.length) DIGITS", pitch: 1.6, label: "\(PairingCode.length) digits")
                            .foregroundStyle(PixelHandTheme.Brand.phosphor)
                    }

                    if choices.count > 1 {
                        macChooser
                    }

                    codeField

                    // Right under the field, so it stays above the number
                    // pad on iPhone (VQ-030).
                    actions

                    footer
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        isScanning = true
                    } label: {
                        HStack(spacing: PixelHandTheme.Space.sm) {
                            PHGlyph(glyph: PixelGlyphs.region, pitch: CGFloat(PixelPitch.chip), stepsWithType: true)
                            Text("Scan the QR code instead")
                        }
                    }
                    .buttonStyle(.ph(.secondary, size: .regular, fullWidth: true))
                    .accessibilityIdentifier("ph.pairing.scanQR")
                }
                .padding(.horizontal, PixelHandTheme.Space.xl)
                .padding(.bottom, PixelHandTheme.Space.xl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.never)
            .background(PixelHandTheme.brandBackground().ignoresSafeArea())
            .foregroundStyle(.white)
            .pixelOnNavy()
            // VQ-086: "Pair with Muhammad’s MacBook…" truncated; the Mac's
            // name is in the heading under it.
            .navigationTitle("Pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // VQ-086: no second Pair button on the keyboard's bar; it
                // floated over the footer on iPhone. The one under the
                // field stays above the number pad (VQ-030), and a full
                // code sends itself.
            }
            .defaultFocus($isFieldFocused, true)
            .task {
                // A sheet's field can't take focus until the sheet has
                // settled; asking once on appear was ignored (VQ-031).
                try? await Task.sleep(for: .milliseconds(350))
                isFieldFocused = true
            }
            .onChange(of: store.codeResultCount) {
                if store.lastCodeResult == .accepted {
                    dismiss()
                } else {
                    text = ""
                    autoSubmitted = nil
                    isFieldFocused = true
                }
            }
            .sheet(isPresented: $isScanning) {
                PairingQRScannerSheet { invite in
                    scanned(invite)
                }
            }
        }
    }

    // MARK: - Pieces

    private var macChooser: some View {
        Picker("Mac", selection: Binding(
            get: { target ?? choices[0] },
            set: { chosen = $0 }
        )) {
            ForEach(choices) { choice in
                Text(choice.name).tag(choice)
            }
        }
        .pickerStyle(.menu)
        .tint(.white)
        .accessibilityIdentifier("ph.pairing.macChooser")
    }

    /// The code in dot-matrix numerals on a navy plate, grouped "4821 0934"
    /// as it is typed; unlit cells stand for the digits still to come. A
    /// dotted phosphor ring while it has focus, mint once the check digit
    /// passes. The text field underneath takes the typing and VoiceOver.
    private var codeField: some View {
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
        return ZStack {
            TextField("", text: $text)
                .font(.system(.largeTitle, design: .monospaced))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFieldFocused)
                // The digits are drawn by the dot-matrix layer above.
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel("Pairing code")
                // Read digit by digit ("4 8 2 1, 0 9 3 4"), not as one number.
                .accessibilityValue(text.map { $0.isNumber ? String($0) : "," }.joined(separator: " "))
                .accessibilityIdentifier("ph.pairing.codeField")
                .onChange(of: text) { _, newValue in
                    let grouped = PairingCode.grouped(newValue)
                    if grouped != newValue {
                        text = grouped
                        return
                    }
                    autoSubmitIfComplete()
                }

            // Two groups of four with a gap; unlit cells stand for the
            // digits still to come.
            HStack(spacing: PixelHandTheme.Space.lg) {
                ForEach(Array(displayGroups.enumerated()), id: \.offset) { _, group in
                    DotMatrixText(group, pitch: 3.2, label: nil, showsUnlit: true, glows: true, stepsWithType: true)
                }
            }
            .foregroundStyle(validCode != nil ? PixelHandTheme.Brand.mint : PixelHandTheme.Brand.phosphor)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .padding(.vertical, PixelHandTheme.Space.lg)
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .frame(maxWidth: .infinity)
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
        .contentShape(shape)
        .onTapGesture { isFieldFocused = true }
    }

    /// What's typed so far in groups of four, padded with blanks where
    /// digits are still to come so the plate keeps its width.
    private var displayGroups: [String] {
        let digits = text.filter(\.isNumber)
        let padded = digits + String(repeating: " ", count: max(0, PairingCode.length - digits.count))
        let size = PairingCode.groupSize
        return stride(from: 0, to: PairingCode.length, by: size).map { start in
            String(padded.dropFirst(start).prefix(size))
        }
    }

    @ViewBuilder
    private var actions: some View {
        if store.isAwaitingCodeResult {
            VStack(spacing: PixelHandTheme.Space.sm) {
                DotWave(pitch: 4, label: "Pairing")
                Text(isConnected ? "Pairing…" : "Connecting to \(targetName)…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(minHeight: PixelHandTheme.ControlHeight.primary)
        } else if isConnected {
            Button("Pair") { submit(validCode) }
                .buttonStyle(.ph(.primary, fullWidth: true))
                .disabled(validCode == nil)
                .accessibilityIdentifier("ph.pairing.pair")
        } else {
            // No live session with this Mac (it dropped or refused the
            // request, or this sheet came from the picker): connect, then
            // send the code (VQ-037).
            Button("Connect and pair") { submit(validCode) }
                .buttonStyle(.ph(.primary, fullWidth: true))
                .disabled(validCode == nil || target == nil)
                .accessibilityHint("Connects to \(targetName), then sends the code")
                .accessibilityIdentifier("ph.pairing.reconnect")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let notice = store.notice {
            Text(notice).foregroundStyle(PixelHandTheme.danger)
        } else if let result = store.lastCodeResult, let line = ApprovalStatusCopy.codeResult(result, peerName: targetName) {
            Text(line).foregroundStyle(PixelHandTheme.danger)
        } else if let hint = ApprovalStatusCopy.codeEntryHint(parse) {
            Text(hint).foregroundStyle(PixelHandTheme.warning)
        } else if !isConnected, target != nil {
            Text("Not connected to \(targetName) now. Pixel Hand connects again and sends the code.")
                .foregroundStyle(.white.opacity(0.7))
        } else {
            Text("No code on \(targetName)? Choose “Pair a device” in Pixel Hand’s menu bar there. A paired \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") connects without asking.")
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Sending

    private func autoSubmitIfComplete() {
        guard let code = validCode, autoSubmitted != code.digits,
              !store.isAwaitingCodeResult, target != nil else { return }
        autoSubmitted = code.digits
        submit(code)
    }

    private func submit(_ code: PairingCode?) {
        guard let code else { return }
        if isConnected {
            Task {
                let sent = await store.submit(code)
                if !sent {
                    // The session ended between the check and the send.
                    holdAndConnect(code)
                }
            }
        } else {
            holdAndConnect(code)
        }
    }

    /// Keeps the code and connects to the Mac; the session sends it.
    private func holdAndConnect(_ code: PairingCode) {
        guard let target else {
            store.notice = "Choose the Mac that shows the code."
            return
        }
        store.holdForNextConnection(code, macDeviceID: target.id, macName: target.name)
        MacSwitcher.shared.connectForPairing(target.id)
        dismiss()
    }

    private func scanned(_ invite: PairingInvite) {
        if let mac = store.liveMac {
            guard invite.macDeviceID == mac.deviceID,
                  invite.macIdentityKeyID == mac.identityKeyID else {
                store.notice = "That QR code is from a different Mac. Scan the one \(targetName) shows."
                return
            }
            Task { await store.submit(invite.code) }
        } else {
            // Not connected: the invite carries the Mac and its key.
            store.pendingInvite = invite
            MacSwitcher.shared.connectForPairing(invite.macDeviceID)
            dismiss()
        }
    }
}
