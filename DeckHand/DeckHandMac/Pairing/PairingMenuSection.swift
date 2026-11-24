//
//  PairingMenuSection.swift
//  DeckHandMac
//
//  The menu-bar panel's pairing part (S4, restyled for UX-012): the paired
//  devices, each with a visible "Forget…" that confirms in place; a status
//  line while a code is showing or pairing is paused; and "Pair a device…",
//  which opens the "Pair a device" window (`PairDeviceWindow`) with the QR
//  code and the seven-digit code. Forgetting a connected device ends its
//  session.
//

import SwiftUI

struct PairingMenuSection: View {
    @EnvironmentObject private var authManager: DeviceAuthorizationManager
    @ObservedObject private var store = PairedDeviceStore.shared
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            MacSectionLabel(text: "Paired")
                .padding(.horizontal, PixelHandTheme.Space.lg)

            if store.devices.isEmpty {
                Text("None yet. A paired iPhone or iPad connects without the Allow prompt.")
                    .font(.callout)
                    .foregroundStyle(PixelHandTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PixelHandTheme.Space.lg)
            } else {
                ForEach(store.devices) { device in
                    PairedDeviceRow(device: device, isConnected: authManager.liveRefs.contains(device.ref))
                }
            }

            PairingStatusLine()

            HStack(spacing: PixelHandTheme.Space.sm) {
                Button("Pair a device…") { PairDeviceWindow.shared.open(authManager) }
                    .buttonStyle(.macPrimary)
                    .disabled(authManager.pairingDisplay.isLockedOut)
                    .help("Show a code to scan or type on an iPhone or iPad. A paired device connects without asking.")
                    .accessibilityIdentifier("ph.mac.pairDevice")
                if case .code = authManager.pairingDisplay {
                    Button("Show code") { PairDeviceWindow.shared.open(authManager) }
                        .buttonStyle(.macSecondary)
                        .help("Bring the Pair a device window forward")
                        .accessibilityLabel("Show pairing code")
                        .accessibilityIdentifier("ph.mac.showCode")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PixelHandTheme.Space.lg)
            .padding(.top, PixelHandTheme.Space.xs)
        }
        // Moves an expired code or a finished lockout on while the panel is open.
        .onReceive(ticker) { _ in authManager.refreshPairingDisplay() }
    }
}

private extension PairingCodeWindow.Display {
    var isLockedOut: Bool {
        if case .lockedOut = self { return true }
        return false
    }
}

// MARK: - Status line

/// One line under the paired list while a code is live, pairing is paused,
/// or a device just paired.
private struct PairingStatusLine: View {
    @EnvironmentObject private var authManager: DeviceAuthorizationManager

    var body: some View {
        Group {
            switch authManager.pairingDisplay {
            case .none:
                EmptyView()

            case let .code(_, expiresAt, _):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = expiresAt.timeIntervalSince(context.date)
                    HStack(spacing: PixelHandTheme.Space.sm) {
                        MacDotBeam(lit: PairingCodeDisplay.beamLitCells(remaining: remaining), dot: 4, gap: 2)
                        Text("Code showing · \(PairingCodeDisplay.countdown(remaining: remaining)) left")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(PixelHandTheme.ink2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Pairing code showing, \(PairingCodeDisplay.spokenCountdown(remaining: remaining))")
                }

            case let .lockedOut(until):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(1, Int(until.timeIntervalSince(context.date).rounded(.up)))
                    HStack(alignment: .firstTextBaseline, spacing: PixelHandTheme.Space.sm) {
                        MacGlyph(glyph: PixelGlyphs.lock, pitch: 1.4, accent: PixelHandTheme.warning)
                            .foregroundStyle(PixelHandTheme.warning)
                        Text("Too many wrong codes. Pairing is paused for \(ApprovalStatusCopy.durationText(seconds: left)).")
                            .font(.callout)
                            .foregroundStyle(PixelHandTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }

            case .paired:
                HStack(spacing: PixelHandTheme.Space.sm) {
                    LivePixel(color: PixelHandTheme.success, size: 6)
                    Text("Paired.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(PixelHandTheme.success)
                }
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    authManager.cancelPairingCode()
                }
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
    }
}

// MARK: - Paired device row

private struct PairedDeviceRow: View {
    let device: PairedDevice
    let isConnected: Bool
    @EnvironmentObject private var authManager: DeviceAuthorizationManager
    @State private var isConfirming = false

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            MacDeviceIcon(systemImage: device.kind.systemImage, isLive: isConnected)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(isConnected ? "Connected now" : "Last seen \(device.lastSeenAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink2)
            }
            Spacer(minLength: PixelHandTheme.Space.xs)
            if isConfirming {
                Button("Cancel") { isConfirming = false }
                    .buttonStyle(.macQuiet)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Keep \(device.name)")
                    .accessibilityIdentifier("ph.mac.cancelForget")
                Button("Forget") {
                    authManager.forget(device.ref)
                    isConfirming = false
                }
                .buttonStyle(.macDestructive)
                .help(isConnected ? "Unpair and disconnect now. It must be allowed or paired again." : "Unpair. It must be allowed or paired again.")
                .accessibilityLabel("Confirm forget \(device.name)")
                .accessibilityIdentifier("ph.mac.confirmForget")
            } else {
                Button("Forget…") { isConfirming = true }
                    .buttonStyle(.macSecondary)
                    .help("Unpair \(device.name)")
                    .accessibilityLabel("Forget \(device.name)")
                    .accessibilityIdentifier("ph.mac.forget")
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.mac.pairedDeviceRow")
    }
}

/// A device's symbol in a 28 pt circle; a mint pixel on its corner while
/// it is connected.
struct MacDeviceIcon: View {
    let systemImage: String
    var isLive = false
    var tint: Color = PixelHandTheme.accent

    var body: some View {
        Image(systemName: systemImage)
            .font(.body)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(Circle().fill(PixelHandTheme.fill))
            .overlay(alignment: .bottomTrailing) {
                if isLive {
                    LivePixel(color: PixelHandTheme.success, size: 6)
                        .offset(x: 1, y: 1)
                }
            }
            .accessibilityHidden(true)
    }
}
