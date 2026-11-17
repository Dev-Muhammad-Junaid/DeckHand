//
//  PeerCompatibility.swift
//  PixelHandCore
//
//  Whether a discovered device can talk to this one, decided before
//  dialling. Both versions are compared (see `PixelHandProtocol`):
//
//  - Loom's `proto` TXT key: Loom's session handshake refuses a mismatch
//    with a generic error.
//  - Pixel Hand's `ph-proto` TXT key: a mismatch connects but every message
//    fails to decode.
//
//  The apps build the inputs from `LoomPeerAdvertisement` (see
//  `Shared/PeerCompatibility+Loom.swift`); this file holds the decision so
//  it is tested on Linux.
//

import Foundation

public enum PeerCompatibility: Equatable, Sendable {
    /// Same protocols on both ends.
    case compatible
    /// The other device runs a newer protocol: this device needs the update.
    case updateThisDevice
    /// The other device runs an older protocol: it needs the update.
    case updatePeer

    /// - Parameters:
    ///   - peerLoomVersion: The peer's advertised Loom protocol version.
    ///   - peerAppVersion: The peer's advertised `ph-proto`, or `nil` when it
    ///     didn't advertise one. `nil` is treated as compatible: a peer seen
    ///     only through iCloud carries no TXT record, and blocking it would
    ///     hide a Mac that may well be current. Every build from protocol 2
    ///     on advertises the key on the local network.
    ///   - localLoomVersion: This build's Loom protocol version.
    ///   - localAppVersion: This build's app protocol version.
    public init(
        peerLoomVersion: Int,
        peerAppVersion: Int?,
        localLoomVersion: Int,
        localAppVersion: Int = PixelHandProtocol.version
    ) {
        if peerLoomVersion != localLoomVersion {
            self = peerLoomVersion > localLoomVersion ? .updateThisDevice : .updatePeer
            return
        }
        guard let peerAppVersion, peerAppVersion != localAppVersion else {
            self = .compatible
            return
        }
        self = peerAppVersion > localAppVersion ? .updateThisDevice : .updatePeer
    }

    public var isCompatible: Bool { self == .compatible }

    /// The line to show, from the point of view of `thisDevice`, about a
    /// `peer`. For example, on an iPad looking at an older Mac:
    /// "Please update Pixel Hand on your Mac".
    public func updateMessage(thisDevice: String, peer: String) -> String? {
        switch self {
        case .compatible: nil
        case .updateThisDevice: "Please update Pixel Hand on your \(thisDevice)"
        case .updatePeer: "Please update Pixel Hand on your \(peer)"
        }
    }
}
