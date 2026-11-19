//
//  MirrorSpaceStrip.swift
//  PixelHandCore
//
//  What the remote draws under the mirror for the mirrored display's
//  Mission Control Spaces: one dot per desktop (the current one filled),
//  full-screen apps as short labels, and whether each ‹ › chevron is
//  shown, dimmed or hidden. Built from the Mac's `DisplayLayout`
//  (`system.displayState`) with `SpaceNavigation`'s edge rules, so the
//  remote dims a chevron exactly when the Mac would refuse the switch.
//

import Foundation

/// One entry in the strip of Spaces under the mirror.
public struct MirrorSpaceDot: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// A desktop: drawn as a dot.
        case desktop
        /// A full-screen app (or split view): drawn as a short label.
        case fullScreen(label: String)
    }

    /// Position in the display's strip, left to right.
    public let index: Int
    public let kind: Kind
    public let isCurrent: Bool
    public var id: Int { index }

    public init(index: Int, kind: Kind, isCurrent: Bool) {
        self.index = index
        self.kind = kind
        self.isCurrent = isCurrent
    }
}

/// How a ‹ › chevron is drawn.
public enum MirrorChevronState: Equatable, Sendable {
    /// Tappable.
    case enabled
    /// Shown but not tappable: already at that end of the strip.
    case dimmed
    /// Not shown: the display has a single Space.
    case hidden
}

public struct MirrorSpaceStrip: Equatable, Sendable {
    /// The dots, left to right. Empty when Spaces aren't known.
    public let dots: [MirrorSpaceDot]
    public let previous: MirrorChevronState
    public let next: MirrorChevronState

    public init(dots: [MirrorSpaceDot], previous: MirrorChevronState, next: MirrorChevronState) {
        self.dots = dots
        self.previous = previous
        self.next = next
    }

    /// Nothing known: no dots, both chevrons usable (the Mac tries and
    /// watches).
    public static let unknown = MirrorSpaceStrip(dots: [], previous: .enabled, next: .enabled)

    /// Longest full-screen label, in characters, before it is cut with "…".
    public static let maxLabelLength = 10

    /// The strip for the mirrored display.
    ///
    /// - Parameters:
    ///   - layout: the Mac's latest snapshot, `nil` before it arrives.
    ///   - mirroredDisplayID: the display the mirror shows; `nil` (not yet
    ///     confirmed by the Mac) means the main display, which is what the
    ///     Mac mirrors by default.
    public static func make(layout: DisplayLayout?, mirroredDisplayID: UInt32?) -> MirrorSpaceStrip {
        guard let layout, layout.spacesKnown else { return .unknown }
        let display = mirroredDisplayID.flatMap(layout.display) ?? (mirroredDisplayID == nil ? layout.mainDisplay : nil)
        guard let display, let spaces = display.spaces, !spaces.isEmpty else { return .unknown }

        let dots = spaces.enumerated().map { index, space in
            MirrorSpaceDot(
                index: index,
                kind: space.kind == .fullScreen ? .fullScreen(label: shortAppLabel(space.appName)) : .desktop,
                isCurrent: index == display.currentSpaceIndex
            )
        }
        return MirrorSpaceStrip(
            dots: dots,
            previous: chevron(.previous, on: display),
            next: chevron(.next, on: display)
        )
    }

    /// A full-screen app's name, short enough for the strip. "Safari &
    /// Notes" (a split view) keeps its first app; a missing name becomes
    /// "Full Screen".
    public static func shortAppLabel(_ appName: String?) -> String {
        let trimmed = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Full Screen" }
        var first = trimmed.components(separatedBy: " & ").first ?? trimmed
        first = first.trimmingCharacters(in: .whitespaces)
        if first.isEmpty { first = trimmed }
        guard first.count > maxLabelLength else { return first }
        return String(first.prefix(maxLabelLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Spoken summary, for example "Desktop 2 of 3".
    public var accessibilitySummary: String? {
        guard !dots.isEmpty else { return nil }
        guard let current = dots.first(where: \.isCurrent) else {
            return "\(dots.count) \(dots.count == 1 ? "Space" : "Spaces")"
        }
        switch current.kind {
        case .desktop:
            return "Space \(current.index + 1) of \(dots.count)"
        case let .fullScreen(label):
            return "\(label), Space \(current.index + 1) of \(dots.count)"
        }
    }

    private static func chevron(_ direction: SpaceDirection, on display: DisplaySpaces) -> MirrorChevronState {
        switch SpaceNavigation.decide(direction, on: display) {
        case .refused(.singleSpace): .hidden
        case .refused: .dimmed
        case .switchTo, .unknown, .notASwitch: .enabled
        }
    }
}

extension MirrorDisplayChrome {
    /// The display the pointer is on, for the badge: the mirror's own
    /// cursor stream when it has said (60 Hz, only while capturing), else
    /// the Mac's display snapshot (sent on every crossing, mirror or not).
    /// `0` from the stream means "not on any display we know".
    public static func cursorDisplayID(stream: UInt32?, layout: DisplayLayout?) -> UInt32? {
        if let stream, stream != 0 { return stream }
        return layout?.cursorDisplayID
    }
}
