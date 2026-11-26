//
//  TypePanelGeometry.swift
//  PixelHandCore
//
//  Where the Type panel sits and how wide it is (owner testing, build 25,
//  OT-6). On build 25 the panel was a wide card fixed over the middle of
//  the window, so it hid the part of the Mac screen being typed into. Now
//  it moves and resizes:
//
//    floating   iPad (and any window at least 500 wide and 500 tall): drag
//               it by the grip anywhere in the free room, with a soft
//               magnet to the edges, the centre line and so the corners;
//               resize it from either bottom corner between
//               `minimumWidth` and `maximumWidth`.
//    docked     iPhone, and any window under 500 in either direction:
//               full width (or narrower in landscape), docked to the top
//               or the bottom of the free room; a drag moves it between
//               the two.
//
//  The free room is the window's safe area above the on-screen keyboard
//  and the app dock (`gap` above whichever is higher), so the panel never
//  sits under either. The place is stored as fractions of the free room
//  (0 = top or leading, 1 = bottom or trailing) plus a width, one place per
//  arrangement (`CanvasPlan.Form`) and orientation: a panel parked bottom
//  right stays bottom right when the keyboard comes up, when the window
//  is resized, and when the panel's height changes.
//
//  Pure rules, tested on Linux; `DeckHandiOS/Keyboard/TypePanel.swift`
//  (`TypePanelHost`) measures, drags and draws.
//

import Foundation

/// A rectangle in one coordinate space (the window's, in points).
public struct PanelRect: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// The window's orientation, for remembering one place per orientation.
public enum PanelOrientation: String, Sendable, Hashable, CaseIterable {
    case portrait, landscape

    /// Square counts as portrait.
    public init(width: Double, height: Double) {
        self = width > height ? .landscape : .portrait
    }
}

/// Where the person put the panel: fractions of the free room, a width and
/// (since build 26, OT-11) a height.
public struct TypePanelPlacement: Sendable, Hashable, Codable {
    /// 0 = leading edge of the free room, 1 = trailing edge.
    public var x: Double
    /// 0 = top of the free room, 1 = bottom (on the keyboard or the dock).
    public var y: Double
    /// The chosen width; `nil` until the person resizes (the default).
    public var width: Double?
    /// The chosen height; `nil` until the person resizes (the panel's
    /// shortest, `TypePanelLayout.heightRange`). Every block sizes to it.
    public var height: Double?

    public init(x: Double, y: Double, width: Double? = nil, height: Double? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Bottom centre at the default width: where build 25 put it.
    public static let initial = TypePanelPlacement(x: 0.5, y: 1)

    /// The `UserDefaults` key for one arrangement and orientation, for
    /// example `pixelhand.type.place.columns.landscape`.
    public static func storageKey(arrangement: String, orientation: PanelOrientation) -> String {
        "pixelhand.type.place.\(arrangement).\(orientation.rawValue)"
    }

    /// The stored place, or `nil` when nothing (or something unreadable or
    /// out of range) is stored.
    public static func restored(_ data: Data?) -> TypePanelPlacement? {
        guard let data, let place = try? JSONDecoder().decode(TypePanelPlacement.self, from: data) else { return nil }
        guard place.x.isFinite, place.y.isFinite, (0...1).contains(place.x), (0...1).contains(place.y) else { return nil }
        var clean = place
        if let width = place.width, !(width.isFinite && width > 0) { clean.width = nil }
        if let height = place.height, !(height.isFinite && height > 0) { clean.height = nil }
        return clean
    }

    /// What `restored` reads back.
    public var stored: Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

/// The rules for one window, keyboard and dock.
public struct TypePanelGeometry: Sendable, Hashable {
    public enum Style: String, Sendable, Hashable {
        /// Moves anywhere in the free room, with a magnet (iPad).
        case floating
        /// Full width, docked to the top or the bottom (iPhone).
        case docked
    }

    /// Which edge of the panel a resize handle moves.
    public enum ResizeEdge: String, Sendable, Hashable {
        case leading, trailing
    }

    // MARK: Constants (points)

    /// The narrowest panel: the stacked layout at its smallest
    /// (`TypePanelLayout`): 12 padding, a 192 pt field, 12, the 132 pt
    /// arrow cluster, 12 padding = 360. The same 336 pt inside also holds
    /// the 308 pt key block, the 220 pt numpad (stacked under it) and the
    /// header's grip, mode switch, numpad, collapse and close. Narrower
    /// and the field would drop under 192 pt (about 18 characters of
    /// body text), too short to read back what you typed.
    public static let minimumWidth: Double = 360
    /// The widest panel (build 25's cap): a block of keys, not a bar.
    public static let maximumWidth: Double = TypePanelLayout.wideMaximumWidth
    /// The width before the person resizes: wide enough for the one-block
    /// layout (field, arrows and keys side by side) on iPad.
    public static let defaultWidth: Double = 720
    /// Space kept between the panel and the keyboard, the dock and the
    /// window's edges.
    public static let gap: Double = 8
    /// How close (points) an edge, the centre line or a corner must be
    /// for the panel to snap to it when a drag ends.
    public static let magnet: Double = 24
    /// Below this width or height a window docks the panel (iPhone, Slide
    /// Over, the narrowest Stage Manager windows).
    public static let floatingMinimumSide: Double = 500
    /// The handles' touch target.
    public static let handleTarget: Double = 44

    // MARK: Inputs

    public let style: Style
    /// The free room: the safe area, less `gap` on every side, ending
    /// `gap` above the keyboard or the dock.
    public let room: PanelRect

    /// - Parameters:
    ///   - container: the safe area the panel is laid out in, in window
    ///     coordinates (measured with the keyboard's safe area ignored).
    ///   - windowWidth / windowHeight: the window's size (decides the
    ///     style).
    ///   - keyboardMinY: the on-screen keyboard's top, while it covers the
    ///     window.
    ///   - dockMinY: the app dock's top, while it shows.
    public init(
        container: PanelRect,
        windowWidth: Double,
        windowHeight: Double,
        keyboardMinY: Double? = nil,
        dockMinY: Double? = nil
    ) {
        style = (windowWidth < Self.floatingMinimumSide || windowHeight < Self.floatingMinimumSide) ? .docked : .floating
        // An obstacle below the container (a Stage Manager window above
        // the keyboard) doesn't count; one reaching above its top leaves
        // no room, and the panel pins to the top with its header in view.
        let obstacles = [keyboardMinY, dockMinY].compactMap { $0 }.filter { $0 < container.maxY + Self.gap }
        let bottom = min(container.maxY - Self.gap, (obstacles.min() ?? .infinity) - Self.gap)
        let top = container.minY + Self.gap
        let left = container.minX + Self.gap
        let right = container.maxX - Self.gap
        room = PanelRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }

    // MARK: Width

    /// The widths the panel may take here. A room narrower than the
    /// minimum (an iPhone SE in portrait) gives just the room's width.
    public var widthRange: ClosedRange<Double> {
        let upper = min(Self.maximumWidth, room.width)
        let lower = min(Self.minimumWidth, upper)
        return lower...upper
    }

    /// Whether resizing makes sense: there's more than one width to choose.
    public var canResize: Bool {
        widthRange.upperBound - widthRange.lowerBound >= 1
    }

    /// The width a placement draws at: its own, clamped, or the default
    /// (floating) or the whole room (docked).
    public func width(for placement: TypePanelPlacement) -> Double {
        let wanted = placement.width ?? (style == .floating ? Self.defaultWidth : widthRange.upperBound)
        return clampWidth(wanted)
    }

    public func clampWidth(_ width: Double) -> Double {
        let range = widthRange
        guard width.isFinite else { return range.upperBound }
        return min(range.upperBound, max(range.lowerBound, width.rounded()))
    }

    // MARK: Frame

    /// The panel's frame for a placement and the panel's measured height.
    public func frame(for placement: TypePanelPlacement, height: Double) -> PanelRect {
        frame(for: placement, size: (width(for: placement), height))
    }

    /// The frame for a placement and a measured size: the collapsed pill
    /// sits by the same fractions as the panel, so it folds into the same
    /// corner it opens from.
    public func frame(for placement: TypePanelPlacement, size: (width: Double, height: Double)) -> PanelRect {
        let width = min(size.width, room.width)
        let height = size.height
        let freeX = max(0, room.width - width)
        let freeY = max(0, room.height - height)
        let fx = style == .docked ? 0.5 : clampUnit(placement.x)
        let fy = style == .docked ? (placement.y < 0.5 ? 0 : 1) : clampUnit(placement.y)
        // A panel taller than the room keeps its top in view (its header,
        // the grip and the close button).
        return PanelRect(
            x: (room.minX + freeX * fx).rounded(),
            y: (room.minY + freeY * fy).rounded(),
            width: width,
            height: height
        )
    }

    /// Any frame kept in the free room (build 28 bug 6): a frame worked
    /// out before the keyboard came up, before the window turned, or while
    /// a drag or resize was in flight is moved, never resized, so it ends
    /// above the keyboard and the dock and inside the window's edges. A
    /// panel taller than the room keeps its top (the header, the grip and
    /// close) in view. The remembered place isn't touched: it is fractions
    /// of the room, so the same corner comes back when the keyboard goes.
    public func kept(_ frame: PanelRect) -> PanelRect {
        guard [frame.x, frame.y, frame.width, frame.height].allSatisfy(\.isFinite) else {
            return PanelRect(x: room.minX, y: room.minY, width: max(0, frame.width.isFinite ? frame.width : 0), height: max(0, frame.height.isFinite ? frame.height : 0))
        }
        var kept = frame
        if style == .docked {
            kept.x = (room.minX + max(0, room.width - frame.width) / 2).rounded()
        } else {
            kept.x = min(room.minX + max(0, room.width - frame.width), max(room.minX, frame.x))
        }
        kept.y = min(room.minY + max(0, room.height - frame.height), max(room.minY, frame.y))
        return kept
    }

    /// Whether `frame` ends above the keyboard and the dock (within the
    /// free room, give or take a point of rounding).
    public func fitsAbove(_ frame: PanelRect) -> Bool {
        frame.maxY <= room.maxY + 1 && frame.minY >= room.minY - 1
    }

    /// Where a panel being dragged draws: its origin clamped into the
    /// room, without the magnet (that comes when the drag ends).
    public func clamped(origin x: Double, _ y: Double, size: (width: Double, height: Double)) -> PanelRect {
        let maxX = room.minX + max(0, room.width - size.width)
        let maxY = room.minY + max(0, room.height - size.height)
        let cy = min(maxY, max(room.minY, y))
        // Docked panels only move up and down.
        let cx = style == .docked
            ? (room.minX + max(0, room.width - size.width) / 2).rounded()
            : min(maxX, max(room.minX, x))
        return PanelRect(x: cx, y: cy, width: size.width, height: size.height)
    }

    /// The placement a drag ends in: clamped, then snapped. Floating
    /// panels snap to the leading or trailing edge, the centre line, the
    /// top or the bottom when within `magnet` (two at once make a
    /// corner); docked panels go to the nearer of the top and the bottom.
    /// The width is kept.
    public func placement(
        droppedAt x: Double,
        _ y: Double,
        size: (width: Double, height: Double),
        keeping current: TypePanelPlacement
    ) -> TypePanelPlacement {
        let frame = clamped(origin: x, y, size: size)
        let freeX = max(0, room.width - size.width)
        let freeY = max(0, room.height - size.height)
        if style == .docked {
            let toBottom = frame.midY >= room.midY
            return TypePanelPlacement(x: 0.5, y: toBottom ? 1 : 0, width: current.width, height: current.height)
        }
        var fx = freeX > 0 ? (frame.minX - room.minX) / freeX : 0.5
        var fy = freeY > 0 ? (frame.minY - room.minY) / freeY : 1
        // Snap x: leading, centre, trailing.
        let leading = frame.minX - room.minX
        let trailing = room.maxX - frame.maxX
        let centre = abs(frame.midX - room.midX)
        if leading <= Self.magnet { fx = 0 }
        else if trailing <= Self.magnet { fx = 1 }
        else if centre <= Self.magnet { fx = 0.5 }
        // Snap y: top, bottom.
        if frame.minY - room.minY <= Self.magnet { fy = 0 }
        else if room.maxY - frame.maxY <= Self.magnet { fy = 1 }
        return TypePanelPlacement(x: rounded(fx), y: rounded(fy), width: current.width, height: current.height)
    }

    /// A resize in flight from a bottom corner (OT-11): the width as
    /// `resized(_:edge:translation:)`, and the bottom edge moved by `dy`
    /// (positive = taller), the height clamped to `heights` (the layout's
    /// range for the new width) and to the room's height.
    ///
    /// A panel sitting on the room's bottom (the usual case: it rides on
    /// the keyboard or the dock) keeps its bottom there, so it grows and
    /// shrinks from its top (build 27 bug 2: there was no room below it,
    /// so dragging its corner changed nothing and the arrows never grew).
    /// Anywhere else the top holds, and a panel that would pass the room's
    /// bottom rises instead.
    public func resized(
        _ start: PanelRect,
        edge: ResizeEdge,
        translation dx: Double,
        _ dy: Double,
        heights: (Double) -> ClosedRange<Double>
    ) -> PanelRect {
        var frame = resized(start, edge: edge, translation: dx)
        let range = heights(frame.width)
        let wanted = (start.height + (dy.isFinite ? dy : 0)).rounded()
        let tallest = min(range.upperBound, max(range.lowerBound, room.height))
        let height = max(range.lowerBound, min(tallest, wanted))
        frame.height = height
        let onBottom = start.maxY >= room.maxY - 1
        if onBottom || start.minY + height > room.maxY {
            // The bottom holds on the room's bottom; never above its top.
            frame.y = max(room.minY, room.maxY - height)
        } else {
            frame.y = start.minY
        }
        return frame
    }

    /// A resize in flight: the frame with one edge moved by `translation`
    /// (positive = right), the other edge held, the width clamped to
    /// `widthRange` and to the room. Docked panels resize from the centre
    /// (both edges move).
    public func resized(_ start: PanelRect, edge: ResizeEdge, translation: Double) -> PanelRect {
        let range = widthRange
        var frame = start
        if style == .docked {
            let delta = edge == .trailing ? translation : -translation
            let width = min(range.upperBound, max(range.lowerBound, (start.width + 2 * delta).rounded()))
            frame.width = width
            frame.x = (room.midX - width / 2).rounded()
            return frame
        }
        switch edge {
        case .trailing:
            let room = self.room.maxX - start.minX
            frame.width = min(min(range.upperBound, room), max(range.lowerBound, (start.width + translation).rounded()))
        case .leading:
            let room = start.maxX - self.room.minX
            let width = min(min(range.upperBound, room), max(range.lowerBound, (start.width - translation).rounded()))
            frame.x = start.maxX - width
            frame.width = width
        }
        return frame
    }

    /// The placement a resize ends in: the new width (and height, when
    /// `keepsHeight`), and the place that keeps the frame where it was
    /// (snapped like a drag).
    public func placement(resizedTo frame: PanelRect, keeping current: TypePanelPlacement, keepsHeight: Bool = false) -> TypePanelPlacement {
        let width = clampWidth(frame.width)
        var place = placement(droppedAt: frame.minX, frame.minY, size: (width, frame.height), keeping: current)
        place.width = width
        place.height = keepsHeight ? frame.height.rounded() : current.height
        return place
    }

    /// The height a placement draws at: its own, or `nil` for the
    /// layout's shortest.
    public func height(for placement: TypePanelPlacement) -> Double? {
        guard let height = placement.height, height.isFinite, height > 0 else { return nil }
        return height
    }

    // MARK: Loupe (OT-12)

    /// Where the loupe on the Mac's focused field sits: attached to the
    /// panel, as wide as it, above it when there's room (the panel usually
    /// rides on the keyboard or the dock), else below it, else over the
    /// panel's top (the room is too short for both). `nil` with no room.
    public func loupeFrame(panel: PanelRect) -> PanelRect? {
        guard room.width > 0, room.height > 0, panel.width > 0 else { return nil }
        let height = Self.loupeHeight(panelWidth: panel.width)
        let above = panel.minY - room.minY - Self.gap
        let below = room.maxY - panel.maxY - Self.gap
        if above >= height {
            return PanelRect(x: panel.x, y: panel.minY - Self.gap - height, width: panel.width, height: height)
        }
        if below >= height {
            return PanelRect(x: panel.x, y: panel.maxY + Self.gap, width: panel.width, height: height)
        }
        // Squeeze into whichever side has more, never under the minimum;
        // past that it overlaps the panel's top edge.
        let side = max(above, below)
        let squeezed = max(Self.loupeMinimumHeight, side)
        if above >= below {
            return PanelRect(x: panel.x, y: max(room.minY, panel.minY - Self.gap - squeezed), width: panel.width, height: squeezed)
        }
        return PanelRect(x: panel.x, y: min(panel.maxY + Self.gap, room.maxY - squeezed), width: panel.width, height: squeezed)
    }

    /// The loupe's height for a panel width: a wide strip (a text field is
    /// wide and short), 30 % of the width, 96…200 pt.
    public static func loupeHeight(panelWidth: Double) -> Double {
        min(loupeMaximumHeight, max(loupeMinimumHeight, (panelWidth * 0.3).rounded()))
    }

    public static let loupeMinimumHeight: Double = 96
    public static let loupeMaximumHeight: Double = 200

    // MARK: Helpers

    private func clampUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(1, max(0, value))
    }

    /// Three decimals is plenty for a fraction of a window.
    private func rounded(_ value: Double) -> Double {
        (clampUnit(value) * 1000).rounded() / 1000
    }
}
