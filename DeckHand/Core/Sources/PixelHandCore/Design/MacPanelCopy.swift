//
//  MacPanelCopy.swift
//  PixelHandCore – Design
//
//  The Mac menu-bar panel's header line (UX-012, board "Mac panel"):
//  "2 devices connected · ready", spoken the same way.
//

import Foundation

public enum MacPanelCopy {
    /// The line under the Mac's name.
    public static func headerStatus(
        isRunning: Bool,
        failedToStart: Bool,
        connected: Int,
        pending: Int,
        isLocked: Bool,
        pendingName: String? = nil,
        turnedAwayName: String? = nil
    ) -> String {
        if failedToStart { return "Failed to start" }
        if !isRunning { return "Starting…" }
        // One device asking says who (VQ-043).
        if pending == 1, let pendingName, connected == 0 {
            return "\(pendingName) is asking to connect"
        }
        var parts: [String] = []
        if pending > 0 { parts.append(pending == 1 ? "1 device asking" : "\(pending) devices asking") }
        if connected > 0 { parts.append(connected == 1 ? "1 device connected" : "\(connected) devices connected") }
        if isLocked { parts.append("locked") }
        if parts.isEmpty {
            // Never "Ready" right after turning a device away (VQ-023).
            if let turnedAwayName { return "\(turnedAwayName) couldn’t connect" }
            return "Ready for a device"
        }
        if parts == ["locked"] { return "Locked" }
        // "ready" only beside connected devices: next to a request it read
        // as if nothing needed the person (VQ-043).
        if !isLocked, pending == 0 { parts.append("ready") }
        return parts.joined(separator: " · ")
    }

    /// The panel's line about a device the Mac just turned away by a rule
    /// or a timeout, and the button beside it (VQ-023). `nil` for a
    /// person's Deny: they know.
    public static func turnedAway(name: String, reason: AuthRefusal) -> (line: String, action: String)? {
        switch reason {
        case .notPairedRemote:
            ("\(name) tried to connect from another network. Pair it on the same Wi-Fi first.", "Pair a device")
        case .timedOut:
            ("\(name) asked to connect, but nobody answered in time. Pair it so it connects without asking.", "Pair a device")
        case .unverified:
            ("\(name) couldn’t prove its identity. Update Pixel Hand on it, then connect again.", "Dismiss")
        case .declined, .replaced:
            nil
        }
    }

    /// What kind of device a name suggests, for its glyph when Loom doesn't
    /// say (VQ-043: an iPad showed an iPhone glyph). `nil` when the name
    /// doesn't tell.
    public enum DeviceClass: String, Sendable {
        case iPad, iPhone, mac
    }

    public static func deviceClass(fromName name: String) -> DeviceClass? {
        let lower = name.lowercased()
        if lower.contains("ipad") { return .iPad }
        if lower.contains("iphone") { return .iPhone }
        if lower.contains("macbook") || lower.contains("imac") || lower.contains("mac mini") || lower.contains("mac studio") || lower.contains("mac pro") {
            return .mac
        }
        return nil
    }
}
