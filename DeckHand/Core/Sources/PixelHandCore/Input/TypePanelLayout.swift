//
//  TypePanelLayout.swift
//  PixelHandCore
//
//  How the Type panel's blocks share the panel (owner testing, build 26,
//  OT-11). Build 25 sized the panel by its width only: the arrows stayed
//  44 pt whatever the panel, a lone Paste button sat in a strip under the
//  field, and the arrow cluster left an empty block under it. Now the
//  person sizes the panel in both directions and **every block is cut
//  from the panel's current width and height**, with nothing left over:
//
//    one block   wide and short: field │ actions │ arrows │ keys, one band
//                two rows tall.
//    stacked     field │ actions │ arrows on top, the key rows under them
//                spanning the whole width.
//    numpad      only the arrows and the numpad (and, in Compose, the
//                draft), filling the panel together.
//
//  Rows grow from 44 pt (the touch target) to 72 pt; the key rows' cells
//  stretch to the panel's width; the field takes what the keys leave and
//  can show two lines. At the shortest heights the arrows go to one row
//  (← ↑ ↓ →). Pure rules, tested on Linux; `DeckHandiOS/Keyboard/
//  TypePanel.swift` places its views at these frames.
//

import Foundation

/// The panel's blocks, each with its frame inside the panel's body (below
/// the header, inside the padding) and its cells.
public struct TypePanelLayout: Sendable, Hashable {
    /// What the panel shows.
    public enum Body: String, Sendable, Hashable {
        /// Header, field, actions, arrows and keys.
        case full
        /// A hardware keyboard types: the field holds focus to take the
        /// keys; no action column.
        case keysOnly
    }

    /// How the blocks share the panel.
    public enum Arrangement: String, Sendable, Hashable {
        /// Field, actions, arrows and keys side by side in one band.
        case oneBlock
        /// Field, actions and arrows on top; the two key rows under them.
        case stacked
        /// The numpad is on: only the arrows and the numpad (plus the
        /// draft in Compose).
        case numpad
    }

    /// The panel's blocks.
    public enum Block: String, Sendable, Hashable, CaseIterable {
        case field, actions, arrows, keys, numpad
    }

    /// The small buttons beside the field.
    public enum Action: String, Sendable, Hashable {
        /// Live: press Tab, which takes the Mac app's inline suggestion
        /// (OT-13).
        case accept
        /// Live: paste this device's clipboard on the Mac.
        case paste
        /// Compose: press Return after sending.
        case sendReturn
        /// Compose: send the draft.
        case send
    }

    /// A block's frame and its grid of cells. Cells may be wider than tall
    /// (the key rows stretch to the panel's width).
    public struct Grid: Sendable, Hashable {
        /// In the body's space: origin at the body's top-leading corner.
        public let rect: PanelRect
        public let columns: Int
        public let rows: Int

        public var cellWidth: Double { columns > 0 ? rect.width / Double(columns) : 0 }
        public var cellHeight: Double { rows > 0 ? rect.height / Double(rows) : 0 }
    }

    /// An action button and its cell in the action block.
    public struct ActionCell: Sendable, Hashable {
        public let action: Action
        public let column: Int
        public let row: Int
    }

    // MARK: Constants (points)

    /// The smallest cell: every key keeps a 44 pt touch target.
    public static let keyPitch: Double = 44
    /// The tallest row: past this the keys stop growing and the panel
    /// stops getting taller (a 72 pt cap is already a big target; more
    /// would just cover the Mac picture).
    public static let maximumRowHeight: Double = 72
    /// The gap inside a cell between caps.
    public static let keyGap: Double = 4
    public static var keyCap: Double { keyPitch - keyGap }
    /// Between blocks.
    public static let blockGap: Double = 8
    /// The panel's inner padding.
    public static let padding: Double = 12
    /// The header row, and the space under it.
    public static let headerHeight: Double = 44
    public static let headerSpacing: Double = 8
    /// The field never gets narrower than this (about 13 characters of
    /// body text, two lines when the band is tall enough).
    public static let fieldMinimumWidth: Double = 144
    /// The panel never grows past this wide: a block of keys, not a bar.
    public static let wideMaximumWidth: Double = 760
    /// Below this much room above the keyboard the header row goes.
    public static let headerMinimumRoom: Double = 300
    /// From this panel width the header names the app beside its icon.
    public static let appNameMinimumWidth: Double = 560
    /// From this width the header is one row: grip 44, Live│Compose 144,
    /// the target chip 44, numpad 44, collapse 44, close 44, six 4 pt
    /// gaps and the padding. Narrower, the mode switch and the app's name
    /// take a second row.
    public static let oneRowHeaderMinimumWidth: Double = 2 * padding + 6 * 44 + 144 + 6 * 4

    /// The key block's cells as build 25 drew them (44 pt), for reference.
    public static var keyBlockSize: (width: Double, height: Double) {
        (Double(TypeKeyBlock.columns) * keyPitch, Double(TypeKeyBlock.rows) * keyPitch)
    }
    public static var arrowsSize: (width: Double, height: Double) {
        (Double(ArrowCluster.columns) * keyPitch, Double(ArrowCluster.rows) * keyPitch)
    }
    public static var numpadSize: (width: Double, height: Double) {
        (Double(NumpadKey.columns) * keyPitch, Double(NumpadKey.rows) * keyPitch)
    }

    // MARK: Output

    public let body: Body
    public let mode: TypeMode
    /// The header row. Off when the room above the keyboard is short
    /// (iPhone landscape): the field row then carries the grip and the
    /// close button, and the field's placeholder names the target.
    public let showsHeader: Bool
    /// 1, or 2 on narrow panels (the mode switch and the app's name go to
    /// a second row); 0 without a header.
    public let headerRows: Int
    /// The header names the app beside its icon (else the icon alone).
    public let showsAppName: Bool
    /// The widest the panel may be in this window when no width is given.
    public let maximumWidth: Double
    public let panelWidth: Double
    /// The whole panel's height: padding, header and body.
    public let panelHeight: Double
    /// The heights this panel may take at its width (`TypePanelGeometry`
    /// clamps a resize to it).
    public let heightRange: ClosedRange<Double>
    public let arrangement: Arrangement
    public let arrowShape: ArrowCluster.Shape
    /// The blocks shown, with their frames. A block not listed is hidden
    /// (the view keeps it in the tree with no size, so the field never
    /// loses the keyboard to a reflow, OT-2).
    public let blocks: [Block: Grid]
    public let actionCells: [ActionCell]
    /// Lines the field shows before it scrolls.
    public let fieldLines: Int
    /// The side margin of the window.
    public let margin: Double

    public func grid(_ block: Block) -> Grid? { blocks[block] }
    public func shows(_ block: Block) -> Bool { blocks[block] != nil }

    /// The field's width (0 when hidden).
    public var fieldWidth: Double { blocks[.field]?.rect.width ?? 0 }
    /// The body's size (the union of the blocks).
    public var bodySize: (width: Double, height: Double) {
        let rects = blocks.values.map(\.rect)
        return (rects.map(\.maxX).max() ?? 0, rects.map(\.maxY).max() ?? 0)
    }

    /// Kept for build 25's callers: Compose's line count is the field's.
    public var composeLines: Int { fieldLines }

    // MARK: Init

    /// - Parameters:
    ///   - width / height: the window's (the shell's planning size).
    ///   - keyboard / keyboardOverlap: what covers the window.
    ///   - panelWidth: the panel's width (`TypePanelGeometry`); `nil` lays
    ///     out for the widest the window allows.
    ///   - panelHeight: the height the person gave it; `nil` takes the
    ///     shortest (the compact default). Clamped to `heightRange`.
    ///   - roomHeight: the free room's height; a panel taller than the
    ///     room shrinks to it (never below the range's minimum).
    ///   - showsNumpad: the numpad is on.
    ///   - mode: Live or Compose (the action column differs).
    public init(
        width: Double,
        height: Double,
        keyboard: KeyboardKind,
        keyboardOverlap: Double = 0,
        panelWidth: Double? = nil,
        panelHeight: Double? = nil,
        roomHeight: Double? = nil,
        showsNumpad: Bool = false,
        mode: TypeMode = .live
    ) {
        let metrics = LayoutMetrics(width: width, height: height)
        margin = metrics.margin
        self.mode = mode
        let body: Body = keyboard == .hardware ? .keysOnly : .full
        self.body = body
        maximumWidth = min(Self.wideMaximumWidth, max(0, width - 2 * metrics.margin))
        let panel = max(0, min(panelWidth ?? maximumWidth, Self.wideMaximumWidth))
        self.panelWidth = panel
        let above = height - (keyboard == .software ? keyboardOverlap : 0)
        showsHeader = above >= Self.headerMinimumRoom
        headerRows = showsHeader ? (panel >= Self.oneRowHeaderMinimumWidth ? 1 : 2) : 0
        showsAppName = panel >= Self.appNameMinimumWidth || headerRows == 2

        let spec = Spec(inner: max(0, panel - 2 * Self.padding), body: body, mode: mode, numpad: showsNumpad)
        let chrome = 2 * Self.padding + (showsHeader
            ? Double(headerRows) * Self.headerHeight + Self.headerSpacing * Double(headerRows)
            : 0)
        let bodyRange = spec.bodyRange
        heightRange = (chrome + bodyRange.lowerBound)...(chrome + bodyRange.upperBound)
        var wanted = panelHeight ?? heightRange.lowerBound
        if !wanted.isFinite { wanted = heightRange.lowerBound }
        if let roomHeight, roomHeight.isFinite { wanted = min(wanted, roomHeight) }
        let bodyHeight = min(bodyRange.upperBound, max(bodyRange.lowerBound, wanted - chrome))
        let plan = spec.plan(bodyHeight: bodyHeight)
        arrangement = plan.arrangement
        arrowShape = plan.arrowShape
        blocks = plan.blocks
        actionCells = plan.actions
        let used = plan.blocks.values.map(\.rect.maxY).max() ?? 0
        self.panelHeight = (chrome + used).rounded()
        fieldLines = plan.blocks[.field].map { Self.lines(forFieldHeight: $0.rect.height) } ?? 1
    }

    /// The lines a field this tall shows (body text: about 22 pt a line
    /// and 8 pt of inset above and below).
    public static func lines(forFieldHeight height: Double) -> Int {
        max(1, Int(((height - 16) / 22).rounded(.down)))
    }

    /// The panel's bottom padding inside its container: it sits `gap`
    /// above whichever is higher of the on-screen keyboard and the app
    /// dock. All values share the window's coordinate space.
    public static func bottomPadding(containerMaxY: Double, keyboardMinY: Double?, dockMinY: Double?, gap: Double = 8) -> Double {
        let obstacles = [keyboardMinY, dockMinY].compactMap { $0 }.filter { $0 < containerMaxY }
        guard let top = obstacles.min() else { return gap }
        return containerMaxY - top + gap
    }
}

// MARK: - The rules

extension TypePanelLayout {
    /// The arrangement rules for one inner width, body, mode and numpad.
    struct Spec {
        let inner: Double
        let body: Body
        let mode: TypeMode
        let numpad: Bool

        typealias Plan = (arrangement: Arrangement, arrowShape: ArrowCluster.Shape, blocks: [Block: Grid], actions: [ActionCell])

        private var gap: Double { TypePanelLayout.blockGap }
        private var minCell: Double { TypePanelLayout.keyPitch }
        private var maxRow: Double { TypePanelLayout.maximumRowHeight }
        private var fieldMin: Double { TypePanelLayout.fieldMinimumWidth }

        /// The action buttons beside the field, in order.
        var actions: [Action] {
            guard body == .full else { return [] }
            return mode == .live ? [.accept, .paste] : [.sendReturn, .send]
        }

        /// The cell the narrowest windows fall back to: in a panel
        /// narrower than seven 44 pt cells (a 320 pt Slide Over window),
        /// cells shrink so the key rows still fit, never under 32.
        private var floorCell: Double {
            min(minCell, max(32, (inner / Double(TypeKeyBlock.columns)).rounded(.down)))
        }

        /// The cells a field band of `rows` rows needs beside the field.
        private func bandColumns(rows: Int) -> Int {
            let shape: ArrowCluster.Shape = rows == 2 ? .invertedT : .row
            let actionColumns = actions.isEmpty ? 0 : (rows == 2 ? 1 : actions.count)
            return shape.columns + actionColumns
        }

        private func bandGaps(extraColumns: Bool) -> Double {
            (actions.isEmpty ? 1 : 2) * gap + (extraColumns ? gap : 0)
        }

        /// Whether the field keeps its minimum beside `columns` 44 pt cells.
        private func fieldFits(columns: Int, gaps: Double) -> Bool {
            inner - gaps - Double(columns) * minCell >= fieldMin - 0.5
        }

        /// One band, side by side: field, actions, inverted T, 7 key columns.
        var oneBlockFits: Bool {
            fieldFits(columns: bandColumns(rows: 2) + TypeKeyBlock.columns, gaps: bandGaps(extraColumns: true))
        }

        /// The arrows in one row beside the field (the shortest stacked).
        var rowArrowsFit: Bool {
            fieldFits(columns: bandColumns(rows: 1), gaps: bandGaps(extraColumns: false))
        }

        /// Arrows and numpad side by side: 3 + 5 columns of 44 pt.
        var numpadBesideFits: Bool {
            (inner - gap) / 8 >= minCell - 0.001
        }

        private var composeDraftRow: Bool { numpad && mode == .compose }

        /// The body heights this panel may take.
        var bodyRange: ClosedRange<Double> {
            if numpad {
                let draft = composeDraftRow ? 1.0 : 0
                let rows = (numpadBesideFits ? 4.0 : 5.0) + draft
                let gaps = (numpadBesideFits ? 0 : gap) + (composeDraftRow ? gap : 0)
                return (rows * minCell + gaps)...(rows * maxRow + gaps)
            }
            let stackedMax = 4 * maxRow + gap
            if oneBlockFits { return (2 * minCell)...stackedMax }
            if rowArrowsFit { return (3 * minCell + gap)...stackedMax }
            return (4 * floorCell + gap)...(max(4 * floorCell, 4 * maxRow) + gap)
        }

        func plan(bodyHeight h: Double) -> Plan {
            if numpad { return numpadPlan(h) }
            let rowStackedMin = 3 * minCell + gap
            let tStackedMin = 4 * minCell + gap
            if oneBlockFits && h < (rowArrowsFit ? rowStackedMin : tStackedMin) {
                return oneBlockPlan(h)
            }
            let rows = (h >= tStackedMin || !rowArrowsFit) ? 2 : 1
            return stackedPlan(h, fieldRows: rows)
        }

        // MARK: Bands

        /// Field, actions and arrows in a band `rows` tall at `y`, cells
        /// `cell` wide; returns the blocks and the action cells.
        private func fieldBand(
            y: Double, width: Double, rowHeight: Double, rows: Int, cell: Double
        ) -> (blocks: [Block: Grid], actions: [ActionCell], shape: ArrowCluster.Shape) {
            let shape: ArrowCluster.Shape = rows == 2 ? .invertedT : .row
            let actionColumns = actions.isEmpty ? 0 : (rows == 2 ? 1 : actions.count)
            let height = Double(rows) * rowHeight
            let arrowsWidth = Double(shape.columns) * cell
            let actionsWidth = Double(actionColumns) * cell
            let gaps = gap + (actionColumns > 0 ? gap : 0)
            let fieldWidth = max(0, width - arrowsWidth - actionsWidth - gaps)
            var blocks: [Block: Grid] = [:]
            blocks[.field] = Grid(rect: PanelRect(x: 0, y: y, width: fieldWidth, height: height), columns: 1, rows: 1)
            var x = fieldWidth + gap
            var cells: [ActionCell] = []
            if actionColumns > 0 {
                let actionRows = rows == 2 ? 2 : 1
                blocks[.actions] = Grid(rect: PanelRect(x: x, y: y, width: actionsWidth, height: height), columns: actionColumns, rows: actionRows)
                for (index, action) in actions.enumerated() {
                    cells.append(rows == 2
                        ? ActionCell(action: action, column: 0, row: index)
                        : ActionCell(action: action, column: index, row: 0))
                }
                x += actionsWidth + gap
            }
            blocks[.arrows] = Grid(rect: PanelRect(x: x, y: y, width: arrowsWidth, height: height), columns: shape.columns, rows: shape.rows)
            return (blocks, cells, shape)
        }

        /// The cell width a band gives its arrows and actions: square with
        /// the row while the field keeps its minimum, never under 44 (or
        /// the narrowest windows' floor).
        private func bandCell(rowHeight: Double, columns: Int, gaps: Double) -> Double {
            let room = (inner - fieldMin - gaps) / Double(columns)
            return max(floorCell, min(rowHeight, room))
        }

        private func oneBlockPlan(_ h: Double) -> Plan {
            let row = min(maxRow, max(minCell, h / 2))
            let columns = bandColumns(rows: 2) + TypeKeyBlock.columns
            let cell = bandCell(rowHeight: row, columns: columns, gaps: bandGaps(extraColumns: true))
            let keysWidth = Double(TypeKeyBlock.columns) * cell
            var band = fieldBand(y: 0, width: inner - keysWidth - gap, rowHeight: row, rows: 2, cell: cell)
            band.blocks[.keys] = Grid(
                rect: PanelRect(x: inner - keysWidth, y: 0, width: keysWidth, height: 2 * row),
                columns: TypeKeyBlock.columns, rows: TypeKeyBlock.rows
            )
            return (.oneBlock, band.shape, band.blocks, band.actions)
        }

        private func stackedPlan(_ h: Double, fieldRows: Int) -> Plan {
            let rows = Double(fieldRows + TypeKeyBlock.rows)
            let row = min(maxRow, max(floorCell, (h - gap) / rows))
            let cell = bandCell(rowHeight: row, columns: bandColumns(rows: fieldRows), gaps: bandGaps(extraColumns: false))
            var band = fieldBand(y: 0, width: inner, rowHeight: row, rows: fieldRows, cell: cell)
            let top = Double(fieldRows) * row + gap
            // The key rows span the whole width: no empty block beside them.
            band.blocks[.keys] = Grid(
                rect: PanelRect(x: 0, y: top, width: inner, height: 2 * row),
                columns: TypeKeyBlock.columns, rows: TypeKeyBlock.rows
            )
            return (.stacked, band.shape, band.blocks, band.actions)
        }

        private func numpadPlan(_ h: Double) -> Plan {
            var blocks: [Block: Grid] = [:]
            var cells: [ActionCell] = []
            let beside = numpadBesideFits
            let rows = (beside ? 4.0 : 5.0) + (composeDraftRow ? 1 : 0)
            let gaps = (beside ? 0 : gap) + (composeDraftRow ? gap : 0)
            let row = min(maxRow, max(minCell, (h - gaps) / rows))
            var y = 0.0
            if composeDraftRow {
                // Compose: the draft the numpad writes into, with +⏎ and
                // Send beside it, one row.
                let count = Double(actions.count)
                let cell = count > 0 ? max(minCell, min(row, (inner - fieldMin - gap) / count)) : 0
                let actionsWidth = count * cell
                let fieldWidth = inner - actionsWidth - (count > 0 ? gap : 0)
                blocks[.field] = Grid(rect: PanelRect(x: 0, y: 0, width: fieldWidth, height: row), columns: 1, rows: 1)
                if count > 0 {
                    blocks[.actions] = Grid(rect: PanelRect(x: inner - actionsWidth, y: 0, width: actionsWidth, height: row), columns: actions.count, rows: 1)
                    cells = actions.enumerated().map { ActionCell(action: $0.element, column: $0.offset, row: 0) }
                }
                y = row + gap
            }
            if beside {
                // Arrows (3 columns, each arrow half the height) and the
                // numpad (5 columns, 4 rows) share the width.
                let cell = (inner - gap) / 8
                let height = 4 * row
                blocks[.arrows] = Grid(rect: PanelRect(x: 0, y: y, width: 3 * cell, height: height), columns: 3, rows: 2)
                blocks[.numpad] = Grid(rect: PanelRect(x: 3 * cell + gap, y: y, width: 5 * cell, height: height), columns: NumpadKey.columns, rows: NumpadKey.rows)
                return (.numpad, .invertedT, blocks, cells)
            }
            // Narrow: the arrows in one row across, the numpad under them.
            blocks[.arrows] = Grid(rect: PanelRect(x: 0, y: y, width: inner, height: row), columns: 4, rows: 1)
            blocks[.numpad] = Grid(rect: PanelRect(x: 0, y: y + row + gap, width: inner, height: 4 * row), columns: NumpadKey.columns, rows: NumpadKey.rows)
            return (.numpad, .row, blocks, cells)
        }
    }
}
