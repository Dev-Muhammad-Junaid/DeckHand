//
//  DisplayLayout.swift
//  PixelHandCore
//
//  A snapshot of the Mac's displays, their Mission Control Spaces and which
//  display the pointer is on. The Mac sends it as
//  `SystemMessage.displayState(layout:)` when a remote connects, when the
//  active Space changes, when displays are added, removed or rearranged,
//  and when the pointer crosses to another display. The remote uses it for
//  the mirror's display picker, the desktop dots under the mirror, the
//  "cursor is on <display>" badge, and to hide ‹ › at either end of the
//  strip of Spaces.
//
//  Spaces are read on the Mac with a private call (approved, Mac only, see
//  DECISIONS.md 2026-11-17). When it is missing, `spacesKnown` is `false`
//  and every display's `spaces` and `currentSpaceIndex` are `nil`: show the
//  displays, hide the dots, keep ‹ › (the Mac then tries and watches).
//
//  Remote side (Mirror lane): read the computed helpers below rather than
//  the raw arrays, and `SpaceNavigation.decide` for the ‹ › state, so the
//  remote and the Mac agree on the edge rules.
//

import Foundation

public struct DisplayLayout: Codable, Sendable, Equatable, Hashable {
    /// Every display, the main one (menu bar) first, then left to right.
    public let displays: [DisplaySpaces]
    /// The display the pointer is on, `nil` if it couldn't be told.
    public let cursorDisplayID: UInt32?
    /// `false` when this Mac couldn't read Spaces (private symbol missing,
    /// or it answered nothing usable).
    public let spacesKnown: Bool
    /// System Settings › Desktop & Dock › "Displays have separate Spaces".
    /// When `false` every display shows the same strip of Spaces, and each
    /// display carries the same `spaces` list.
    public let separateSpaces: Bool

    public init(displays: [DisplaySpaces], cursorDisplayID: UInt32?, spacesKnown: Bool, separateSpaces: Bool) {
        self.displays = displays
        self.cursorDisplayID = cursorDisplayID
        self.spacesKnown = spacesKnown
        self.separateSpaces = separateSpaces
    }

    /// The display with this `CGDirectDisplayID`.
    public func display(_ displayID: UInt32) -> DisplaySpaces? {
        displays.first { $0.displayID == displayID }
    }

    /// The main display (the one with the menu bar).
    public var mainDisplay: DisplaySpaces? {
        displays.first(where: \.isMain) ?? displays.first
    }

    /// The display under the pointer.
    public var cursorDisplay: DisplaySpaces? {
        cursorDisplayID.flatMap(display)
    }

    /// The same layout without Space data, for a Mac that can't read it.
    public var withoutSpaces: DisplayLayout {
        DisplayLayout(
            displays: displays.map { $0.withoutSpaces },
            cursorDisplayID: cursorDisplayID,
            spacesKnown: false,
            separateSpaces: separateSpaces
        )
    }
}

/// One display and its Spaces.
public struct DisplaySpaces: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: UInt32 { displayID }
    /// `CGDirectDisplayID`, the same id `DisplayInfo` and `mirror.start` use.
    public let displayID: UInt32
    /// `NSScreen.localizedName`, or "Display".
    public let name: String
    public let isMain: Bool
    /// Position and size in the Mac's global coordinate space, in points,
    /// origin at the top left of the main display (CoreGraphics' space).
    public let bounds: DisplayBounds
    /// The display's Spaces in Mission Control order, left to right, full
    /// screen apps included (they sit in the same strip). `nil` when not
    /// known.
    public let spaces: [SpaceInfo]?
    /// Index into `spaces` of the Space showing now. `nil` when not known.
    public let currentSpaceIndex: Int?

    public init(
        displayID: UInt32,
        name: String,
        isMain: Bool,
        bounds: DisplayBounds,
        spaces: [SpaceInfo]?,
        currentSpaceIndex: Int?
    ) {
        self.displayID = displayID
        self.name = name
        self.isMain = isMain
        self.bounds = bounds
        self.spaces = spaces
        // An index outside the list is as good as unknown.
        if let spaces, let index = currentSpaceIndex, spaces.indices.contains(index) {
            self.currentSpaceIndex = index
        } else {
            self.currentSpaceIndex = nil
        }
    }

    /// Number of Spaces on this display, `nil` when not known.
    public var spaceCount: Int? { spaces?.count }

    /// The full-screen app Spaces, with their index in `spaces`.
    public var fullScreenSpaces: [(index: Int, appName: String?)] {
        guard let spaces else { return [] }
        return spaces.enumerated()
            .filter { $0.element.kind == .fullScreen }
            .map { (index: $0.offset, appName: $0.element.appName) }
    }

    /// The current Space, when known.
    public var currentSpace: SpaceInfo? {
        guard let spaces, let index = currentSpaceIndex else { return nil }
        return spaces[index]
    }

    public var withoutSpaces: DisplaySpaces {
        DisplaySpaces(displayID: displayID, name: name, isMain: isMain, bounds: bounds, spaces: nil, currentSpaceIndex: nil)
    }

    // Decoding goes through init, so a hostile or stale index can't point
    // outside `spaces` on the remote either.
    private enum CodingKeys: String, CodingKey {
        case displayID, name, isMain, bounds, spaces, currentSpaceIndex
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            displayID: try c.decode(UInt32.self, forKey: .displayID),
            name: try c.decode(String.self, forKey: .name),
            isMain: try c.decode(Bool.self, forKey: .isMain),
            bounds: try c.decode(DisplayBounds.self, forKey: .bounds),
            spaces: try c.decodeIfPresent([SpaceInfo].self, forKey: .spaces),
            currentSpaceIndex: try c.decodeIfPresent(Int.self, forKey: .currentSpaceIndex)
        )
    }
}

/// A rectangle in the Mac's global display space, in points.
public struct DisplayBounds: Codable, Sendable, Equatable, Hashable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }
}

/// One Mission Control Space.
public struct SpaceInfo: Codable, Sendable, Equatable, Hashable {
    public let kind: SpaceKind
    /// For a full-screen Space, the app (or apps, for a split view) in it,
    /// when the Mac could tell. `nil` for desktops.
    public let appName: String?

    public init(kind: SpaceKind, appName: String? = nil) {
        self.kind = kind
        self.appName = appName
    }

    public static let desktop = SpaceInfo(kind: .desktop)
}

public enum SpaceKind: String, Codable, Sendable, Hashable {
    /// A desktop the user added in Mission Control.
    case desktop
    /// An app (or a split view) in full screen.
    case fullScreen
}
