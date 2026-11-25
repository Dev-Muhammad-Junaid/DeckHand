//
//  PairingMenuSection.swift
//  DeckHandMac
//
//  The menu-bar panel's one Devices list (OR-08, replacing the separate
//  Devices, Paired and "Pair a device…" parts). Each iPhone or iPad is one
//  row with its state, from Core's `MacDeviceListPlan`:
//
//  - Asking to connect: amber, with Deny / Pair / Allow on the row;
//  - Connected: the live pixel, its link badge, Disconnect (and Forget
//    when paired) in the row's menu;
//  - Paired · not connected: dim, Forget in the row's menu.
//
//  Forget confirms in the row. One "Pair a device" button sits under the
//  list, with the code's status line while a code shows. Labels carry no
//  trailing "…" (OR-12).
//

import Loom
import LoomKit
import SwiftUI

struct MacDevicesList: View {
    /// Allowed, live connections.
    let connections: [LoomConnectionSnapshot]
    let loomContext: LoomContext
    let isLocked: Bool
    /// The SF Symbol for a connection's device (iPad, iPhone…).
    let systemImage: @MainActor (LoomConnectionSnapshot) -> String

    @EnvironmentObject private var authManager: DeviceAuthorizationManager
    @ObservedObject private var store = PairedDeviceStore.shared
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let paired = Dictionary(store.devices.map { (Self.key($0.ref), $0) }, uniquingKeysWith: { first, _ in first })
        let snapshots = Dictionary(
            (authManager.pendingConnections + connections).map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )
        let rows = MacDeviceListPlan.rows(
            asking: authManager.pendingConnections.map { (pending: LoomConnectionSnapshot) -> MacDeviceListPlan.Asking in
                MacDeviceListPlan.Asking(
                    connectionID: pending.id,
                    name: pending.peerName,
                    requestedAt: authManager.pendingRequestedDate(for: pending.id)
                )
            },
            live: connections.map { (live: LoomConnectionSnapshot) -> MacDeviceListPlan.Live in
                MacDeviceListPlan.Live(
                    connectionID: live.id,
                    name: live.peerName,
                    connectedAt: live.connectedAt,
                    pairedKey: authManager.pairedRef(connectionID: live.id).map { Self.key($0) }
                )
            },
            paired: store.devices.map { (device: PairedDevice) -> MacDeviceListPlan.Paired in
                MacDeviceListPlan.Paired(key: Self.key(device.ref), name: device.name, lastSeenAt: device.lastSeenAt)
            }
        )

        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            if rows.isEmpty {
                waitingState
            }
            ForEach(rows) { row in
                let connection = row.connectionID.flatMap { snapshots[$0] }
                let device = row.pairedKey.flatMap { paired[$0] }
                MacDeviceRowView(
                    row: row,
                    systemImage: connection.map { systemImage($0) } ?? device?.kind.systemImage ?? DeviceType.iPhone.systemImage,
                    connection: connection,
                    pairedRef: device?.ref,
                    isLocked: isLocked,
                    loomContext: loomContext
                )
            }
            if !rows.isEmpty, let hint = MacDeviceListPlan.hint(rows: rows, macName: PairDeviceView.macName) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PixelHandTheme.Space.lg)
            }

            PairingStatusLine()

            HStack(spacing: PixelHandTheme.Space.sm) {
                Button(MacDeviceListPlan.pairButton) { PairDeviceWindow.shared.open(authManager) }
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

    /// The plan's key for a paired record.
    static func key(_ ref: PairedDeviceRef) -> String {
        "\(ref.identityKeyID)/\(ref.deviceID.uuidString)"
    }

    private var waitingState: some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            PixelScreen(cornerRadius: 10, padding: 6) {
                PixelGlyph(bitmap: PixelArt.hand, pitch: 1.4, glows: false)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("No devices yet")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PixelHandTheme.ink)
                Text(MacDeviceListPlan.hint(rows: [], macName: PairDeviceView.macName) ?? "")
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ph.mac.waitingState")
    }
}

private extension PairingCodeWindow.Display {
    var isLockedOut: Bool {
        if case .lockedOut = self { return true }
        return false
    }
}

// MARK: - Row

private struct MacDeviceRowView: View {
    let row: MacDeviceListPlan.Row
    let systemImage: String
    let connection: LoomConnectionSnapshot?
    let pairedRef: PairedDeviceRef?
    let isLocked: Bool
    let loomContext: LoomContext

    @EnvironmentObject private var authManager: DeviceAuthorizationManager
    @State private var isConfirmingForget = false
    @State private var isHovering = false

    private var isAsking: Bool { row.state == .asking }
    private var isAway: Bool { row.state == .pairedAway }

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            HStack(alignment: .center, spacing: PixelHandTheme.Space.md) {
                MacDeviceIcon(
                    systemImage: systemImage,
                    isLive: row.state == .connected,
                    tint: isAsking ? PixelHandTheme.warning : PixelHandTheme.accent,
                    isDim: isAway
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.body.weight(isAway ? .medium : .semibold))
                        .foregroundStyle(isAway ? PixelHandTheme.ink2 : PixelHandTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // VQ-097: minute-grained, redrawn every 30 s, so "last
                    // seen" never freezes on "38 seconds ago".
                    TimelineView(.periodic(from: .now, by: MacDeviceListPlan.seenRefreshInterval)) { context in
                        Text(MacDeviceListPlan.detailText(row.detail) { date in
                            MacDeviceListPlan.recentSeen(date, now: context.date)
                                ?? date.formatted(.relative(presentation: .named))
                        })
                            .font(.caption)
                            .foregroundStyle(isAway ? PixelHandTheme.ink3 : PixelHandTheme.ink2)
                            .lineLimit(2)
                    }
                    if row.state == .connected, let connection {
                        HStack(spacing: PixelHandTheme.Space.sm) {
                            HostLinkBadge(connectionID: connection.id) // Network lane (S13)
                            if isLocked {
                                MacDotText("LOCKED", pitch: 1.3, label: "Mac locked")
                                    .foregroundStyle(PixelHandTheme.warning)
                            }
                        }
                        // The live connection id, for matching against the
                        // remote's log and spotting silent session swaps.
                        Text("session \(connection.id.uuidString.prefix(8))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(PixelHandTheme.ink3)
                            .textSelection(.enabled)
                            .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: PixelHandTheme.Space.xs)
                if !row.menu.isEmpty, !isConfirmingForget {
                    rowMenu
                }
            }

            if isAsking {
                requestButtons
            }
            if isConfirmingForget {
                forgetConfirmation
            }
        }
        .padding(.vertical, isAsking ? PixelHandTheme.Space.md : 0)
        .padding(.horizontal, isAsking ? PixelHandTheme.Space.md : PixelHandTheme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .fill(isAsking ? PixelHandTheme.warningTint : Color.clear)
        )
        .padding(.horizontal, isAsking ? PixelHandTheme.Space.sm : 0)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            if !isConfirmingForget {
                menuItems
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.name), \(MacDeviceListPlan.spokenState(row.state))")
        .accessibilityIdentifier(rowIdentifier)
    }

    private var rowIdentifier: String {
        switch row.state {
        case .asking: "ph.mac.pendingRow"
        case .connected: "ph.mac.deviceRow"
        case .pairedAway: "ph.mac.pairedDeviceRow"
        }
    }

    // MARK: Menu

    /// Disconnect, Forget or Pair: in a menu, not a row of buttons
    /// (OR-08). Always there for the keyboard; brighter on hover.
    private var rowMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(isHovering ? PixelHandTheme.ink : PixelHandTheme.ink3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Options for \(row.name)")
        .accessibilityLabel("Options for \(row.name)")
        .accessibilityIdentifier("ph.mac.deviceMenu")
    }

    @ViewBuilder private var menuItems: some View {
        ForEach(row.menu, id: \.self) { action in
            Button(action.title, role: action == .forget ? .destructive : nil) {
                perform(action)
            }
            .accessibilityLabel("\(action.title) \(row.name)")
            .accessibilityIdentifier(identifier(for: action))
        }
    }

    // MARK: Request

    /// Deny sits apart from the primary Allow; Pair shows a code the device
    /// can type so it connects without asking from now on.
    private var requestButtons: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            Button(MacDeviceListPlan.Action.deny.title) { perform(.deny) }
                .buttonStyle(.macDestructive)
                .help("Refuse this request")
                .accessibilityLabel("Deny \(row.name)")
                .accessibilityIdentifier("ph.mac.deny")
            Spacer(minLength: 0)
            Button(MacDeviceListPlan.Action.pair.title) { perform(.pair) }
                .buttonStyle(.macSecondary)
                .help("Show a pairing code to enter on the device. Paired devices connect without asking.")
                .accessibilityLabel("Pair \(row.name)")
                .accessibilityIdentifier("ph.mac.pairRequest")
            Button(MacDeviceListPlan.Action.allow.title) { perform(.allow) }
                .buttonStyle(.macPrimary)
                .help("Allow for this session")
                .accessibilityLabel("Allow \(row.name)")
                .accessibilityIdentifier("ph.mac.allow")
        }
        .padding(.leading, 28 + PixelHandTheme.Space.md)
    }

    // MARK: Forget

    private var forgetConfirmation: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            Text(MacDeviceListPlan.forgetPrompt(name: row.name, isConnected: row.state == .connected))
                .font(.caption)
                .foregroundStyle(PixelHandTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PixelHandTheme.Space.sm) {
                Spacer(minLength: 0)
                Button("Cancel") { isConfirmingForget = false }
                    .buttonStyle(.macQuiet)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Keep \(row.name)")
                    .accessibilityIdentifier("ph.mac.cancelForget")
                Button(MacDeviceListPlan.Action.forget.title) {
                    if let pairedRef { authManager.forget(pairedRef) }
                    isConfirmingForget = false
                }
                .buttonStyle(.macDestructive)
                .accessibilityLabel("Confirm forget \(row.name)")
                .accessibilityIdentifier("ph.mac.confirmForget")
            }
        }
        .padding(.leading, 28 + PixelHandTheme.Space.md)
    }

    // MARK: Actions

    private func perform(_ action: MacDeviceListPlan.Action) {
        switch action {
        case .deny:
            if let connection { authManager.reject(connection: connection, loomContext: loomContext) }
        case .pair:
            PairDeviceWindow.shared.open(authManager)
        case .allow:
            if let connection { authManager.authorize(connection: connection) }
        case .disconnect:
            if let connection { authManager.removeAndDisconnect(connection: connection, loomContext: loomContext) }
        case .forget:
            isConfirmingForget = true
        }
    }

    private func identifier(for action: MacDeviceListPlan.Action) -> String {
        switch action {
        case .deny: "ph.mac.deny"
        case .pair: row.state == .asking ? "ph.mac.pairRequest" : "ph.mac.pairConnected"
        case .allow: "ph.mac.allow"
        case .disconnect: "ph.mac.disconnect"
        case .forget: "ph.mac.forget"
        }
    }
}

// MARK: - Status line

/// One line under the list while a code is live, pairing is paused, or a
/// device just paired.
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
                    MacStatusPixel(color: PixelHandTheme.success, size: 6)
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

// MARK: - Device icon

/// A device's symbol in a 28 pt circle; a mint pixel on its corner while
/// it is connected (fading in, never flowing in: OR-09); dim while a
/// paired device is away.
struct MacDeviceIcon: View {
    let systemImage: String
    var isLive = false
    var tint: Color = PixelHandTheme.accent
    var isDim = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.body)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(Circle().fill(PixelHandTheme.fill))
            .opacity(isDim ? 0.5 : 1)
            .overlay(alignment: .bottomTrailing) {
                if isLive {
                    MacStatusPixel(color: PixelHandTheme.success, size: 6)
                        .offset(x: 1, y: 1)
                }
            }
            .accessibilityHidden(true)
    }
}
