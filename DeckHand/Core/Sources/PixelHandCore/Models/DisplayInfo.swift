//
//  DisplayInfo.swift
//  PixelHandCore
//
//  Physical displays the live mirror can target, plus the Space-switch
//  directions the PIP chrome can ask the host to perform. Spaces themselves
//  are not enumerable through any public API — this type only describes
//  monitors.
//

import Foundation

/// One connected monitor, identified by CoreGraphics' `CGDirectDisplayID`.
public struct DisplayInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: UInt32 { displayID }
    /// Native `CGDirectDisplayID`. Stable for a given connection of a
    /// given panel; changes if the user unplugs and replugs.
    public let displayID: UInt32
    /// `NSScreen.localizedName` when we can match the screen, otherwise a
    /// generic "Display".
    public let name: String
    /// `true` when this is `CGMainDisplayID()` — the display with the menu bar.
    public let isMain: Bool
    public let width: Int
    public let height: Int

    public init(
        displayID: UInt32,
        name: String,
        isMain: Bool,
        width: Int,
        height: Int
    ) {
        self.displayID = displayID
        self.name = name
        self.isMain = isMain
        self.width = width
        self.height = height
    }

    /// Compact chip label for the PIP chrome. Prefer a recognizable
    /// hardware token over the often-long localized name.
    public var shortLabel: String {
        let lower = name.lowercased()
        if lower.contains("built-in") { return "Built-in" }
        if lower.contains("sidecar") { return "Sidecar" }
        if isMain { return "Main" }
        if name.count <= 14 { return name }
        return String(name.prefix(12))
    }
}

/// How the PIP asks the Mac to move between Mission Control Spaces on the
/// currently mirrored display. There is no public API to address a Space
/// by index, so this is strictly relative.
public enum SpaceDirection: String, Codable, Sendable {
    /// Control-Left — previous Space on the focused display.
    case previous
    /// Control-Right — next Space on the focused display.
    case next
    /// Open Mission Control, which is the OS overview of every Space.
    case missionControl
}

/// The window a single-window mirror shows (S14), as the Mac describes it
/// in `mirror.displayList`. Sizes are the window's frame in points; the
/// mirror's frames have the same aspect.
public struct MirroredWindow: Codable, Hashable, Sendable {
    /// Native `CGWindowID`, as in `WindowInfo`.
    public let windowID: UInt32
    public let title: String
    public let appName: String
    public let width: Int
    public let height: Int

    public init(windowID: UInt32, title: String, appName: String, width: Int, height: Int) {
        self.windowID = windowID
        self.title = title
        self.appName = appName
        self.width = width
        self.height = height
    }

    /// Compact chip label for the mirror's picker: the app's name, else
    /// the title, cut to 14 characters.
    public var shortLabel: String {
        let base = appName.isEmpty ? (title.isEmpty ? "Window" : title) : appName
        return base.count <= 14 ? base : String(base.prefix(12)) + "…"
    }

    /// For VoiceOver and the picker's menu: "Notes — Shopping list".
    public var longLabel: String {
        switch (appName.isEmpty, title.isEmpty) {
        case (false, false): "\(appName) — \(title)"
        case (false, true): appName
        case (true, false): title
        case (true, true): "Window"
        }
    }
}
