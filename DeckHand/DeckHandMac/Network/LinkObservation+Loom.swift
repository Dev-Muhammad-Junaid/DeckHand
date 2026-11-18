//
//  LinkObservation+Loom.swift
//  DeckHandMac
//
//  Fills PixelHandCore's `LinkObservation` from a Loom path snapshot.
//

import Foundation
import LoomKit

extension LinkObservation {
    /// The interface carrying the connection is found from the local
    /// address (its `%zone`, or `getifaddrs`), else the path's preferred
    /// interface.
    init(snapshot: LoomSessionNetworkPathSnapshot, addressOwners: [String: String], isUSBTether: (String) -> Bool?) {
        let localHost = snapshot.backendLocalEndpoint?.hostPort?.host.rawValue
        let interfaceName = LinkJudge.carryingInterface(
            localHost: localHost,
            addressOwners: addressOwners,
            pathInterfaces: snapshot.interfaces.map(\.name)
        )
        self.init(
            interfaceName: interfaceName,
            usesWiFi: snapshot.usesWiFi,
            usesWiredEthernet: snapshot.usesWiredEthernet,
            usesCellular: snapshot.usesCellular,
            usesLoopback: snapshot.usesLoopback,
            usesOther: snapshot.usesOther,
            remoteHost: snapshot.backendRemoteEndpoint?.hostPort?.host.rawValue,
            isUSBTether: interfaceName.flatMap(isUSBTether)
        )
    }
}
