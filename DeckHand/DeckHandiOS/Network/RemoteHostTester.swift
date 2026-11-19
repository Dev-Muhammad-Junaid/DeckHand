//
//  RemoteHostTester.swift
//  DeckHandiOS
//
//  S15: Settings › Remote Access › Test. Probes a paired Mac's saved hosts
//  with Loom's overlay probe (the same one the device list uses) and says
//  whether that Mac answers there. It doesn't connect: connecting from the
//  device list runs the pinned handshake.
//

import Foundation
import Loom
import LoomKit

@MainActor
enum RemoteHostTester {

    struct Result: Equatable {
        var host: RemoteHost
        var verdict: RemoteAccessPolicy.ProbeVerdict
    }

    /// Probes each host on its own so the answer is per host.
    static func test(_ hosts: [RemoteHost], for mac: PairedDeviceRef) async -> [Result] {
        var results: [Result] = []
        for host in hosts {
            let directory = LoomOverlayDirectory(
                configuration: LoomOverlayDirectoryConfiguration(
                    refreshInterval: .seconds(3_600),
                    probeTimeout: .seconds(3),
                    probeAttempts: 2,
                    probeRetryDelay: .milliseconds(400),
                    seedProvider: { [LoomOverlaySeed(host: host.value)] }
                )
            )
            await directory.refresh()
            let answers = directory.discoveredPeers.map {
                (deviceID: $0.deviceID as UUID?, identityKeyID: $0.advertisement.identityKeyID)
            }
            directory.stop()
            let verdict = RemoteAccessPolicy.probeVerdict(answers: answers, mac: mac)
            DeckHandLog.connection.info("Remote access test \(host.value, privacy: .public): \(String(describing: verdict), privacy: .public)")
            results.append(Result(host: host, verdict: verdict))
        }
        return results
    }
}
