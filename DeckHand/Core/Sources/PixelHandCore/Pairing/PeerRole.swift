//
//  PeerRole.swift
//  PixelHandCore
//
//  Which side of Pixel Hand a discovered device runs. Both apps advertise
//  the same Bonjour service, so a remote's browse also finds other iPads
//  and iPhones running Pixel Hand. Only Macs belong in the remote's list
//  (build 19: the iPad mini listed the iPad Pro as a Mac, with a laptop
//  glyph and "Please update Pixel Hand on your Mac").
//
//  Two signals, best first: the `ph-role` TXT key each app advertises
//  (new with this change), then Loom's advertised device type (every build).
//

import Foundation

public enum PeerRole: String, Sendable, CaseIterable {
    /// The Mac app: the one a remote controls.
    case mac
    /// The iOS app (iPad or iPhone): a remote.
    case remote

    /// Bonjour TXT key carrying the role. Under 9 bytes.
    public static let advertisementKey = "ph-role"

    /// The role a peer advertised, or `nil` when it didn’t say (a build
    /// without `ph-role`) or said something this build doesn't know.
    public static func advertised(in metadata: [String: String]) -> PeerRole? {
        guard let raw = metadata[advertisementKey]?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return nil
        }
        return PeerRole(rawValue: raw)
    }

    /// Loom device types (`DeviceType.rawValue`) that are never a Mac.
    public static let nonMacDeviceTypes: Set<String> = ["ipad", "iphone", "vision"]

    /// Whether a discovered peer belongs in the remote's list of Macs.
    ///
    /// Either signal can rule a peer out; neither can rule an iOS device in.
    /// - Loom's device type: iPad, iPhone and Vision are never listed.
    /// - The advertised role: when present, only `mac` is listed (an
    ///   unknown value is not).
    /// - With neither saying otherwise (`mac`, `unknown` or no type, no
    ///   role: a build 19 Mac, or a Mac seen through a source that carries
    ///   no type), the peer is listed.
    ///
    /// - Parameters:
    ///   - metadata: the peer's advertisement metadata (TXT record).
    ///   - deviceType: Loom's `DeviceType.rawValue` for the peer, if any.
    public static func isListedAsMac(metadata: [String: String], deviceType: String?) -> Bool {
        if let deviceType, nonMacDeviceTypes.contains(deviceType.lowercased()) {
            return false
        }
        if metadata[advertisementKey] != nil {
            return advertised(in: metadata) == .mac
        }
        return true
    }
}
