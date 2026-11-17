//
//  CloudRecognitionStatus.swift
//  PixelHandCore
//
//  The "Recognize my own devices" row in the remote's Settings.
//
//  The row used to be hard-coded "Not available", saying the feature needed
//  a CloudKit container registered to a paid developer account. The
//  container `iCloud.com.widgetsflow.pixelhand` is registered now and
//  `DeckHandCloud.isCloudEnabled` is on, so the row reports what is true on
//  this device: whether CloudKit is switched on in this build and whether
//  an iCloud account is signed in.
//

import Foundation

public enum CloudRecognitionStatus: Equatable, Sendable {
    /// Still asking CloudKit for the account status.
    case checking
    /// Working: own Macs get the "My Mac" badge.
    case on
    /// No iCloud account is signed in on this device.
    case noAccount
    /// iCloud is restricted, temporarily unavailable or couldn't be read.
    case unavailable
    /// CloudKit is switched off in this build.
    case disabledInBuild

    /// The account states CloudKit reports, without importing CloudKit here
    /// so the mapping can be tested anywhere.
    public enum Account: Equatable, Sendable {
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case couldNotDetermine
    }

    public static func resolve(cloudEnabled: Bool, account: Account?) -> CloudRecognitionStatus {
        guard cloudEnabled else { return .disabledInBuild }
        switch account {
        case nil: return .checking
        case .available: return .on
        case .noAccount: return .noAccount
        case .restricted, .temporarilyUnavailable, .couldNotDetermine: return .unavailable
        }
    }

    /// Short badge on the right of the row.
    public var badge: String {
        switch self {
        case .checking: "Checking…"
        case .on: "On"
        case .noAccount: "Sign in to iCloud"
        case .unavailable: "Unavailable"
        case .disabledInBuild: "Off"
        }
    }

    public var isActive: Bool { self == .on }

    /// The line under the row's title.
    public var detail: String {
        switch self {
        case .checking, .on:
            "Macs signed in to your iCloud account are marked “My Mac” and listed first."
        case .noAccount:
            "Sign in to iCloud in the Settings app to have your own Macs marked “My Mac”."
        case .unavailable:
            "iCloud isn’t reachable right now, so your own Macs aren’t marked. Discovery on your network still works."
        case .disabledInBuild:
            "This build doesn’t use iCloud. Macs are found on your local network only."
        }
    }

    /// Section footer: what recognition does and doesn't change.
    public static let footer = "Your devices recognize each other through your private iCloud database. The Mac still asks you to allow each new connection."
}
