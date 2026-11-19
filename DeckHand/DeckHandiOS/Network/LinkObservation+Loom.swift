//
//  LinkObservation+Loom.swift
//  DeckHandiOS
//
//  Fills PixelHandCore's `LinkObservation` from a Loom path snapshot. The
//  remote uses public API only, so it never knows `isUSBTether`; the judge
//  infers the cable from a wired interface to a link-local Mac, and the
//  Mac's own `session.link` report (IOKit) confirms it.
//

import Foundation
import LoomKit

extension LinkObservation {
    init(snapshot: LoomSessionNetworkPathSnapshot, addressOwners: [String: String]) {
        let localHost = snapshot.backendLocalEndpoint?.hostPort?.host.rawValue
        self.init(
            interfaceName: LinkJudge.carryingInterface(
                localHost: localHost,
                addressOwners: addressOwners,
                pathInterfaces: snapshot.interfaces.map(\.name)
            ),
            usesWiFi: snapshot.usesWiFi,
            usesWiredEthernet: snapshot.usesWiredEthernet,
            usesCellular: snapshot.usesCellular,
            usesLoopback: snapshot.usesLoopback,
            usesOther: snapshot.usesOther,
            remoteHost: snapshot.backendRemoteEndpoint?.hostPort?.host.rawValue,
            isUSBTether: nil
        )
    }
}
