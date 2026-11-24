//
//  MacMenuBarView.swift
//  DeckHandMac
//
//  The menu-bar panel (UX-012, board "Mac panel"): 340 pt, system text
//  styles so it follows the Mac's text size, and the Pixel Hand tokens.
//
//  Header: the icon's hand tile, this Mac's name and what it is doing.
//  Requests: Deny / Pair… / Allow, amber. Devices: each connected device
//  with its link badge and a visible Disconnect; the lock state when this
//  Mac is locked. Paired: Forget… and Pair a device… (`PairingMenuSection`).
//  Permissions: a live pixel per permission and a labelled fix button.
//  Footer: updates, crash reports, the version line and Quit.
//  Nothing is hover-only; every control is a labelled button.
//

import Combine
import Loom
import LoomKit
import SwiftUI

struct MacMenuBarView: View {
    @Environment(\.loomContext) private var loomContext
    @EnvironmentObject private var authManager: DeviceAuthorizationManager
    @EnvironmentObject private var daemon: MacDaemon
    @LoomQuery(.connections(sort: .connectedAtDescending)) private var connections: [LoomConnectionSnapshot]
    @LoomQuery(.peers(sort: .name)) private var peers: [LoomPeerSnapshot]

    let receiver: ControlReceiver

    @ObservedObject private var permissions = PermissionsMonitor.shared
    @ObservedObject private var updater = AppUpdater.shared

    /// Mirrors `DeckHandDiagnostics.isEnabledByUser` (absent = on).
    @AppStorage(DeckHandDiagnostics.enabledKey) private var shareCrashReports = true

    /// `MacLockMonitor` isn't observable; the panel re-reads it each second.
    @State private var isLocked = MacLockMonitor.shared.state.isLocked

    private static let width: CGFloat = 340

    var body: some View {
        let authorizedConnections = connections.filter { $0.state == .connected && authManager.isAuthorized(peerID: $0.peerID) }

        VStack(alignment: .leading, spacing: 0) {
            header(connected: authorizedConnections.count)

            if let startupError = daemon.fatalStartupError {
                Text(startupError)
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .padding(.horizontal, PixelHandTheme.Space.lg)
                    .padding(.bottom, PixelHandTheme.Space.md)
            }

            if !authManager.pendingConnections.isEmpty {
                PanelDivider()
                PanelSection {
                    MacSectionLabel(text: "Asking to connect", color: PixelHandTheme.warning)
                        .padding(.horizontal, PixelHandTheme.Space.lg)
                    ForEach(authManager.pendingConnections) { connection in
                        PendingConnectionRow(
                            connection: connection,
                            loomContext: loomContext,
                            deviceSystemImage: deviceSystemImage(for: connection)
                        )
                    }
                }
            }

            // A nearby iPhone or iPad on a different Loom protocol can't
            // connect (its handshake fails), so say which side to update.
            if !outdatedPeers.isEmpty {
                PanelDivider()
                PanelSection {
                    MacSectionLabel(text: "Needs an update", color: PixelHandTheme.warning)
                    ForEach(outdatedPeers, id: \.peer.id) { item in
                        HStack(alignment: .top, spacing: PixelHandTheme.Space.md) {
                            MacDeviceIcon(systemImage: item.peer.deviceType.systemImage, tint: PixelHandTheme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.peer.name)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Text(item.message)
                                    .font(.caption)
                                    .foregroundStyle(PixelHandTheme.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, PixelHandTheme.Space.lg)
            }

            PanelDivider()

            PanelSection {
                MacSectionLabel(text: "Devices")
                    .padding(.horizontal, PixelHandTheme.Space.lg)
                if authorizedConnections.isEmpty {
                    waitingState
                } else {
                    if isLocked {
                        lockedNote
                    }
                    ForEach(authorizedConnections) { connection in
                        ConnectionRow(
                            connection: connection,
                            loomContext: loomContext,
                            deviceSystemImage: deviceSystemImage(for: connection),
                            isLocked: isLocked
                        )
                    }
                }
            }

            MacTransferSection() // Sharing lane: Send, prompts, transfers (S1/S2)

            PanelDivider()

            // ── Pairing (S4) ──────────────────────────────────────────
            PanelSection {
                PairingMenuSection()
            }

            PanelDivider()

            permissionsSection

            PanelDivider()

            footer
        }
        .frame(width: Self.width)
        .background(PixelHandTheme.elevated)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            let locked = MacLockMonitor.shared.state.isLocked
            if locked != isLocked { isLocked = locked }
        }
    }

    // MARK: Header

    private func header(connected: Int) -> some View {
        let failed = daemon.fatalStartupError != nil
        let running = loomContext.isRunning
        let status = MacPanelCopy.headerStatus(
            isRunning: running,
            failedToStart: failed,
            connected: connected,
            pending: authManager.pendingConnections.count,
            isLocked: isLocked && connected > 0
        )
        return HStack(spacing: PixelHandTheme.Space.md) {
            MacHandTile(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(PairDeviceView.macName)
                    .font(.headline)
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(failed ? PixelHandTheme.danger : PixelHandTheme.ink2)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ph.mac.header")
            Spacer(minLength: 0)
            if failed {
                MacDotText("ERROR", pitch: 1.4, label: "Failed to start")
                    .foregroundStyle(PixelHandTheme.danger)
            } else if isLocked && connected > 0 {
                MacDotText("LOCKED", pitch: 1.4, label: "This Mac is locked")
                    .foregroundStyle(PixelHandTheme.warning)
            } else if running {
                // Lit only while something is live (`02-Design-System.md` §6).
                if connected > 0 {
                    LivePixel(color: PixelHandTheme.success, size: 8)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(PixelHandTheme.fill2)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .padding(.vertical, PixelHandTheme.Space.md)
    }

    // MARK: Devices

    private var waitingState: some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            PixelScreen(cornerRadius: 10, padding: 6) {
                PixelGlyph(bitmap: PixelArt.hand, pitch: 1.4, glows: false)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("No device connected")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PixelHandTheme.ink)
                Text("Open Pixel Hand on your iPhone or iPad and choose \(PairDeviceView.macName).")
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ph.mac.waitingState")
    }

    private var lockedNote: some View {
        HStack(alignment: .top, spacing: PixelHandTheme.Space.sm) {
            MacGlyph(glyph: PixelGlyphs.lock, pitch: 1.6, accent: PixelHandTheme.warning)
                .foregroundStyle(PixelHandTheme.warning)
            Text("This Mac is locked. Connected devices can type the password from their keyboard.")
                .font(.caption)
                .foregroundStyle(PixelHandTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PixelHandTheme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                .fill(PixelHandTheme.warningTint)
        )
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .accessibilityElement(children: .combine)
    }

    // MARK: Permissions

    // Live status per TCC permission, re-checked every 2 s while the panel
    // is open, so toggles flipped in System Settings show at once. Each
    // missing one has a labelled button to the exact Settings pane.
    private var permissionsSection: some View {
        PanelSection {
            MacSectionLabel(text: "Permissions")
            PermissionRow(
                title: "Accessibility",
                detail: "Pointer, keyboard and dialogs",
                status: permissions.accessibility
            ) { permissions.fixAccessibility() }

            PermissionRow(
                title: "Screen Recording",
                detail: "Screenshots and the live screen",
                status: permissions.screenRecording
            ) { permissions.fixScreenRecording() }

            PermissionRow(
                title: "Notifications",
                detail: "Connection requests",
                status: permissions.notifications
            ) { permissions.fixNotifications() }

            if permissions.accessibility == .denied || permissions.screenRecording == .denied {
                Text("Turned it on but still listed as off? Development builds change identity on every rebuild: remove Pixel Hand from the Settings list and add it back.")
                    .font(.caption2)
                    .foregroundStyle(PixelHandTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        // TCC has no change notifications; polling is the only way.
        .onAppear { permissions.refresh() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            permissions.refresh()
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            Toggle("Share crash reports", isOn: $shareCrashReports)
                .toggleStyle(.checkbox)
                .font(.callout)
                .foregroundStyle(PixelHandTheme.ink2)
                .help("Sends crash, hang and performance reports to the developer. Never includes your screen, your device names or who you are.")
                .onChange(of: shareCrashReports) { _, enabled in
                    DeckHandDiagnostics.setEnabled(enabled)
                }
                .accessibilityIdentifier("ph.mac.shareCrashReports")
            HStack(spacing: PixelHandTheme.Space.sm) {
                MacDotText(
                    VersionLine.text(version: Self.version, build: Self.build),
                    pitch: 1.3,
                    label: VersionLine.spoken(version: Self.version, build: Self.build)
                )
                .foregroundStyle(PixelHandTheme.ink3)
                Spacer(minLength: PixelHandTheme.Space.xs)
                Button("Updates…") { updater.checkForUpdates() }
                    .buttonStyle(.macSecondary)
                    .disabled(!updater.canCheckForUpdates)
                    .help(updater.isConfigured ? "Check for a newer version of Pixel Hand" : "Updates aren't set up in this build")
                    .accessibilityLabel("Check for updates")
                    .accessibilityIdentifier("ph.mac.checkForUpdates")
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.macSecondary)
                    .keyboardShortcut("q")
                    .help("Quit Pixel Hand")
                    .accessibilityLabel("Quit Pixel Hand")
                    .accessibilityIdentifier("ph.mac.quit")
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .padding(.top, PixelHandTheme.Space.md)
        .padding(.bottom, PixelHandTheme.Space.lg)
    }

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    // MARK: Helpers

    /// Nearby remotes whose Loom protocol differs from this Mac's, with the
    /// "Please update Pixel Hand on your …" line for each.
    private var outdatedPeers: [(peer: LoomPeerSnapshot, message: String)] {
        peers.compactMap { peer in
            guard peer.deviceType != .mac else { return nil }
            let remote = switch peer.deviceType {
            case .iPad: "iPad"
            case .iPhone: "iPhone"
            default: "iPhone or iPad"
            }
            guard let message = PeerCompatibility(advertisement: peer.advertisement)
                .updateMessage(thisDevice: "Mac", peer: remote) else { return nil }
            return (peer, message)
        }
    }

    /// Resolves iPhone vs iPad (etc.) from the live peer list; Pixel Hand remote is iOS-only so unknown falls back to phone.
    private func deviceSystemImage(for connection: LoomConnectionSnapshot) -> String {
        guard let peer = peers.first(where: { $0.id == connection.peerID }) else {
            return DeviceType.iPhone.systemImage
        }
        switch peer.deviceType {
        case .unknown:
            return DeviceType.iPhone.systemImage
        default:
            return peer.deviceType.systemImage
        }
    }
}

// MARK: - Layout pieces

/// A section: 12 pt above and below, 8 pt between rows.
private struct PanelSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PixelHandTheme.Space.md)
    }
}

private struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(PixelHandTheme.hairline)
            .frame(height: 0.5)
            .padding(.horizontal, PixelHandTheme.Space.lg)
            .accessibilityHidden(true)
    }
}

// MARK: - PermissionRow

private struct PermissionRow: View {
    let title: String
    let detail: String
    let status: PermissionsMonitor.Status
    let onFix: () -> Void

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            statusDot
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PixelHandTheme.ink)
                if status != .granted {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(PixelHandTheme.ink2)
                }
            }
            Spacer(minLength: PixelHandTheme.Space.xs)
            if status == .granted {
                Text("On")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PixelHandTheme.success)
            } else {
                Button("Turn on…", action: onFix)
                    .buttonStyle(.macSecondary)
                    .help("Open System Settings to turn on \(title)")
                    .accessibilityLabel("Turn on \(title)")
                    .accessibilityIdentifier("ph.mac.turnOn" + title.replacingOccurrences(of: " ", with: ""))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(status == .granted ? "on" : "off")")
        .accessibilityIdentifier("ph.mac.permission" + title.replacingOccurrences(of: " ", with: ""))
    }

    @ViewBuilder private var statusDot: some View {
        switch status {
        case .granted:
            LivePixel(color: PixelHandTheme.success, size: 7)
        case .denied:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(PixelHandTheme.warning)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        case .unknown:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(PixelHandTheme.fill2)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - ConnectionRow

private struct ConnectionRow: View {
    let connection: LoomConnectionSnapshot
    let loomContext: LoomContext
    let deviceSystemImage: String
    let isLocked: Bool
    @EnvironmentObject private var authManager: DeviceAuthorizationManager

    var body: some View {
        HStack(alignment: .center, spacing: PixelHandTheme.Space.md) {
            MacDeviceIcon(systemImage: deviceSystemImage, isLive: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.peerName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PixelHandTheme.ink2)
                }
                HStack(spacing: PixelHandTheme.Space.sm) {
                    HostLinkBadge(connectionID: connection.id) // Network lane (S13)
                    if isLocked {
                        MacDotText("LOCKED", pitch: 1.3, label: "Mac locked")
                            .foregroundStyle(PixelHandTheme.warning)
                    }
                }
                // The live connection id, for matching against the remote's
                // log and spotting silent session swaps.
                Text("session \(connection.id.uuidString.prefix(8))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(PixelHandTheme.ink3)
                    .textSelection(.enabled)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: PixelHandTheme.Space.xs)
            Button("Disconnect") {
                authManager.removeAndDisconnect(connection: connection, loomContext: loomContext)
            }
            .buttonStyle(.macSecondary)
            .help("Disconnect and end this session's access. A paired device stays paired; use Forget… under Paired.")
            .accessibilityLabel("Disconnect \(connection.peerName)")
            .accessibilityIdentifier("ph.mac.disconnect")
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.mac.deviceRow")
    }

    private var subtitle: String {
        "Connected \(connection.connectedAt.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - PendingConnectionRow

private struct PendingConnectionRow: View {
    let connection: LoomConnectionSnapshot
    let loomContext: LoomContext
    let deviceSystemImage: String
    @EnvironmentObject private var authManager: DeviceAuthorizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            HStack(alignment: .center, spacing: PixelHandTheme.Space.md) {
                MacDeviceIcon(systemImage: deviceSystemImage, tint: PixelHandTheme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.peerName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PixelHandTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Group {
                        if let requestedAt = authManager.pendingRequestedDate(for: connection.id) {
                            Text("Wants to control this Mac · \(requestedAt.formatted(.relative(presentation: .named)))")
                        } else {
                            Text("Wants to control this Mac")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink2)
                }
                Spacer(minLength: 0)
            }

            // Allow (this session), Deny, or Pair: show a code the device
            // can enter to connect without asking from now on. Labelled
            // buttons, so the choice never rests on telling colours apart.
            // Deny sits apart from the primary Allow.
            HStack(spacing: PixelHandTheme.Space.sm) {
                Button("Deny") {
                    authManager.reject(connection: connection, loomContext: loomContext)
                }
                .buttonStyle(.macDestructive)
                .help("Refuse this request")
                .accessibilityLabel("Deny \(connection.peerName)")
                .accessibilityIdentifier("ph.mac.deny")
                Spacer(minLength: 0)
                Button("Pair…") {
                    PairDeviceWindow.shared.open(authManager)
                }
                .buttonStyle(.macSecondary)
                .help("Show a pairing code to enter on the device. Paired devices connect without asking.")
                .accessibilityLabel("Pair \(connection.peerName)")
                .accessibilityIdentifier("ph.mac.pairRequest")
                Button("Allow") {
                    authManager.authorize(connection: connection)
                }
                .buttonStyle(.macPrimary)
                .help("Allow for this session")
                .accessibilityLabel("Allow \(connection.peerName)")
                .accessibilityIdentifier("ph.mac.allow")
            }
            .padding(.leading, 28 + PixelHandTheme.Space.md)
        }
        .padding(PixelHandTheme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .fill(PixelHandTheme.warningTint)
        )
        .padding(.horizontal, PixelHandTheme.Space.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.mac.pendingRow")
    }
}
