//
//  PeerPickerView.swift
//  DeckHandiOS
//

import Loom
import LoomKit
import SwiftUI
import UIKit

/// What this device calls itself in "Please update Pixel Hand on your …".
@MainActor
private var thisDeviceKind: String {
    UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
}

struct PeerPickerView: View {
    /// Set when Loom couldn't start: discovery isn't running, so the picker
    /// says so (with Retry) instead of "Looking for your Mac" forever.
    var startError: String? = nil
    var onRetryStart: () -> Void = {}
    let onConnected: (LoomConnectionHandle, String) -> Void

    @Environment(\.loomContext) private var loomContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LoomQuery(.peers(sort: .name)) private var peers: [LoomPeerSnapshot]

    @State private var connecting: UUID?
    @State private var errorMessage: String?
    @State private var isSettingsPresented = false
    /// Pairing (S4): scanning a Mac's pairing QR code from here dials that
    /// Mac and sends its code once the Mac answers.
    @State private var isScanningInvite = false
    private let pairing = PairedMacsStore.shared

    private enum Layout {
        /// Caps the content column so cards stay a readable width on a 13"
        /// iPad instead of stretching the full display.
        static let column: CGFloat = 520
    }

    var body: some View {
        ZStack {
            PixelHandTheme.brandBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Centred while the content is short, scrolls once there are
                // more Macs than fit. On an iPad the column is capped so the
                // cards don't stretch into letterboxes.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            header(isShort: proxy.size.height < 520)
                            if let startError, peers.isEmpty {
                                startFailedState(startError)
                            } else if peers.isEmpty {
                                searchingState
                            } else {
                                peerList
                            }
                        }
                        .frame(maxWidth: Layout.column)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                    }
                    .scrollIndicators(.hidden)
                }

                if let error = errorMessage {
                    errorBanner(error)
                }

                footer
            }

            // Reachable before connecting: appearance, pointer feel and the
            // welcome tour are all worth changing without a Mac in range.
            settingsButton
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .sheet(isPresented: $isScanningInvite) {
            PairingQRScannerSheet { invite in
                connect(with: invite)
            }
        }
        // The picker is a branded surface, not a system one: it stays dark
        // regardless of the appearance preference, the same way the icon does.
        .foregroundStyle(.white)
        .pixelOnNavy()
        .preferredColorScheme(.dark)
    }

    private var settingsButton: some View {
        VStack {
            HStack(spacing: PixelHandTheme.Space.sm) {
                Spacer()
                GlassCircleButton(glyph: PixelGlyphs.region, label: "Scan pairing code") {
                    isScanningInvite = true
                }
                .accessibilityIdentifier("ph.connect.scanQR")
                GlassCircleButton(glyph: PixelGlyphs.settings, label: "Settings") {
                    isSettingsPresented = true
                }
                .accessibilityIdentifier("ph.connect.settings")
            }
            Spacer()
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .padding(.top, PixelHandTheme.Space.sm)
    }

    // MARK: - Header

    /// The mark, a Geist title and one line. Shrinks on short screens
    /// (landscape) so the first Mac is visible without scrolling.
    @ViewBuilder
    private func header(isShort: Bool) -> some View {
        let layout = isShort
            ? AnyLayout(HStackLayout(spacing: PixelHandTheme.Space.lg))
            : AnyLayout(VStackLayout(spacing: PixelHandTheme.Space.xl))
        layout {
            DeckHandMark(size: isShort ? 64 : 112)

            VStack(alignment: isShort ? .leading : .center, spacing: PixelHandTheme.Space.sm) {
                Text(headerTitle)
                    .phText(.displayLarge)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.66))
            }
            .multilineTextAlignment(isShort ? .leading : .center)
            .contentTransition(.opacity)
        }
        .padding(.horizontal, PixelHandTheme.Space.xl)
        // Clears the glass buttons in the top corner.
        .padding(.top, isShort ? 56 : 64)
        .padding(.bottom, isShort ? PixelHandTheme.Space.xl : 40)
    }

    private var headerTitle: String {
        if !peers.isEmpty { return "Choose a Mac" }
        return startError == nil ? "Looking for your Macs" : "Can’t look for Macs"
    }

    private var headerSubtitle: String {
        if !peers.isEmpty { return "Your own Macs come first." }
        return startError == nil
            ? "Open Pixel Hand on your Mac. Both need the same Wi-Fi or a cable."
            : "The network connection didn’t start."
    }

    // MARK: - Peers

    private var peerList: some View {
        // The user's own iCloud Macs first (stable within each group thanks
        // to the query's name sort) — they're the ones that connect without
        // an approval prompt.
        let orderedPeers = peers.sorted {
            ($0.isSameICloudDevice ? 0 : 1, $0.name) < ($1.isSameICloudDevice ? 0 : 1, $1.name)
        }

        return VStack(spacing: PixelHandTheme.Space.md) {
            ForEach(Array(orderedPeers.enumerated()), id: \.element.id) { index, peer in
                PeerCard(
                    peer: peer,
                    isPaired: pairing.isPaired(deviceID: peer.deviceID),
                    isConnecting: connecting == peer.deviceID,
                    isDimmed: connecting != nil && connecting != peer.deviceID
                ) {
                    connectTo(peer)
                }
                .freeMacBadge(deviceID: peer.deviceID) // Store lane
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .spring(duration: 0.38, bounce: 0.14).delay(Double(index) * 0.05),
                    value: orderedPeers.count
                )
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
    }

    private var searchingState: some View {
        VStack(spacing: PixelHandTheme.Space.lg) {
            DotScan()
            HStack(spacing: PixelHandTheme.Space.sm) {
                StatusPixel(state: .needsYou)
                DotMatrixText("SEARCHING", pitch: 1.6, label: "Searching")
                    .foregroundStyle(PixelHandTheme.Brand.phosphor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Searching for Macs")
        .accessibilityIdentifier("ph.connect.searching")
        .padding(.top, PixelHandTheme.Space.md)
    }

    /// Loom failed to start, so nothing is being searched. Say what went
    /// wrong and offer Retry; Settings stays reachable above.
    private func startFailedState(_ message: String) -> some View {
        VStack(spacing: PixelHandTheme.Space.lg) {
            PHGlyph(glyph: PixelGlyphs.wifi, pitch: CGFloat(PixelPitch.emptyState), showsUnlit: true)
                .foregroundStyle(PixelHandTheme.Brand.phosphor)
            Text("Pixel Hand couldn’t start its network connection.")
                .font(.headline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: onRetryStart)
                .buttonStyle(.ph(.primary, size: .regular))
                .accessibilityIdentifier("ph.connect.retry")
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .padding(.top, PixelHandTheme.Space.md)
    }

    // MARK: - Footer

    private func errorBanner(_ message: String) -> some View {
        PHToast(message: message, isFailure: true)
            .padding(.horizontal, PixelHandTheme.Space.xl)
            .padding(.top, PixelHandTheme.Space.md)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var footer: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            PHGlyph(glyph: PixelGlyphs.wifi, pitch: CGFloat(PixelPitch.badge), stepsWithType: true)
            Text("Same Wi-Fi, or a cable")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.5))
        .padding(.top, PixelHandTheme.Space.lg)
        .padding(.bottom, PixelHandTheme.Space.xxl)
    }

    // MARK: - Actions

    private func connectTo(_ peer: LoomPeerSnapshot) {
        guard connecting == nil else { return }
        guard SubscriptionStore.shared.admitMac(deviceID: peer.deviceID, name: peer.name, retry: { connectTo(peer) }) else { return } // Store lane: one Mac on the free plan

        // A Mac on a different Loom protocol would fail the handshake with a
        // generic error. Say which side to update instead of dialling.
        let compatibility = PeerCompatibility(advertisement: peer.advertisement)
        if let updateMessage = compatibility.updateMessage(thisDevice: thisDeviceKind, peer: "Mac") {
            DeckHandLog.connection.info("📡 Not connecting to \(peer.name, privacy: .public): protocol \(peer.advertisement.protocolVersion), ours \(PeerCompatibility.localProtocolVersion)")
            showError(updateMessage)
            return
        }

        connecting = peer.deviceID
        errorMessage = nil

        DeckHandLog.connection.info("📡 Connecting to \(peer.name, privacy: .public) id=\(peer.deviceID, privacy: .public) nearby=\(peer.isNearby)")
        Task {
            do {
                let handle = try await RemoteConnect.connect(peer, using: loomContext) // S15: VPN peers paired-only, key pinned
                await MainActor.run {
                    DeckHandLog.connection.info("📡 Connected to \(peer.name, privacy: .public); awaiting authorization")
                    connecting = nil
                    onConnected(handle, peer.name)
                }
            } catch {
                await MainActor.run {
                    DeckHandLog.connection.error("📡 Connect failed for \(peer.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    connecting = nil
                    showError("Couldn’t connect to \(peer.name). Make sure Pixel Hand is open on the Mac, then try again.")
                }
            }
        }
    }

    /// A scanned pairing QR code: dial the Mac it names. The code goes out
    /// once that Mac proves the key in the QR code and answers
    /// (ControlSessionModel+Pairing).
    private func connect(with invite: PairingInvite) {
        guard let peer = peers.first(where: { $0.deviceID == invite.macDeviceID }) else {
            showError("That Mac isn’t nearby. Make sure Pixel Hand is open on it and both devices are on the same Wi-Fi.")
            return
        }
        pairing.pendingInvite = invite
        connectTo(peer)
    }

    private func showError(_ message: String) {
        withAnimation(.easeOut(duration: 0.22)) {
            errorMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            // Only clear this message, not a newer one shown since.
            guard errorMessage == message else { return }
            withAnimation(.easeOut(duration: 0.22)) { errorMessage = nil }
        }
    }
}

// MARK: - PeerCard

private struct PeerCard: View {
    let peer: LoomPeerSnapshot
    /// This device is paired with the Mac (S4): it connects without asking.
    let isPaired: Bool
    let isConnecting: Bool
    /// Set while a different peer is connecting, so the tapped card is the
    /// only one that still reads as active.
    let isDimmed: Bool
    let onTap: () -> Void

    /// Set when this Mac runs a different Loom protocol, so the card says
    /// which side to update before anyone taps it.
    private var updateMessage: String? {
        PeerCompatibility(advertisement: peer.advertisement)
            .updateMessage(thisDevice: thisDeviceKind, peer: "Mac")
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
        Button(action: onTap) {
            HStack(spacing: PixelHandTheme.Space.md) {
                GlyphTile(glyph: PixelGlyphs.mac, side: 44, pitch: 3)

                VStack(alignment: .leading, spacing: PixelHandTheme.Space.xs) {
                    HStack(spacing: PixelHandTheme.Space.sm) {
                        Text(peer.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        // Provably the user's own device (private CloudKit
                        // DB record). The Mac still asks to allow it.
                        if peer.isSameICloudDevice {
                            DotMatrixText("MY MAC", pitch: CGFloat(PixelPitch.badge), label: "My Mac", glows: false)
                                .foregroundStyle(PixelHandTheme.Brand.mint)
                                .padding(.horizontal, 7)
                                .frame(height: PixelHandTheme.ControlHeight.badge)
                                .background(Capsule().fill(PixelHandTheme.Brand.mint.opacity(0.14)))
                        }
                    }

                    if let updateMessage {
                        HStack(alignment: .firstTextBaseline, spacing: PixelHandTheme.Space.sm) {
                            StatusPixel(state: .needsYou)
                            Text(updateMessage)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(PixelHandTheme.warning)
                                .lineLimit(3)
                        }
                    } else {
                        HStack(spacing: PixelHandTheme.Space.sm) {
                            StatusPixel(state: peer.isNearby ? .live : .needsYou)
                            Text(statusLine)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.66))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(statusAccessibility)
                    }
                }

                Spacer(minLength: PixelHandTheme.Space.sm)

                if isConnecting {
                    DotWave(pitch: 3, label: "Connecting")
                        .transition(.opacity)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.36))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, PixelHandTheme.Space.lg)
            .padding(.vertical, 14)
            .frame(minHeight: 72)
            .background(
                shape
                    .fill(PixelHandTheme.Brand.screenGradient)
                    .shadow(color: PixelHandTheme.Brand.glow.opacity(isConnecting ? 0.32 : 0), radius: 18)
            )
            .overlay {
                if isConnecting {
                    // Phosphor focus: dotted ring while this Mac answers.
                    shape
                        .strokeBorder(PixelHandTheme.Brand.phosphor.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5]))
                } else {
                    shape.strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: 1)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityValue(isConnecting ? "Connecting" : "")
        .accessibilityIdentifier("ph.connect.macRow")
        .opacity(isDimmed ? 0.4 : 1)
        .disabled(isConnecting || isDimmed)
        .animation(.easeOut(duration: 0.22), value: isConnecting)
        .animation(.easeOut(duration: 0.22), value: isDimmed)
    }

    private var statusLine: String {
        let place = peer.isNearby ? "Nearby" : "Remote"
        return isPaired ? "Paired · \(place)" : place
    }

    /// The whole card as one spoken line: "Studio, my Mac, paired, nearby".
    private var rowAccessibilityLabel: String {
        var parts = [peer.name]
        if peer.isSameICloudDevice { parts.append("my Mac") }
        if let updateMessage {
            parts.append(updateMessage)
        } else {
            if isPaired { parts.append("paired") }
            parts.append(peer.isNearby ? "nearby" : "remote")
        }
        return parts.joined(separator: ", ")
    }

    private var statusAccessibility: String {
        let place = peer.isNearby ? "Nearby" : "Remote"
        return isPaired ? "Paired: connects without asking. \(place)" : place
    }
}
