//
//  MacPanelMotion.swift
//  PixelHandCore – Design
//
//  How the Mac panel moves (OR-09 and the owner's motion rule): status
//  dots and rows fade in and out, 150–200 ms ease-out, and nothing flows
//  in from the bottom. Reduce Motion changes at once.
//
//  Also how a dot glyph sits on a tile (OR-10): the lit dots, not the
//  glyph's canvas, are centred, so art whose canvas has an empty column
//  or row still lands on the tile's (and the QR's) centre.
//

import Foundation

public enum MacPanelMotion {
    /// The fade for dots and status rows, in seconds.
    public static let fadeDuration: Double = 0.18

    /// The fade under the person's setting: none with Reduce Motion.
    public static func fade(reduceMotion: Bool) -> Double? {
        reduceMotion ? nil : fadeDuration
    }

    /// A status dot's opacity once it has faded in, and at the dim end of
    /// its breath (the breath animates opacity only, never position).
    public static let breathDim: Double = 0.55
    /// One half of a breath, in seconds (a full breath is 2.4 s).
    public static let halfBreath: Double = 1.2
}

/// Centring dot art by its lit dots (OR-10).
public enum GlyphInkCentring {
    /// The lit dots' bounding box in cells: first and last column and row.
    public struct Box: Sendable, Hashable {
        public let minX: Int, maxX: Int, minY: Int, maxY: Int
        public var width: Int { maxX - minX + 1 }
        public var height: Int { maxY - minY + 1 }
    }

    /// The box around every cell in `rows` that isn't `"."` or a space;
    /// `nil` when nothing is lit.
    public static func box(rows: [String]) -> Box? {
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.enumerated() where cell != "." && cell != " " {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        return Box(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    /// The box around a glyph's lit points.
    public static func box(glyph: GlyphBitmap) -> Box? {
        box(rows: glyph.pattern)
    }

    /// How far to move art drawn on a `columns` × `rows` canvas at `pitch`
    /// so its lit dots, not its canvas, sit on the frame's centre. Positive
    /// x moves right, positive y down.
    public static func offset(box: Box, columns: Int, rows: Int, pitch: Double) -> (x: Double, y: Double) {
        let inkCentreX = Double(box.minX + box.maxX + 1) / 2
        let inkCentreY = Double(box.minY + box.maxY + 1) / 2
        return ((Double(columns) / 2 - inkCentreX) * pitch, (Double(rows) / 2 - inkCentreY) * pitch)
    }

    /// The largest pitch, in whole points (or `step`s of a point), at which
    /// the lit box fits inside `side` with `margin` on every side.
    public static func pitch(fitting box: Box, in side: Double, margin: Double, step: Double = 0.5) -> Double {
        let room = max(0, side - 2 * margin)
        let raw = room / Double(max(box.width, box.height))
        guard step > 0 else { return raw }
        return max(step, (raw / step).rounded(.down) * step)
    }
}

/// The QR code's centre tile (OR-10): a whole, odd number of modules
/// centred on the centre module, inside the cleared square.
public enum QRCentreTile {
    /// Side of the tile in modules: the cleared square less one module of
    /// quiet border, kept odd so the tile's centre is the centre module's.
    public static func sideModules(modules n: Int) -> Int {
        let cleared = QRDotPlan.clearedSide(modules: n)
        guard cleared >= 3 else { return 0 }
        let side = cleared - 2
        return side % 2 == 1 ? side : side - 1
    }

    /// The tile's frame in the code's drawing space (quiet zone included),
    /// as an origin and side in points.
    public static func frame(modules n: Int, moduleSide: Double, quietModules: Int) -> (x: Double, y: Double, side: Double)? {
        let sideModules = sideModules(modules: n)
        guard sideModules > 0 else { return nil }
        let start = quietModules + (n - sideModules) / 2
        return (Double(start) * moduleSide, Double(start) * moduleSide, Double(sideModules) * moduleSide)
    }

    /// The centre module's centre in the same space: where the tile's centre
    /// must land.
    public static func centreModuleCentre(modules n: Int, moduleSide: Double, quietModules: Int) -> Double {
        (Double(quietModules + n / 2) + 0.5) * moduleSide
    }
}
