//
//  SpaceNavigation.swift
//  PixelHandCore
//
//  The Space rules both sides share: whether ‹ › can move on a display
//  (the Mac refuses a switch past either end instead of posting ⌃←/⌃→ and
//  waiting for nothing; the remote dims the chevron), how the Mac's
//  `CGSCopyManagedDisplaySpaces` answer is read, and how the snapshot is
//  put together. All pure, so it is tested on Linux.
//

import Foundation

/// Why a Space switch can't happen.
public enum SpaceSwitchRefusal: String, Sendable, Equatable {
    /// The display has one Space.
    case singleSpace
    /// Already on the first Space; there is nothing to the left.
    case atFirstSpace
    /// Already on the last Space; there is nothing to the right.
    case atLastSpace
}

public enum SpaceSwitchDecision: Equatable, Sendable {
    /// Go ahead; the Space at `index` will show.
    case switchTo(index: Int)
    /// Don't post anything.
    case refused(SpaceSwitchRefusal)
    /// No Space data for this display: try, and watch for the change.
    case unknown
    /// Not a move between Spaces (Mission Control).
    case notASwitch
}

public enum SpaceNavigation {
    /// What ‹ (`.previous`) or › (`.next`) does on `display`.
    public static func decide(_ direction: SpaceDirection, on display: DisplaySpaces?) -> SpaceSwitchDecision {
        let step: Int
        switch direction {
        case .previous: step = -1
        case .next: step = 1
        case .missionControl: return .notASwitch
        }
        guard let display, let count = display.spaceCount, count > 0,
              let current = display.currentSpaceIndex else {
            return .unknown
        }
        if count == 1 { return .refused(.singleSpace) }
        let target = current + step
        if target < 0 { return .refused(.atFirstSpace) }
        if target >= count { return .refused(.atLastSpace) }
        return .switchTo(index: target)
    }

    /// Whether the chevron for `direction` should be enabled. Unknown
    /// counts as enabled, so a Mac without Space data still lets you try.
    public static func canMove(_ direction: SpaceDirection, on display: DisplaySpaces?) -> Bool {
        switch decide(direction, on: display) {
        case .switchTo, .unknown, .notASwitch: true
        case .refused: false
        }
    }
}

/// One entry of `CGSCopyManagedDisplaySpaces`: a display (or, with
/// "Displays have separate Spaces" off, every display) and its Spaces.
public struct ManagedDisplaySpaces: Equatable, Sendable {
    /// "Display Identifier": the display's UUID string, or "Main".
    public let identifier: String
    public let spaces: [SpaceInfo]
    public let currentIndex: Int?

    public init(identifier: String, spaces: [SpaceInfo], currentIndex: Int?) {
        self.identifier = identifier
        self.spaces = spaces
        self.currentIndex = currentIndex
    }

    /// The identifier macOS uses for the main display on some setups, and
    /// for the single shared strip when displays don't have separate Spaces.
    public static let mainIdentifier = "Main"
}

/// Reads `CGSCopyManagedDisplaySpaces`' answer, an array of dictionaries:
///
///     [{ "Display Identifier": "<UUID>" | "Main",
///        "Current Space": { "ManagedSpaceID": 5, … },
///        "Spaces": [{ "ManagedSpaceID": 5, "type": 0, … },
///                   { "ManagedSpaceID": 9, "type": 4,
///                     "TileLayoutManager": { "TileSpaces": [{ "appName": "Safari", … }] }, "pid": 412, … }] }]
///
/// Verified on macOS 27 (STATUS.md). Unknown shapes are skipped, never
/// trapped on: an entry without an identifier or Spaces list is dropped, a
/// Space of type 2 (a system Space, not in the strip) is left out, type 4
/// is a full-screen app, anything else a desktop.
public enum ManagedSpacesParser {
    public static let fullScreenType = 4
    public static let systemType = 2

    /// `nil` when `raw` isn't a list at all. `appName(forPID:)` names a
    /// full-screen Space from its owner's pid when the dictionary carries
    /// no app name.
    public static func parse(
        _ raw: Any?,
        appNameForPID: (Int32) -> String? = { _ in nil }
    ) -> [ManagedDisplaySpaces]? {
        guard let entries = raw as? [Any] else { return nil }
        return entries.compactMap { entry -> ManagedDisplaySpaces? in
            guard let dict = entry as? [String: Any],
                  let identifier = dict["Display Identifier"] as? String,
                  let rawSpaces = dict["Spaces"] as? [Any] else { return nil }
            let currentID = (dict["Current Space"] as? [String: Any]).flatMap(spaceID)
            var spaces: [SpaceInfo] = []
            var currentIndex: Int?
            for rawSpace in rawSpaces {
                guard let space = rawSpace as? [String: Any] else { continue }
                let type = intValue(space["type"]) ?? 0
                if type == systemType { continue }
                if let currentID, let id = spaceID(space), id == currentID {
                    currentIndex = spaces.count
                }
                if type == fullScreenType {
                    spaces.append(SpaceInfo(kind: .fullScreen, appName: fullScreenAppName(space, appNameForPID: appNameForPID)))
                } else {
                    spaces.append(.desktop)
                }
            }
            return ManagedDisplaySpaces(identifier: identifier, spaces: spaces, currentIndex: currentIndex)
        }
    }

    private static func spaceID(_ space: [String: Any]) -> Int? {
        intValue(space["ManagedSpaceID"]) ?? intValue(space["id64"])
    }

    private static func fullScreenAppName(_ space: [String: Any], appNameForPID: (Int32) -> String?) -> String? {
        if let manager = space["TileLayoutManager"] as? [String: Any],
           let tiles = manager["TileSpaces"] as? [Any] {
            let names = tiles.compactMap { ($0 as? [String: Any])?["appName"] as? String }
                .filter { !$0.isEmpty }
            if !names.isEmpty { return names.joined(separator: " & ") }
        }
        if let pid = intValue(space["pid"]), let name = appNameForPID(Int32(truncatingIfNeeded: pid)) {
            return name
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: v
        case let v as Int64: Int(truncatingIfNeeded: v)
        case let v as Int32: Int(v)
        case let v as UInt64: Int(truncatingIfNeeded: v)
        case let v as Double where v.isFinite: Int(v)
        case let v as NSNumber: v.intValue
        default: nil
        }
    }
}

/// A display as the Mac sees it, before Spaces are matched to it.
public struct DisplayDescriptor: Equatable, Sendable {
    public let displayID: UInt32
    public let name: String
    public let isMain: Bool
    public let bounds: DisplayBounds
    /// `CGDisplayCreateUUIDFromDisplayID` as a string, if available.
    public let uuid: String?

    public init(displayID: UInt32, name: String, isMain: Bool, bounds: DisplayBounds, uuid: String?) {
        self.displayID = displayID
        self.name = name
        self.isMain = isMain
        self.bounds = bounds
        self.uuid = uuid
    }
}

public enum DisplayLayoutBuilder {
    /// Puts the snapshot together.
    ///
    /// - Parameters:
    ///   - managed: the parsed Spaces, or `nil` when they couldn't be read.
    ///   - cursorPoint: the pointer in global coordinates, used to find its
    ///     display when `cursorDisplayID` isn't given.
    public static func build(
        displays: [DisplayDescriptor],
        managed: [ManagedDisplaySpaces]?,
        cursorDisplayID: UInt32? = nil,
        cursorPoint: (x: Double, y: Double)? = nil
    ) -> DisplayLayout {
        let ordered = displays.sorted {
            if $0.isMain != $1.isMain { return $0.isMain }
            if $0.bounds.x != $1.bounds.x { return $0.bounds.x < $1.bounds.x }
            return $0.displayID < $1.displayID
        }
        let cursor = cursorDisplayID ?? cursorPoint.flatMap { point in
            ordered.first { $0.bounds.contains(x: point.x, y: point.y) }?.displayID
        }
        guard let managed, !managed.isEmpty else {
            return DisplayLayout(
                displays: ordered.map { DisplaySpaces($0, spaces: nil, current: nil) },
                cursorDisplayID: cursor,
                spacesKnown: false,
                separateSpaces: true
            )
        }
        // One strip for several displays: "Displays have separate Spaces"
        // is off, and every display shows the same Spaces.
        let shared = managed.count == 1 && ordered.count > 1
        let result = ordered.map { display -> DisplaySpaces in
            let entry = shared ? managed[0] : match(display, in: managed)
            return DisplaySpaces(display, spaces: entry?.spaces, current: entry?.currentIndex)
        }
        return DisplayLayout(
            displays: result,
            cursorDisplayID: cursor,
            spacesKnown: true,
            separateSpaces: !shared
        )
    }

    private static func match(_ display: DisplayDescriptor, in managed: [ManagedDisplaySpaces]) -> ManagedDisplaySpaces? {
        if let uuid = display.uuid,
           let entry = managed.first(where: { $0.identifier.caseInsensitiveCompare(uuid) == .orderedSame }) {
            return entry
        }
        if display.isMain {
            return managed.first { $0.identifier == ManagedDisplaySpaces.mainIdentifier }
        }
        return nil
    }
}

private extension DisplaySpaces {
    init(_ display: DisplayDescriptor, spaces: [SpaceInfo]?, current: Int?) {
        self.init(
            displayID: display.displayID,
            name: display.name,
            isMain: display.isMain,
            bounds: display.bounds,
            spaces: spaces,
            currentSpaceIndex: current
        )
    }
}
