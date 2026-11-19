//
//  HostLinkMonitor.swift
//  DeckHandMac
//
//  S13: judges the link under each connection (USB cable, Wi-Fi, Ethernet,
//  …) from Loom's path snapshots, tells the remote with `session.link`, and
//  keeps the latest judgement for the menu bar's "Wired" badge.
//
//  Started by `SessionHandler` on the first ping, so it only runs for
//  authorized sessions. It ends with the connection's path stream.
//

import Foundation
import Loom
import LoomKit
import Observation

@MainActor
@Observable
final class HostLinkMonitor {
    static let shared = HostLinkMonitor()

    /// The latest judgement per connection (`LoomConnectionHandle.id`).
    private(set) var kinds: [UUID: LinkKind] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    /// Starts watching `handle`'s path. Calling it again for the same
    /// connection does nothing.
    func monitor(_ handle: LoomConnectionHandle) {
        let id = handle.id
        guard tasks[id] == nil else { return }
        tasks[id] = Task { [weak self] in
            for await snapshot in handle.networkPathUpdates {
                let kind = await Self.judge(snapshot)
                guard let self else { return }
                guard self.kinds[id] != kind else { continue }
                let previous = self.kinds[id]
                self.kinds[id] = kind
                DeckHandLog.connection.info("Link for \(id, privacy: .public): \(previous?.rawValue ?? "none", privacy: .public) → \(kind.rawValue, privacy: .public)")
                do {
                    try await handle.send(.session(.link(kind: kind)))
                } catch {
                    DeckHandLog.connection.error("Sending the link judgement to \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            self?.forget(id)
        }
    }

    /// Drops a connection's judgement and stops watching it.
    func forget(_ id: UUID) {
        tasks.removeValue(forKey: id)?.cancel()
        kinds.removeValue(forKey: id)
        RemoteAccessGate.forget(id)
    }

    /// Reads interface addresses and walks IOKit off the main actor.
    nonisolated static func judge(_ snapshot: LoomSessionNetworkPathSnapshot) async -> LinkKind {
        await Task.detached(priority: .utility) {
            let observation = LinkObservation(
                snapshot: snapshot,
                addressOwners: InterfaceAddressTable.current(),
                isUSBTether: USBNetworkProbe.isUSBTether(bsdName:)
            )
            return LinkJudge.judge(observation)
        }.value
    }
}
