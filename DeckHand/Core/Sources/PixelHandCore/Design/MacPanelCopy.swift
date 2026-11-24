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
        isLocked: Bool
    ) -> String {
        if failedToStart { return "Failed to start" }
        if !isRunning { return "Starting…" }
        var parts: [String] = []
        if pending > 0 { parts.append(pending == 1 ? "1 device asking" : "\(pending) devices asking") }
        if connected > 0 { parts.append(connected == 1 ? "1 device connected" : "\(connected) devices connected") }
        if isLocked { parts.append("locked") }
        if parts.isEmpty { return "Ready for a device" }
        if parts == ["locked"] { return "Locked" }
        if !isLocked { parts.append("ready") }
        return parts.joined(separator: " · ")
    }
}
