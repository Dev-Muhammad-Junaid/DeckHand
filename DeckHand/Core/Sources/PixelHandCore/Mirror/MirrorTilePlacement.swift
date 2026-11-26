//
//  MirrorTilePlacement.swift
//  PixelHandCore
//
//  Where the floating screen tile may sit over a surface. The Pointer
//  surface reserves its click strip, its caption row and the keyboard
//  button; the Deck surface reserves its header (build 19). The tile is
//  anchored to the pad's top-trailing corner (or, on the Deck, the
//  canvas below the header), and every
//  drag and pinch is clamped so the tile stays inside the canvas and clear
//  of those areas (polish spec: the tile never covers a control).
//
//  All rectangles share one coordinate space (the canvas the tile floats
//  in), top-left origin, in points.
//

import Foundation

/// Where the floating tile rests, what it keeps clear of, and whether it
/// may step aside when nothing is clear (`MirrorTilePlacement.surfacePlan`).
public struct MirrorTileSurfacePlan: Equatable, Sendable {
    /// The rect the tile's home is anchored to (top-trailing); the canvas
    /// when nil.
    public var anchor: MirrorRect?
    /// Areas the tile never covers.
    public var keepOut: [MirrorRect]
    /// True while the deck is being edited: with no clear spot left, the
    /// tile hides instead of covering the least it can.
    public var stepsAsideWhenCrowded: Bool

    public init(anchor: MirrorRect?, keepOut: [MirrorRect], stepsAsideWhenCrowded: Bool = false) {
        self.anchor = anchor
        self.keepOut = keepOut
        self.stepsAsideWhenCrowded = stepsAsideWhenCrowded
    }
}

public enum MirrorTilePlacement {
    /// Clearance between the tile and a reserved area.
    public static let keepOutGap = 8.0
    /// Clearance between the tile and the canvas edge.
    public static let edgeMargin = 8.0
    /// The tile's inset from the pad's top-trailing corner (board: 12 pt).
    public static let homeInset = 12.0

    /// The areas the tile must stay clear of on the Pointer surface. The
    /// caption grows and shrinks as it names the gesture, so the whole
    /// caption row across the pad is reserved: the tile doesn't jump when
    /// `POINTER` becomes `DRAG LOCKED · TAP TO DROP`.
    public static func pointerKeepOut(
        pad: MirrorRect?,
        clickStrip: MirrorRect?,
        caption: MirrorRect?,
        keyboard: MirrorRect?
    ) -> [MirrorRect] {
        var areas: [MirrorRect] = []
        if let clickStrip { areas.append(clickStrip) }
        if let caption {
            if let pad {
                areas.append(MirrorRect(x: pad.x, y: caption.y, width: pad.width, height: caption.height))
            } else {
                areas.append(caption)
            }
        }
        if let keyboard { areas.append(keyboard) }
        return areas
    }

    /// The tile's home anchor and the areas it keeps clear of, for
    /// whichever surface reported its parts (all in the canvas's space).
    ///
    /// - Pointer: anchored to the pad; clear of the click strip, the
    ///   caption row and the keyboard button (`pointerKeepOut`).
    /// - Deck: clear of the deck header (page name, counter, pin and Edit;
    ///   Undo, the page menu and Done while editing), reported across the
    ///   deck's width so the tile doesn't jump as the counter comes and
    ///   goes. Without a pad, the tile's home is the canvas below the
    ///   header (build 19: on iPhone the tile sat on the counter, pin and
    ///   Edit, and `ph.deck.edit` wasn't hittable).
    /// - With both (an iPad showing the pad and the deck column), the pad
    ///   stays the anchor and every area is kept clear.
    /// - Deck in edit mode (build 23, VQ-083): the edit grid (keys, ghost
    ///   slots and Add key) is kept clear too. Where no clear spot is left
    ///   for the smallest tile (iPhone: the grid fills the canvas under the
    ///   header), the tile steps aside until Done (`isShown`).
    public static func surfaceLayout(
        bounds: MirrorRect,
        pad: MirrorRect? = nil,
        clickStrip: MirrorRect? = nil,
        caption: MirrorRect? = nil,
        keyboard: MirrorRect? = nil,
        deckHeader: MirrorRect? = nil,
        deckEditGrid: MirrorRect? = nil
    ) -> (anchor: MirrorRect?, keepOut: [MirrorRect]) {
        let plan = surfacePlan(
            bounds: bounds, pad: pad, clickStrip: clickStrip, caption: caption,
            keyboard: keyboard, deckHeader: deckHeader, deckEditGrid: deckEditGrid
        )
        return (plan.anchor, plan.keepOut)
    }

    /// `surfaceLayout` plus whether the tile may step aside (hide) when it
    /// has no clear spot: while the deck is being edited, and over an empty
    /// deck page at the Huge band.
    ///
    /// - deckEmptyState: the empty page's glyph, "No keys yet", message and
    ///   Add keys (build 24, VQ-098: the tile covered the title at AX3 and
    ///   most of the card at AX5). Always kept clear; at the Huge band,
    ///   where it fills the page, the tile steps aside when nothing is
    ///   clear (`emptyStateStepsAside`).
    public static func surfacePlan(
        bounds: MirrorRect,
        pad: MirrorRect? = nil,
        clickStrip: MirrorRect? = nil,
        caption: MirrorRect? = nil,
        keyboard: MirrorRect? = nil,
        deckHeader: MirrorRect? = nil,
        deckEditGrid: MirrorRect? = nil,
        deckEmptyState: MirrorRect? = nil,
        band: TypeBand = .standard
    ) -> MirrorTileSurfacePlan {
        var keepOut = pointerKeepOut(pad: pad, clickStrip: clickStrip, caption: caption, keyboard: keyboard)
        if let deckHeader { keepOut.append(deckHeader) }
        if let deckEditGrid { keepOut.append(deckEditGrid) }
        if let deckEmptyState { keepOut.append(deckEmptyState) }
        let stepsAside = deckEditGrid != nil
            || (deckEmptyState != nil && emptyStateStepsAside(band: band))
        if let pad { return MirrorTileSurfacePlan(anchor: pad, keepOut: keepOut, stepsAsideWhenCrowded: stepsAside) }
        if let deckHeader {
            let top = min(max(deckHeader.y + deckHeader.height, bounds.y), bounds.y + bounds.height)
            let below = MirrorRect(x: bounds.x, y: top, width: bounds.width, height: bounds.y + bounds.height - top)
            return MirrorTileSurfacePlan(anchor: below, keepOut: keepOut, stepsAsideWhenCrowded: stepsAside)
        }
        return MirrorTileSurfacePlan(anchor: nil, keepOut: keepOut, stepsAsideWhenCrowded: stepsAside)
    }

    /// Whether an empty deck page lets the tile step aside when it has no
    /// clear spot: only at the Huge band (AX3–AX5), where the empty state
    /// fills the page. At smaller sizes the tile stays, shrunk and moved to
    /// cover as little as it can.
    public static func emptyStateStepsAside(band: TypeBand) -> Bool {
        band == .huge
    }

    /// Whether the tile is drawn. It always is, except while the deck is
    /// being edited and even the smallest tile (`minimumWidth`) has no spot
    /// clear of the header and the edit grid: then it steps aside until
    /// Done, rather than cover Done or the key slots (VQ-083).
    public static func isShown(
        _ plan: MirrorTileSurfacePlan,
        minimumWidth: Double,
        aspect: Double,
        extraHeight: Double = 0,
        in bounds: MirrorRect
    ) -> Bool {
        guard plan.stepsAsideWhenCrowded else { return true }
        return fits(
            width: minimumWidth,
            height: minimumWidth * aspect + extraHeight,
            in: bounds,
            avoiding: plan.keepOut
        )
    }

    /// The tile's resting frame: top-trailing in `anchor` (the pad, the
    /// canvas below the deck header, or the canvas; `surfaceLayout`),
    /// `homeInset` from both edges.
    public static func home(width: Double, height: Double, anchor: MirrorRect) -> MirrorRect {
        MirrorRect(
            x: anchor.x + anchor.width - homeInset - width,
            y: anchor.y + homeInset,
            width: width,
            height: height
        )
    }

    /// The frame nearest to `tile` (same size) that lies inside `bounds`
    /// (less `margin`) and clear of every rectangle in `keepOut` (plus
    /// `gap`). When no such spot exists (the tile is too big for the space
    /// left), the spot with the least overlap wins; `fittingWidth` avoids
    /// that case.
    public static func place(
        _ tile: MirrorRect,
        in bounds: MirrorRect,
        avoiding keepOut: [MirrorRect],
        margin: Double = edgeMargin,
        gap: Double = keepOutGap
    ) -> MirrorRect {
        let candidates = candidateOrigins(for: tile, in: bounds, avoiding: keepOut, margin: margin, gap: gap)
        let clear = candidates.filter { overlap(origin: $0, tile: tile, keepOut: keepOut, gap: gap) == 0 }
        let pick: (x: Double, y: Double)?
        if !clear.isEmpty {
            pick = clear.min { distance($0, tile) < distance($1, tile) }
        } else {
            pick = candidates.min { a, b in
                let oa = overlap(origin: a, tile: tile, keepOut: keepOut, gap: gap)
                let ob = overlap(origin: b, tile: tile, keepOut: keepOut, gap: gap)
                if abs(oa - ob) > epsilon { return oa < ob }
                return distance(a, tile) < distance(b, tile)
            }
        }
        guard let pick else { return tile }
        return MirrorRect(x: pick.x, y: pick.y, width: tile.width, height: tile.height)
    }

    /// Whether a tile of this size has any clear spot in `bounds`.
    public static func fits(
        width: Double,
        height: Double,
        in bounds: MirrorRect,
        avoiding keepOut: [MirrorRect],
        margin: Double = edgeMargin,
        gap: Double = keepOutGap
    ) -> Bool {
        let tile = MirrorRect(x: bounds.x, y: bounds.y, width: width, height: height)
        guard width <= bounds.width - 2 * margin + epsilon,
              height <= bounds.height - 2 * margin + epsilon else { return false }
        return candidateOrigins(for: tile, in: bounds, avoiding: keepOut, margin: margin, gap: gap)
            .contains { overlap(origin: $0, tile: tile, keepOut: keepOut, gap: gap) == 0 }
    }

    /// The largest width up to `proposed` (and at least `minimum`) at which
    /// the tile still has a clear spot. Height is `width × aspect + extra`
    /// (`extra`: chrome drawn under the picture, like the desktop dots).
    /// Returns `minimum` when even that doesn't fit; `place` then keeps the
    /// overlap as small as it can.
    public static func fittingWidth(
        proposed: Double,
        minimum: Double,
        aspect: Double,
        extraHeight: Double = 0,
        in bounds: MirrorRect,
        avoiding keepOut: [MirrorRect],
        margin: Double = edgeMargin,
        gap: Double = keepOutGap
    ) -> Double {
        func ok(_ width: Double) -> Bool {
            fits(width: width, height: width * aspect + extraHeight, in: bounds, avoiding: keepOut, margin: margin, gap: gap)
        }
        // The canvas alone caps the width; try that cap before searching.
        let byBounds = min(bounds.width - 2 * margin, aspect > 0 ? (bounds.height - 2 * margin - extraHeight) / aspect : .infinity)
        let top = max(min(proposed, byBounds), minimum)
        if ok(top) { return top }
        guard ok(minimum) else { return minimum }
        var low = minimum
        var high = top
        for _ in 0..<24 where high - low > 0.5 {
            let mid = (low + high) / 2
            if ok(mid) { low = mid } else { high = mid }
        }
        return low.rounded(.down)
    }

    // MARK: - Internals

    private static let epsilon = 1e-6

    /// The nearest clear origin to `p` lies at `p`, or with one or both
    /// coordinates on a bounds edge or a keep-out edge; this grid holds
    /// every such point.
    private static func candidateOrigins(
        for tile: MirrorRect,
        in bounds: MirrorRect,
        avoiding keepOut: [MirrorRect],
        margin: Double,
        gap: Double
    ) -> [(x: Double, y: Double)] {
        let xRange = range(low: bounds.x + margin, high: bounds.x + bounds.width - margin - tile.width)
        let yRange = range(low: bounds.y + margin, high: bounds.y + bounds.height - margin - tile.height)

        var xs = [clamp(tile.x, xRange), xRange.low, xRange.high]
        var ys = [clamp(tile.y, yRange), yRange.low, yRange.high]
        for area in keepOut {
            xs.append(area.x - gap - tile.width)
            xs.append(area.x + area.width + gap)
            ys.append(area.y - gap - tile.height)
            ys.append(area.y + area.height + gap)
        }
        let inX = xs.filter { $0 >= xRange.low - epsilon && $0 <= xRange.high + epsilon }
        let inY = ys.filter { $0 >= yRange.low - epsilon && $0 <= yRange.high + epsilon }
        var out: [(x: Double, y: Double)] = []
        for y in inY {
            for x in inX { out.append((x, y)) }
        }
        return out
    }

    /// A tile bigger than the bounds pins to the leading/top edge.
    private static func range(low: Double, high: Double) -> (low: Double, high: Double) {
        high < low ? (low, low) : (low, high)
    }

    private static func clamp(_ value: Double, _ range: (low: Double, high: Double)) -> Double {
        min(max(value, range.low), range.high)
    }

    private static func distance(_ origin: (x: Double, y: Double), _ tile: MirrorRect) -> Double {
        let dx = origin.x - tile.x
        let dy = origin.y - tile.y
        return dx * dx + dy * dy
    }

    /// Total area the tile at `origin` shares with the keep-outs (each grown
    /// by `gap`). Touching edges don't count.
    private static func overlap(origin: (x: Double, y: Double), tile: MirrorRect, keepOut: [MirrorRect], gap: Double) -> Double {
        var total = 0.0
        for area in keepOut {
            let w = min(origin.x + tile.width, area.x + area.width + gap) - max(origin.x, area.x - gap)
            let h = min(origin.y + tile.height, area.y + area.height + gap) - max(origin.y, area.y - gap)
            if w > epsilon && h > epsilon { total += w * h }
        }
        return total
    }
}
