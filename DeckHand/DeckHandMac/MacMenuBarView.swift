//
//  MacMenuBarView.swift
//  DeckHandMac
//
//  The menu-bar panel (UX-012, board "Mac panel"): 340 pt, system text
//  styles so it follows the Mac's text size, and the Pixel Hand tokens.
//
//  Header: the icon's hand tile, this Mac's name and what it is doing.
//  Then, while transfers exist or finished in the last hour, a Devices |
//  Transfers switch (OR-13).
//  Devices: one list of iPhones and iPads, each asking (amber, Deny / Pair /
//  Allow), connected (live pixel) or paired and away (dim), with Forget and
//  Disconnect in each row's menu and one "Pair a device" under it (OR-08,
//  `MacDevicesList`); the Send section with a one-line transfer summary;
//  permissions with a fading status dot each (OR-09).
//  Transfers: under way, then the last hour's (`MacTransfersTab`).
//  Footer: updates, crash reports, the version line and Quit.
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
    @ObservedObject private var transfers = MacTransferService.shared

    /// Devices or Transfers (OR-13).
    @State private var tab: MacPanelTabs.Tab = .devices

    /// Mirrors `DeckHandDiagnostics.isEnabledByUser` (absent = on).
    @AppStorage(DeckHandDiagnostics.enabledKey) private var shareCrashReports = true

    /// `MacLockMonitor` isn't observable; the panel re-reads it each second.
    @State private var isLocked = MacLockMonitor.shared.state.isLocked
    /// Takes keyboard focus when the panel opens, so no button (least of
    /// all Forget) starts out focused and Return or Space does nothing
    /// (VQ-021, VQ-042).
    @FocusState private var isFocusSinkFocused: Bool

    private static let width: CGFloat = 340

    var body: some View {
        let authorizedConnections = connections.filter { $0.state == .connected && authManager.isAuthorized(peerID: $0.peerID) }

        VStack(alignment: .leading, spacing: 0) {
            focusSink

            header(connected: authorizedConnections.count)

            if let refusal = authManager.recentRefusal,
               authManager.pendingConnections.isEmpty,
               let copy = MacPanelCopy.turnedAway(name: refusal.deviceName, reason: refusal.reason) {
                turnedAwayNote(copy, reason: refusal.reason)
            }

            if let startupError = daemon.fatalStartupError {
                Text(startupError)
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .padding(.horizontal, PixelHandTheme.Space.lg)
                    .padding(.bottom, PixelHandTheme.Space.md)
            }

            let showsTransfers = TransferPanelPlan.showsTab(
                transfers.panelItems,
                waitingPrompts: transfers.prompts.count,
                at: Date()
            )
            if showsTransfers {
                MacPanelTabs(
                    selection: $tab,
                    transfersBadge: TransferPanelPlan.badge(transfers.panelItems, waitingPrompts: transfers.prompts.count, at: Date())
                )
                .padding(.horizontal, PixelHandTheme.Space.lg)
                .padding(.bottom, PixelHandTheme.Space.sm)
            }

            if showsTransfers && tab == .transfers {
                PanelDivider()
                MacTransfersTab()
            } else {
                devicesView(authorizedConnections: authorizedConnections)
            }

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

    // MARK: Devices view

    @ViewBuilder
    private func devicesView(authorizedConnections: [LoomConnectionSnapshot]) -> some View {
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

        // One list: asking, connected, paired and away (OR-08).
        PanelSection {
            MacSectionLabel(text: "Devices")
                .padding(.horizontal, PixelHandTheme.Space.lg)
            if isLocked && !authorizedConnections.isEmpty {
                lockedNote
            }
            MacDevicesList(
                connections: authorizedConnections,
                loomContext: loomContext,
                isLocked: isLocked,
                systemImage: { deviceSystemImage(for: $0) }
            )
        }

        // Sharing lane: Send, prompts, and one transfer summary row (S1/S2, OR-13).
        MacTransferSection(onOpenTransfers: { tab = .transfers })

        PanelDivider()

        permissionsSection
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
            isLocked: isLocked && connected > 0,
            pendingName: authManager.pendingConnections.first?.peerName,
            turnedAwayName: authManager.pendingConnections.isEmpty ? authManager.recentRefusal?.deviceName : nil
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
                // Fades in, never flows in (OR-09); the panel's one breath.
                if connected > 0 {
                    MacStatusPixel(color: PixelHandTheme.success, size: 8, breathes: true)
                } else {
                    MacStatusPixel(color: PixelHandTheme.fill2, size: 8)
                }
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .padding(.vertical, PixelHandTheme.Space.md)
    }

    // MARK: Focus

    /// An empty, invisible focus target that takes the panel's first focus.
    @ViewBuilder
    private var focusSink: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .focusable()
            .focused($isFocusSinkFocused)
            .focusEffectDisabled()
            .accessibilityHidden(true)
            .onAppear { isFocusSinkFocused = true }
    }

    // MARK: Turned away (VQ-023)

    /// "iPhone 17 Pro tried to connect from another network. Pair it on the
    /// same Wi-Fi first." with Pair a device, amber like a request.
    private func turnedAwayNote(_ copy: (line: String, action: String), reason: AuthRefusal) -> some View {
        HStack(alignment: .top, spacing: PixelHandTheme.Space.sm) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(PixelHandTheme.warning)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                Text(copy.line)
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: PixelHandTheme.Space.sm) {
                    if reason != .unverified {
                        Button(copy.action) {
                            authManager.dismissRecentRefusal()
                            PairDeviceWindow.shared.open(authManager)
                        }
                        .buttonStyle(.macPrimary)
                        .accessibilityIdentifier("ph.mac.turnedAwayPair")
                    }
                    Button("Dismiss") { authManager.dismissRecentRefusal() }
                        .buttonStyle(.macQuiet)
                        .accessibilityIdentifier("ph.mac.turnedAwayDismiss")
                }
            }
        }
        .padding(PixelHandTheme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .fill(PixelHandTheme.warningTint)
        )
        .padding(.horizontal, PixelHandTheme.Space.sm)
        .padding(.bottom, PixelHandTheme.Space.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.mac.turnedAway")
    }

    // MARK: Devices

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
                // Cobalt, not the system accent (VQ-021).
                .tint(PixelHandTheme.accent)
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
                // Hidden while this build has no update feed: a dim button
                // that did nothing read as broken (VQ-040).
                if updater.isConfigured {
                    Button("Updates") { updater.checkForUpdates() }
                        .buttonStyle(.macSecondary)
                        .disabled(!updater.canCheckForUpdates)
                        .help("Check for a newer version of Pixel Hand")
                        .accessibilityLabel("Check for updates")
                        .accessibilityIdentifier("ph.mac.checkForUpdates")
                }
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

    /// Resolves iPhone vs iPad (etc.) from the live peer list, then from
    /// the device's name (a pending request often isn't in the peer list
    /// yet: an iPad showed an iPhone glyph, VQ-043); iPhone last.
    private func deviceSystemImage(for connection: LoomConnectionSnapshot) -> String {
        if let peer = peers.first(where: { $0.id == connection.peerID }), peer.deviceType != .unknown {
            return peer.deviceType.systemImage
        }
        switch MacPanelCopy.deviceClass(fromName: connection.peerName) {
        case .iPad: return DeviceType.iPad.systemImage
        case .mac: return DeviceType.mac.systemImage
        case .iPhone, nil: return DeviceType.iPhone.systemImage
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
                Button("Turn on", action: onFix)
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

    /// Fades in with the panel (OR-09); never breathes.
    @ViewBuilder private var statusDot: some View {
        switch status {
        case .granted:
            MacStatusPixel(color: PixelHandTheme.success, size: 7)
        case .denied:
            MacStatusPixel(color: PixelHandTheme.warning, size: 7)
        case .unknown:
            MacStatusPixel(color: PixelHandTheme.fill2, size: 7)
        }
    }
}
