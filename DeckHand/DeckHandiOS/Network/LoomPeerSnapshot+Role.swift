//
//  LoomPeerSnapshot+Role.swift
//  Pixel Hand – iOS
//
//  Feeds a discovered device's advertisement into PixelHandCore's
//  `PeerRole`, so the picker and the Mac switcher list only Macs: another
//  iPad or iPhone running Pixel Hand advertises the same service.
//

import Foundation
import LoomKit
import PixelHandCore

extension LoomPeerSnapshot {
    /// Whether this peer is a Mac (`PeerRole.isListedAsMac`).
    var isPixelHandMac: Bool {
        PeerRole.isListedAsMac(metadata: advertisement.metadata, deviceType: deviceType.rawValue)
    }
}

extension Array where Element == LoomPeerSnapshot {
    /// Only the Macs; other remotes running Pixel Hand dropped.
    var macsOnly: [LoomPeerSnapshot] { filter(\.isPixelHandMac) }
}
