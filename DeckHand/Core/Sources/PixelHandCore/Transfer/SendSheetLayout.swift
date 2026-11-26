//
//  SendSheetLayout.swift
//  PixelHandCore – Transfer
//
//  The Send / Inbox sheet's sizes (owner testing, build 26, OT-9). The
//  sheet is as tall as what it holds: the header, the source chips, the
//  field, the tray, the "Send to" cards, the beam and the waiting list,
//  never a fixed medium detent with half of it empty. The app measures its
//  content and asks `sheetHeight` for the detent; before the first
//  measurement it uses `estimatedSendHeight` / `estimatedInboxHeight`, so
//  the sheet opens near its final size instead of jumping.
//
//  Every size is on the 4 pt grid and from `07-Polish-Spec.md` §2–§4.
//

import Foundation

public enum SendSheetLayout {
    // MARK: Component sizes (pt)

    /// The header: Send | Inbox switch and Done, 44 pt with 8 above and
    /// 8 below.
    public static let headerHeight = 60.0
    /// Source chips (Photos, Files, Clipboard): one size, 44 pt.
    public static let chipHeight = 44.0
    /// The source chips in their row.
    public static let chipCount = 3
    public static let chipGap = 8.0

    /// One source chip's width in a row `rowWidth` wide: the row less its
    /// gaps, split evenly and rounded down to whole points, so the three
    /// chips are exactly one width (build 27 bug 3: a stack splitting the
    /// row measured them 174.5, 175 and 173.5 pt). At least 44.
    public static func chipWidth(rowWidth: Double, count: Int = chipCount, gap: Double = chipGap) -> Double {
        guard count > 0, rowWidth.isFinite, rowWidth > 0 else { return chipHeight }
        let share = (rowWidth - gap * Double(count - 1)) / Double(count)
        return max(chipHeight, share.rounded(.down))
    }
    /// The text-or-link field with its Add button.
    public static let fieldHeight = 52.0
    /// A full device card: 44 pt tile, 10 pt inset (card radius 24 →
    /// tile radius 14).
    public static let cardHeight = 64.0
    /// An offline Mac: small and muted, one 44 pt row.
    public static let offlineHeight = 44.0
    /// A staged item in the tray.
    public static let trayRowHeight = 52.0
    /// A waiting item.
    public static let waitingRowHeight = 44.0
    /// The beam tile, its caption and the Switch / Cancel buttons.
    public static let beamHeight = 148.0
    /// A section label ("Send to", "Waiting", the tray hint).
    public static let labelHeight = 20.0
    /// The dot beam shown while photos load.
    public static let loadingHeight = 8.0
    /// An Inbox row.
    public static let inboxRowHeight = 56.0
    /// The Inbox empty state (glyph, title, one sentence).
    public static let inboxEmptyHeight = 280.0

    /// Between sections.
    public static let sectionGap = 16.0
    /// Between a label and what it names, and between rows.
    public static let rowGap = 8.0
    /// Between cards.
    public static let cardGap = 12.0
    /// Padding under the last section (above the home indicator's inset,
    /// which the system adds).
    public static let bottomPadding = 16.0

    /// A card never gets narrower than this; below it the grid drops a
    /// column. Two columns at iPhone width (375 − 2 × 16 → 165 pt cards,
    /// 402 → 179 pt).
    public static let minimumCardWidth = 160.0
    /// At most three columns, even in a wide window.
    public static let maximumColumns = 3

    /// The shortest sheet (header, sources, field, a line).
    public static let minimumHeight = 240.0
    /// Room left above the sheet so it reads as a sheet, not a page.
    public static let topClearance = 48.0

    // MARK: Grid

    /// Card columns for a content width (the sheet's width less its
    /// margins).
    public static func columns(width: Double) -> Int {
        guard width > 0 else { return 1 }
        let fit = Int(((width + cardGap) / (minimumCardWidth + cardGap)).rounded(.down))
        return max(1, min(maximumColumns, fit))
    }

    /// Rows needed for `count` items in `columns`.
    public static func rows(count: Int, columns: Int) -> Int {
        guard count > 0 else { return 0 }
        let columns = max(1, columns)
        return (count + columns - 1) / columns
    }

    /// Height of `rows` rows of `rowHeight` with `gap` between them.
    static func stack(rows: Int, rowHeight: Double, gap: Double) -> Double {
        rows > 0 ? Double(rows) * rowHeight + Double(rows - 1) * gap : 0
    }

    // MARK: Content

    /// What the Send tab holds right now.
    public struct SendContent: Equatable, Sendable {
        public var stagedCount: Int
        public var cardCount: Int
        public var offlineCount: Int
        public var waitingCount: Int
        public var showsBeam: Bool
        public var isLoadingPhotos: Bool

        public init(
            stagedCount: Int = 0,
            cardCount: Int = 0,
            offlineCount: Int = 0,
            waitingCount: Int = 0,
            showsBeam: Bool = false,
            isLoadingPhotos: Bool = false
        ) {
            self.stagedCount = stagedCount
            self.cardCount = cardCount
            self.offlineCount = offlineCount
            self.waitingCount = waitingCount
            self.showsBeam = showsBeam
            self.isLoadingPhotos = isLoadingPhotos
        }
    }

    /// The Send tab's content height (under the header) for a content
    /// width, from the component sizes above. The app replaces it with the
    /// measured height once laid out.
    public static func estimatedSendHeight(_ content: SendContent, width: Double) -> Double {
        let columns = columns(width: width)
        var sections: [Double] = []
        sections.append(chipHeight)
        var field = fieldHeight
        if content.isLoadingPhotos { field += rowGap + loadingHeight }
        sections.append(field)
        if content.stagedCount > 0 {
            sections.append(labelHeight + rowGap + stack(rows: content.stagedCount, rowHeight: trayRowHeight, gap: rowGap))
        }
        var targets = labelHeight + rowGap
        if content.cardCount == 0 && content.offlineCount == 0 {
            targets += labelHeight // "Pair a Mac to send to it."
        } else {
            targets += stack(rows: rows(count: content.cardCount, columns: columns), rowHeight: cardHeight, gap: cardGap)
            if content.offlineCount > 0 {
                if content.cardCount > 0 { targets += cardGap }
                targets += stack(rows: rows(count: content.offlineCount, columns: columns), rowHeight: offlineHeight, gap: rowGap)
            }
        }
        sections.append(targets)
        if content.showsBeam { sections.append(beamHeight) }
        if content.waitingCount > 0 {
            sections.append(labelHeight + rowGap + stack(rows: content.waitingCount, rowHeight: waitingRowHeight, gap: rowGap))
        }
        let body = sections.reduce(0, +) + Double(sections.count - 1) * sectionGap
        return body + bottomPadding
    }

    /// The Inbox tab's content height: arriving items, then received ones,
    /// or the empty state.
    public static func estimatedInboxHeight(arriving: Int, items: Int) -> Double {
        var height = 0.0
        if arriving > 0 {
            height += labelHeight + rowGap + stack(rows: arriving, rowHeight: inboxRowHeight, gap: rowGap) + sectionGap
        }
        if items == 0 {
            height += inboxEmptyHeight
        } else {
            // The rows, then the "Also in Files" footer line.
            height += stack(rows: items, rowHeight: inboxRowHeight, gap: rowGap) + rowGap + labelHeight
        }
        return height + bottomPadding
    }

    // MARK: Sheet

    /// The tallest the sheet may be in a container (window) this tall.
    public static func maximumHeight(container: Double) -> Double {
        max(minimumHeight, (container - topClearance).rounded(.down))
    }

    /// The sheet's height: header + content, at least `minimumHeight`, at
    /// most `maximumHeight`, rounded up to the 4 pt grid.
    public static func sheetHeight(content: Double, container: Double) -> Double {
        let wanted = headerHeight + max(0, content)
        let clamped = min(max(wanted, minimumHeight), maximumHeight(container: container))
        return onGrid(clamped)
    }

    /// Whether the content is taller than the sheet may be, so it scrolls
    /// and the sheet also offers the large detent.
    public static func overflows(content: Double, container: Double) -> Bool {
        headerHeight + max(0, content) > maximumHeight(container: container)
    }

    /// A measured height worth resizing the sheet for: a change of at least
    /// one grid step, so sub-point layout noise never animates the sheet.
    public static func isNewHeight(_ new: Double, comparedWith old: Double?) -> Bool {
        guard let old else { return true }
        return abs(new - old) >= 4
    }

    /// Rounds up to the 4 pt grid.
    public static func onGrid(_ value: Double) -> Double {
        (value / 4).rounded(.up) * 4
    }
}
