//
//  PairingMenuSection.swift
//  DeckHandMac
//
//  The menu bar panel's pairing section (S4): "Pair a Device…" shows a
//  seven-digit code and its QR code for five minutes; below it, the paired
//  devices, each with "Forget". Forgetting a device that is connected ends
//  its session.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct PairingMenuSection: View {
    @EnvironmentObject private var authManager: DeviceAuthorizationManager
    @ObservedObject private var store = PairedDeviceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PAIRED DEVICES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if case .none = authManager.pairingDisplay {
                    Button("Pair a Device…") { authManager.showPairingCode() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DeckHandTheme.accent)
                        .help("Show a code to type or scan on an iPhone or iPad. A paired device connects without asking.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            PairingCodePanel()

            if store.devices.isEmpty {
                Text("None yet. Paired iPhones and iPads connect without the Allow prompt.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            } else {
                ForEach(store.devices) { device in
                    PairedDeviceRow(device: device, isConnected: authManager.liveRefs.contains(device.ref))
                }
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Code panel

private struct PairingCodePanel: View {
    @EnvironmentObject private var authManager: DeviceAuthorizationManager
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch authManager.pairingDisplay {
            case .none:
                EmptyView()

            case let .code(code, expiresAt, attemptsLeft):
                VStack(spacing: 8) {
                    if let invite = authManager.pairingInvite, let qr = QRCodeImage.make(invite.payload) {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 132, height: 132)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                            .accessibilityLabel("Pairing QR code")
                    }
                    Text(code.formatted)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityLabel("Pairing code \(code.digits.map(String.init).joined(separator: " "))")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(expiresAt.timeIntervalSince(context.date).rounded(.up)))
                        Text("Scan it or type it in Pixel Hand on your iPhone or iPad. Expires in \(left / 60):\(String(format: "%02d", left % 60)).")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if attemptsLeft < PairingCodeWindow.maxWrongAttempts {
                        Text("\(PairingCodeWindow.maxWrongAttempts - attemptsLeft) wrong code(s) entered. \(attemptsLeft) left.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DeckHandTheme.warning)
                    }
                    Button("Cancel") { authManager.cancelPairingCode() }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

            case let .lockedOut(until):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(1, Int(until.timeIntervalSince(context.date).rounded(.up)))
                    Label("Too many wrong codes. Pairing is paused for \(ApprovalStatusCopy.durationText(seconds: left)).", systemImage: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DeckHandTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            case .paired:
                Label("Paired.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DeckHandTheme.success)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        authManager.cancelPairingCode()
                    }
            }
        }
        // Moves an expired code or a finished lockout on while the panel is open.
        .onReceive(ticker) { _ in authManager.refreshPairingDisplay() }
    }
}

// MARK: - Paired device row

private struct PairedDeviceRow: View {
    let device: PairedDevice
    let isConnected: Bool
    @EnvironmentObject private var authManager: DeviceAuthorizationManager
    @State private var isConfirming = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.kind.systemImage)
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DeckHandTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(isConnected ? "Connected" : "Last seen \(device.lastSeenAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isConfirming {
                Button("Cancel") { isConfirming = false }
                    .controlSize(.small)
                Button("Forget") {
                    authManager.forget(device.ref)
                    isConfirming = false
                }
                .controlSize(.small)
                .tint(DeckHandTheme.danger)
                .help(isConnected ? "Unpair and disconnect now. It must be allowed or paired again." : "Unpair. It must be allowed or paired again.")
            } else {
                Button("Forget…") { isConfirming = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - QR

enum QRCodeImage {
    /// A crisp QR image for `text`, or `nil` if Core Image can't make one.
    static func make(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
