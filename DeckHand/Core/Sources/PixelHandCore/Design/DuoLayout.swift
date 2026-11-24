//
//  DuoLayout.swift
//  PixelHandCore
//
//  iPhone Duo panes (UX-040): which pose the foldable iPhone is in and where
//  the two panes go so nothing sits on the crease. Plain maths, so every
//  boundary is tested on Linux.
//  Spec: `Product/Design/03-Layout-Strategy.md` (iPhone Duo cover, open/book,
//  half-folded/laptop), `07-Polish-Spec.md` §1 and §7; board "Duo & iPad".
//
//    folded   cover display (466 × 678): the compact iPhone layout
//    book     inner display, vertical crease (951 × 669): two side-by-side
//             panes, 20 pt clear on each side of the crease
//    laptop   inner display, horizontal crease (669 × 951): screen above
//             the crease, controls below it
//
//  Where the crease comes from, best first:
//    1. The system's division region (iOS 27.1 `GeometryProxy
//       .reservedRegions(kind: .division)`), passed in as `division`.
//    2. Inference: a phone-idiom window that is not compact and not short
//       can only be the open inner display (an iPhone in landscape is
//       always under 500 pt tall), so the crease is the window's centre
//       line, across its longer side. The band is `minimumBandWidth` wide.
//  The iPad never infers a crease (`isPhone` is false there), so its
//  Stage Manager windows of the same size keep their usual arrangement.
//

/// A rectangle in points, in the shell's own coordinate space.
public struct DuoRect: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// Whether the two rectangles share any area.
    public func intersects(_ other: DuoRect) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }
}

/// The foldable iPhone's pose, as far as the layout cares.
public enum DuoPose: String, Sendable, Hashable, CaseIterable {
    /// Not a foldable (or the system hasn't shown a crease yet): the usual
    /// `CanvasPlan` arrangement.
    case none
    /// The cover display of a foldable that has been seen open: the compact
    /// iPhone layout, same as `none`, kept apart so transitions can tell.
    case folded
    /// Inner display, crease running top to bottom: two side-by-side panes.
    case book
    /// Inner display, crease running left to right (half-folded like a
    /// laptop, or held upright): screen on top, controls below.
    case laptop

    /// Whether the layout splits into two panes around the crease.
    public var isOpen: Bool { self == .book || self == .laptop }
}

/// The hinge as the system reports it (iOS 27.1 `DeviceHinge.status`),
/// mirrored here so Core needs no SDK.
public enum DuoHingeStatus: String, Sendable, Hashable {
    case closed, partiallyOpen, fullyOpen
}

/// Everything the pose is read from, for one layout pass.
public struct DuoPoseInput: Sendable, Hashable {
    /// The shell's size (inside the safe area).
    public var width: Double
    public var height: Double
    /// Where the window's centre sits in the shell's coordinates. The
    /// crease runs through the window's centre, not the safe area's
    /// (the status bar and home indicator make those differ). `nil` uses
    /// the shell's centre.
    public var windowCentre: (x: Double, y: Double)?
    /// The system's division region (frame with its margins), in the
    /// shell's coordinates, when the SDK provides one.
    public var division: DuoRect?
    /// The system's hinge status, when the SDK provides one.
    public var hingeStatus: DuoHingeStatus?
    /// Phone idiom. Inference only runs on phones.
    public var isPhone: Bool

    public init(
        width: Double,
        height: Double,
        windowCentre: (x: Double, y: Double)? = nil,
        division: DuoRect? = nil,
        hingeStatus: DuoHingeStatus? = nil,
        isPhone: Bool
    ) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.windowCentre = windowCentre
        self.division = division
        self.hingeStatus = hingeStatus
        self.isPhone = isPhone
    }

    public static func == (lhs: DuoPoseInput, rhs: DuoPoseInput) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
            && lhs.windowCentre?.x == rhs.windowCentre?.x && lhs.windowCentre?.y == rhs.windowCentre?.y
            && lhs.division == rhs.division && lhs.hingeStatus == rhs.hingeStatus && lhs.isPhone == rhs.isPhone
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(windowCentre?.x)
        hasher.combine(windowCentre?.y)
        hasher.combine(division)
        hasher.combine(hingeStatus)
        hasher.combine(isPhone)
    }
}

/// The crease's keep-out band: nothing is laid out between `start` and
/// `end` along the axis across the crease.
public struct DuoCreaseBand: Sendable, Hashable {
    public enum Axis: String, Sendable, Hashable {
        /// The crease runs top to bottom; the band spans x.
        case vertical
        /// The crease runs left to right; the band spans y.
        case horizontal
    }

    public let axis: Axis
    public let start: Double
    public let end: Double
    /// Whether the band came from the system (`true`) or was inferred.
    public let fromSystem: Bool

    public init(axis: Axis, start: Double, end: Double, fromSystem: Bool) {
        self.axis = axis
        self.start = min(start, end)
        self.end = max(start, end)
        self.fromSystem = fromSystem
    }

    public var width: Double { end - start }
    public var centre: Double { (start + end) / 2 }

    /// The band as a rectangle across a container of the given size.
    public func rect(width containerWidth: Double, height containerHeight: Double) -> DuoRect {
        switch axis {
        case .vertical: DuoRect(x: start, y: 0, width: width, height: containerHeight)
        case .horizontal: DuoRect(x: 0, y: start, width: containerWidth, height: width)
        }
    }
}

/// The pose state machine. Feed it every layout pass; it remembers whether
/// this device has shown a crease, so the cover display reads as `folded`
/// rather than `none`, and it reports the transition for animation.
public struct DuoPoseMachine: Sendable, Hashable {
    /// The crease's clear band: 20 pt each side (`07-Polish-Spec.md` §1).
    public static let minimumBandWidth: Double = 40
    /// Each open pane must still be at least a compact phone layout wide
    /// (or tall); otherwise the pose is ignored for layout.
    public static let minimumPaneLength: Double = 320

    public private(set) var pose: DuoPose = .none
    public private(set) var band: DuoCreaseBand?
    /// Set once a crease has been seen (system or inferred).
    public private(set) var hasSeenCrease = false

    public init() {}

    /// A change of pose, for the shell's animation.
    public struct Transition: Sendable, Hashable {
        public let from: DuoPose
        public let to: DuoPose
        /// Opening or closing the device (cover ↔ inner display): the
        /// surface selection is kept; the shell cross-fades.
        public var isFold: Bool { from.isOpen != to.isOpen }
        /// Book ↔ laptop: the same panes rotate around the crease.
        public var isRotation: Bool { from.isOpen && to.isOpen && from != to }
    }

    /// Reads the pose for `input`. Returns the transition when the pose
    /// changed, `nil` otherwise.
    @discardableResult
    public mutating func update(_ input: DuoPoseInput) -> Transition? {
        let previous = pose
        let newBand = Self.band(for: input)
        if let newBand {
            hasSeenCrease = true
            band = newBand
            pose = newBand.axis == .vertical ? .book : .laptop
        } else {
            band = nil
            pose = hasSeenCrease ? .folded : .none
        }
        return previous == pose ? nil : Transition(from: previous, to: pose)
    }

    /// The crease band for one input, or `nil` when there is none to keep
    /// clear (or the panes either side would be too small to use).
    public static func band(for input: DuoPoseInput) -> DuoCreaseBand? {
        // Closed: the app is on the cover display, whatever the size says.
        if input.hingeStatus == .closed { return nil }

        let candidate: DuoCreaseBand?
        if let division = input.division, division.width > 0 || division.height > 0 {
            candidate = systemBand(division, input: input)
        } else {
            candidate = inferredBand(input)
        }
        guard let candidate else { return nil }

        // Both panes must stay usable.
        let length = candidate.axis == .vertical ? input.width : input.height
        let before = candidate.start
        let after = length - candidate.end
        guard before >= minimumPaneLength, after >= minimumPaneLength else { return nil }
        return candidate
    }

    /// The system's division, widened to at least the 40 pt band around its
    /// centre line. A division taller than wide is a vertical crease.
    static func systemBand(_ division: DuoRect, input: DuoPoseInput) -> DuoCreaseBand? {
        let vertical = division.height >= division.width
        if vertical {
            guard division.maxX > 0, division.minX < input.width else { return nil }
            let mid = division.midX
            return DuoCreaseBand(
                axis: .vertical,
                start: min(division.minX, mid - minimumBandWidth / 2),
                end: max(division.maxX, mid + minimumBandWidth / 2),
                fromSystem: true
            )
        } else {
            guard division.maxY > 0, division.minY < input.height else { return nil }
            let mid = division.midY
            return DuoCreaseBand(
                axis: .horizontal,
                start: min(division.minY, mid - minimumBandWidth / 2),
                end: max(division.maxY, mid + minimumBandWidth / 2),
                fromSystem: true
            )
        }
    }

    /// Inference from size: only on a phone, only on a window that is
    /// neither compact (cover, portrait) nor short (landscape iPhone).
    static func inferredBand(_ input: DuoPoseInput) -> DuoCreaseBand? {
        guard input.isPhone else { return nil }
        let metrics = LayoutMetrics(width: input.width, height: input.height)
        guard metrics.widthClass != .compact, metrics.heightClass == .tall else { return nil }
        let half = minimumBandWidth / 2
        if input.width >= input.height {
            let centre = input.windowCentre?.x ?? input.width / 2
            return DuoCreaseBand(axis: .vertical, start: centre - half, end: centre + half, fromSystem: false)
        } else {
            let centre = input.windowCentre?.y ?? input.height / 2
            return DuoCreaseBand(axis: .horizontal, start: centre - half, end: centre + half, fromSystem: false)
        }
    }
}

/// The two panes either side of the crease.
public struct DuoPanes: Sendable, Hashable {
    /// Leading (book) or top (laptop) pane.
    public let first: DuoRect
    /// Trailing (book) or bottom (laptop) pane.
    public let second: DuoRect
    /// The keep-out band between them.
    public let crease: DuoRect
    public let pose: DuoPose

    /// Splits a `width` × `height` shell around `band`. The panes meet the
    /// band exactly: the band already holds the 20 pt clear on each side,
    /// so the panes add no margin towards the crease (board `v2DuoBook`).
    public init(width: Double, height: Double, band: DuoCreaseBand) {
        crease = band.rect(width: width, height: height)
        switch band.axis {
        case .vertical:
            pose = .book
            first = DuoRect(x: 0, y: 0, width: band.start.rounded(.down), height: height)
            let secondX = band.end.rounded(.up)
            second = DuoRect(x: secondX, y: 0, width: width - secondX, height: height)
        case .horizontal:
            pose = .laptop
            first = DuoRect(x: 0, y: 0, width: width, height: band.start.rounded(.down))
            let secondY = band.end.rounded(.up)
            second = DuoRect(x: 0, y: secondY, width: width, height: height - secondY)
        }
    }

    /// Each pane is its own compact grid (`07-Polish-Spec.md` §1).
    public var firstMetrics: LayoutMetrics { LayoutMetrics(width: first.width, height: first.height) }
    public var secondMetrics: LayoutMetrics { LayoutMetrics(width: second.width, height: second.height) }

    /// The outer margin of each pane: the compact class margin (16) on the
    /// screen edge, nothing toward the crease.
    public static let outerMargin: Double = 16

    /// Whether `rect` (in the shell's coordinates) keeps clear of the crease.
    public func keepsClear(_ rect: DuoRect) -> Bool {
        !rect.intersects(crease)
    }
}

/// What each pane shows in the open poses (`03-Layout-Strategy.md`).
public enum DuoArrangement {
    /// Book: the selected tab picks what leads the leading pane; the
    /// trailing pane holds the header, strip, deck and tab bar.
    public enum BookLead: String, Sendable, Hashable {
        /// Screen (docked) over the Pointer, app dock at the foot.
        case screenOverPointer
        /// The Pointer alone; a running screen floats as a tile over it.
        case pointer
    }

    /// The leading pane for the selected surface ("pointer", "screen",
    /// "deck"). The deck has its own pane, so Deck leads with the Pointer.
    public static func bookLead(selected surface: String) -> BookLead {
        surface == "screen" ? .screenOverPointer : .pointer
    }

    /// Laptop: the screen is always on top, so the bottom shows the
    /// Pointer or the Deck. Screen → Pointer.
    public static func laptopBottomShowsDeck(selected surface: String) -> Bool {
        surface == "deck"
    }

    /// The book's tab bar: Deck has its own pane, so Pointer and Screen.
    public static let bookTabs = ["pointer", "screen"]
    /// The laptop's tab bar: Screen is always on top, so Pointer and Deck.
    public static let laptopTabs = ["pointer", "deck"]
}
