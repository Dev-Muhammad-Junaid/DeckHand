//
//  InstalledAppInfo.swift
//  PixelHandCore
//

import Foundation

/// Lightweight descriptor of a macOS application, sent from the Mac host
/// to the iPad so it can render a dynamic app launcher with real icons.
public struct InstalledAppInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let displayName: String
    /// 64×64 JPEG icon data (~2-5 KB per app). `nil` if the icon couldn't be read.
    public let iconData: Data?

    public init(bundleID: String, displayName: String, iconData: Data?) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.iconData = iconData
    }
}

// MARK: - Lookups that tolerate duplicate bundle IDs

public extension InstalledAppInfo {
    /// Apps keyed by bundle ID. Two copies of an app (say `/Applications`
    /// and `~/Applications`) share a bundle ID, and
    /// `Dictionary(uniqueKeysWithValues:)` traps on that. The first entry
    /// wins, matching the host's ordering.
    static func byBundleID(_ apps: [InstalledAppInfo]) -> [String: InstalledAppInfo] {
        Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Position of each bundle ID in a most-recent-first list (0 = most
    /// recent). A bundle ID listed twice keeps its earliest position
    /// instead of trapping.
    static func recencyRank(of bundleIDs: [String]) -> [String: Int] {
        Dictionary(bundleIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
