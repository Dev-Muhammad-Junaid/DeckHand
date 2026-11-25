//
//  RemoteAccessGate.swift
//  DeckHandMac
//
//  S15: connections that arrive over a VPN, an overlay address or cellular
//  are admitted only for paired devices. Loopback (a simulator on this
//  Mac) counts as local (VQ-001). No Allow prompt and no
//  pairing code from outside the local network: `RemoteAccessPolicy`
//  (PixelHandCore) decides from the link and the peer's address; this file
//  only reads the path Loom reports for the new connection.
//
//  Also: the Mac's overlay probe listener (so a paired remote that knows
//  the Mac's Tailscale name or address can find it), and the addresses the
//  Mac reports to paired remotes (`session.remoteHosts`).
//

import Foundation
import Loom
import LoomKit

@MainActor
enum RemoteAccessGate {

    /// Turns on Loom's overlay probe listener on its default port. The Mac
    /// dials nobody over the overlay, so it has no seeds; remotes probe it.
    /// The probe answers with what Bonjour already advertises on a LAN.
    static let overlayProbeConfiguration = LoomOverlayDirectoryConfiguration(
        refreshInterval: .seconds(3_600),
        seedProvider: { [] }
    )

    /// How long admission waits for Loom's first path snapshot.
    private static let pathWait: Duration = .seconds(2)

    /// What admission learned about a connection's path.
    struct PathVerdict: Sendable {
        var link: LinkKind
        var remoteHost: String?
        var isRemote: Bool
    }

    /// Judges the path a new connection arrived on.
    static func judgePath(of handle: LoomConnectionHandle) async -> PathVerdict {
        let session = await handle.session
        let snapshot = await firstPathSnapshot(of: session)
        var link = LinkKind.unknown
        var remoteHost: String?
        if let snapshot {
            link = await HostLinkMonitor.judge(snapshot)
            remoteHost = snapshot.backendRemoteEndpoint?.hostPort?.host.rawValue
        }
        if remoteHost == nil, let authenticated = session as? LoomAuthenticatedSession {
            remoteHost = await authenticated.backendRemoteEndpoint?.hostPort?.host.rawValue
        }
        let isRemote = RemoteAccessPolicy.isRemotePath(link: link, remoteHost: remoteHost)
        if RemoteAccessPolicy.pathClass(link: link, remoteHost: remoteHost) == .sameMachine {
            DeckHandLog.trust.info("🔑 conn=\(handle.id, privacy: .public) is on this Mac (loopback, e.g. a simulator): local rules apply")
        }
        return PathVerdict(link: link, remoteHost: remoteHost, isRemote: isRemote)
    }

    /// The pairing decision for `identity`, narrowed for a remote path.
    /// Logs when a remote path turns a prompt into a refusal.
    static func admission(
        for identity: LoomPeerIdentity?,
        handle: LoomConnectionHandle,
        store: PairedDeviceStore
    ) async -> PairingAdmission {
        let verdict = await judgePath(of: handle)
        let pairing = store.admission(for: identity)
        let decision = RemoteAccessPolicy.admission(pairing, isRemotePath: verdict.isRemote)
        if verdict.isRemote {
            switch (pairing, decision) {
            case (.askUser, .refuse):
                DeckHandLog.trust.error("🔑 Refusing conn=\(handle.id, privacy: .public): not paired, and it arrived over a remote path (\(verdict.link.rawValue, privacy: .public)). Pair on the same network first.")
            case (.autoGrant, _):
                DeckHandLog.trust.info("🔑 Remote path (\(verdict.link.rawValue, privacy: .public)) from a paired device conn=\(handle.id, privacy: .public)")
            default:
                break
            }
        }
        return decision
    }

    /// Whether to let `identity` through to the usual admission. `false`
    /// means: refuse it now, it reached the Mac over a remote path without
    /// being paired. (A paired device and anything on the LAN pass.)
    static func allows(
        _ identity: LoomPeerIdentity?,
        handle: LoomConnectionHandle,
        store: PairedDeviceStore
    ) async -> Bool {
        await admission(for: identity, handle: handle, store: store) != .refuse
            || store.admission(for: identity) == .refuse
    }

    private static func firstPathSnapshot(of session: any LoomSessionProtocol) async -> LoomSessionNetworkPathSnapshot? {
        let stream = await session.makePathObserver()
        return await withTaskGroup(of: LoomSessionNetworkPathSnapshot?.self) { group in
            group.addTask {
                for await snapshot in stream {
                    return snapshot
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: pathWait)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Reporting the Mac's VPN addresses

    /// Sends the Mac's tunnel addresses to a paired remote, once per
    /// connection and again when they change. An unpaired (allowed once)
    /// remote gets nothing.
    static func reportHosts(to handle: LoomConnectionHandle, isPaired: Bool) async {
        guard isPaired else { return }
        let hosts = await Task.detached(priority: .utility) {
            RemoteAccessPolicy.reportableHosts(addressOwners: InterfaceAddressTable.current())
        }.value
        guard reportedHosts[handle.id] != hosts else { return }
        reportedHosts[handle.id] = hosts
        do {
            try await handle.send(.session(.remoteHosts(hosts: hosts)))
            DeckHandLog.connection.info("Remote access: told conn=\(handle.id, privacy: .public) about \(hosts.count, privacy: .public) VPN address(es)")
        } catch {
            reportedHosts.removeValue(forKey: handle.id)
        }
    }

    /// Forget a connection's last report (it ended).
    static func forget(_ connectionID: UUID) {
        reportedHosts.removeValue(forKey: connectionID)
    }

    private static var reportedHosts: [UUID: [String]] = [:]
}
