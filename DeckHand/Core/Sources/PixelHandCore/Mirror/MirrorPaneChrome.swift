//
//  MirrorPaneChrome.swift
//  PixelHandCore
//
//  What the mirror's pixel chrome says (UX-006, UX-016): the status strip
//  over the picture (`STUDIO · D1/2 · DESK 2/3 · 60 FPS`), the tile's micro
//  strip (`LIVE · D1 · 60`), the S6 stats strip, the display picker's
//  `1/2` counter, the cursor badge (`ON 2` and an arrow toward that
//  display), the link badge for a `LinkKind`, and the display picker's
//  to-scale arrangement. Every string is dot-matrix safe (the 5 × 7 font's
//  characters only) and comes with a spoken label.
//  Spec: `Product/Design/06-Pixel-Identity.md` §3–§4.
//

import Foundation

/// The badge a link gets, or none. The header stays quiet on plain Wi-Fi.
public enum LinkBadgeKind: String, Sendable, CaseIterable, Equatable {
    case wired, vpn, wifi, direct

    /// Header and mirror strip: only cable and VPN, to keep chrome quiet.
    public static func header(for link: LinkKind?) -> LinkBadgeKind? {
        switch link {
        case .wired, .ethernet: .wired
        case .tunnel: .vpn
        default: nil
        }
    }

    /// Mac cards and the stats strip: every link that has a name.
    public static func card(for link: LinkKind?) -> LinkBadgeKind? {
        switch link {
        case .wired, .ethernet: .wired
        case .tunnel: .vpn
        case .wifi, .cellular: .wifi
        case .peerToPeer: .direct
        case .loopback, .other, .unknown, nil: nil
        }
    }

    /// Dot-matrix label.
    public var text: String {
        switch self {
        case .wired: "WIRED"
        case .vpn: "VPN"
        case .wifi: "WI-FI"
        case .direct: "DIRECT"
        }
    }
}

/// Which way the cursor badge's arrow points: toward the display that has
/// the pointer, in the Mac's arrangement.
public enum MirrorBadgeArrow: String, Sendable, Equatable {
    case left, right, up, down
}

/// The cursor badge: shown only while the pointer is on another display.
public struct MirrorCursorBadge: Equatable, Sendable {
    /// `ON 2`: the display's 1-based position in the Mac's list.
    public let text: String
    public let arrow: MirrorBadgeArrow
    /// The display to switch the picture to on tap.
    public let displayID: UInt32
    /// "The pointer is on HP 24, to the right. Double-tap to show it."
    public let spoken: String
}

/// A display drawn to scale in the picker sheet.
public struct MirrorArrangedDisplay: Equatable, Sendable, Identifiable {
    public var id: UInt32 { displayID }
    public let displayID: UInt32
    public let name: String
    /// 1-based position in the Mac's list.
    public let number: Int
    /// Frame in the picker's box, in points, origin top left.
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let isMirrored: Bool
    public let hasCursor: Bool
    /// Desktop dots for this display, when Spaces are known.
    public let spaceCount: Int?
    public let currentSpaceIndex: Int?
    public let fullScreenIndexes: Set<Int>
}

public enum MirrorPaneChrome {
    /// Longest Mac name in the strip, in characters.
    public static let maxNameLength = 12

    // MARK: Text helpers

    /// `name` uppercased, reduced to the dot-matrix font's characters
    /// (others dropped, runs of spaces collapsed) and cut at
    /// `maxLength` with no trailing space. "Junaid’s MacBook Pro" →
    /// "JUNAIDS MACB".
    public static func dotMatrixSafe(_ name: String, maxLength: Int = maxNameLength) -> String {
        let allowed = DotMatrixFont.characters
        var out = ""
        for character in name.uppercased() {
            if character == " " || character == "\t" {
                if !out.isEmpty, out.last != " " { out.append(" ") }
            } else if allowed.contains(character) {
                out.append(character)
            }
        }
        out = out.trimmingCharacters(in: .whitespaces)
        guard out.count > maxLength else { return out }
        // Cut at a word boundary, never mid-word (`06-Pixel-Identity.md`
        // §3); a first word longer than the limit is the only exception.
        var words: [Substring] = []
        var length = 0
        for word in out.split(separator: " ") {
            let added = words.isEmpty ? word.count : length + 1 + word.count
            guard added <= maxLength else { break }
            words.append(word)
            length = added
        }
        if words.isEmpty { return String(out.prefix(maxLength)) }
        return words.joined(separator: " ")
    }

    /// The strip's fallbacks, widest first, for `StatusStrip` to try in
    /// turn: everything; the Mac's first word in place of its full name;
    /// then without the name (it is the one segment the header already
    /// shows); then trailing items dropped one at a time. Each step drops
    /// whole segments, so the strip truncates at a separator.
    public static func stripCandidates(_ items: [String]) -> [[String]] {
        guard let name = items.first else { return [] }
        var candidates: [[String]] = [items]
        let rest = Array(items.dropFirst())
        if let first = name.split(separator: " ").first, first.count < name.count {
            candidates.append([String(first)] + rest)
        }
        for count in stride(from: rest.count, through: 1, by: -1) {
            candidates.append(Array(rest.prefix(count)))
        }
        return candidates
    }

    /// Frames per second for the strip: whole numbers, the remote's
    /// displayed rate first (what the user sees), then the Mac's sent rate.
    public static func fps(host: MirrorHostStats?, client: MirrorClientStats?) -> Int? {
        let value = client?.displayedFPS ?? host?.sentFPS
        guard let value, value.isFinite, value >= 0 else { return nil }
        return Int(value.rounded())
    }

    // MARK: Display counter

    /// The display picker button's counter, `1/2`; `nil` with one display
    /// or while a window is mirrored (`WIN`).
    public static func displayCounter(displays: [DisplayInfo], mirroredDisplayID: UInt32?, mirroringWindow: Bool) -> String? {
        if mirroringWindow { return "WIN" }
        guard displays.count > 1 else { return nil }
        let index = displayIndex(displays: displays, mirroredDisplayID: mirroredDisplayID) ?? 0
        return "\(index + 1)/\(displays.count)"
    }

    /// Position of the mirrored display; `nil` (not confirmed yet) means
    /// the main display, which the Mac mirrors by default.
    static func displayIndex(displays: [DisplayInfo], mirroredDisplayID: UInt32?) -> Int? {
        if let mirroredDisplayID, let index = displays.firstIndex(where: { $0.displayID == mirroredDisplayID }) {
            return index
        }
        return displays.firstIndex(where: \.isMain) ?? (displays.isEmpty ? nil : 0)
    }

    // MARK: Status strips

    /// The strip over the docked picture: `STUDIO · D1/2 · DESK 2/3 · 60 FPS`.
    /// Items are in drop order (the strip drops trailing items to fit), so
    /// the Mac's name always stays. A window mirror shows `WINDOW` in place
    /// of the display and desktop.
    public static func paneStrip(
        macName: String,
        displays: [DisplayInfo],
        mirroredDisplayID: UInt32?,
        windowTitle: String?,
        mirroringWindow: Bool,
        spaces: MirrorSpaceStrip,
        host: MirrorHostStats?,
        client: MirrorClientStats?,
        hasFrame: Bool = true
    ) -> (items: [String], spoken: String) {
        var items = [dotMatrixSafe(macName).isEmpty ? "MAC" : dotMatrixSafe(macName)]
        var spoken = [macName]
        // Before the first frame: no fps (a lit "0 FPS" reads as live) but
        // CONNECTING, drawn dim by the caller (VQ-062).
        guard hasFrame else {
            items.append("CONNECTING")
            spoken.append("connecting")
            return (items, spoken.joined(separator: ", "))
        }
        if mirroringWindow {
            items.append("WINDOW")
            spoken.append(windowTitle.map { "window \($0)" } ?? "a window")
        } else {
            if displays.count > 1, let index = displayIndex(displays: displays, mirroredDisplayID: mirroredDisplayID) {
                items.append("D\(index + 1)/\(displays.count)")
                spoken.append("display \(index + 1) of \(displays.count)")
            }
            if let current = spaces.dots.firstIndex(where: \.isCurrent), spaces.dots.count > 1 {
                items.append("DESK \(current + 1)/\(spaces.dots.count)")
                spoken.append("desktop \(current + 1) of \(spaces.dots.count)")
            }
        }
        if let fps = fps(host: host, client: client) {
            items.append("\(fps) FPS")
            spoken.append("\(fps) frames per second")
        }
        return (items, spoken.joined(separator: ", "))
    }

    /// The floating tile's micro strip: `LIVE · D1 · 60`.
    public static func tileStrip(
        displays: [DisplayInfo],
        mirroredDisplayID: UInt32?,
        mirroringWindow: Bool,
        host: MirrorHostStats?,
        client: MirrorClientStats?
    ) -> (items: [String], spoken: String) {
        var items = ["LIVE"]
        var spoken = ["Live"]
        if mirroringWindow {
            items.append("WIN")
            spoken.append("window")
        } else if displays.count > 1, let index = displayIndex(displays: displays, mirroredDisplayID: mirroredDisplayID) {
            items.append("D\(index + 1)")
            spoken.append("display \(index + 1)")
        }
        if let fps = fps(host: host, client: client) {
            items.append("\(fps)")
            spoken.append("\(fps) frames per second")
        }
        return (items, spoken.joined(separator: ", "))
    }

    /// S6 as a strip: `60 FPS · 7 MS · HEVC 1920 · 18 MB/S · 2 DROP · WIRED`.
    /// `MS` is the remote's decode time; `MB/S` is megabits.
    public static func statsStrip(host: MirrorHostStats?, client: MirrorClientStats?, link: LinkKind?) -> [String] {
        var items: [String] = []
        if let fps = fps(host: host, client: client) { items.append("\(fps) FPS") }
        if let client, client.decodeMilliseconds.isFinite {
            items.append("\(Int(client.decodeMilliseconds.rounded())) MS")
        }
        if let host {
            items.append("\(host.codec.rawValue.uppercased()) \(host.width)")
            if host.kilobitsPerSecond.isFinite {
                let megabits = host.kilobitsPerSecond / 1_000
                items.append(megabits >= 10 ? "\(Int(megabits.rounded())) MB/S" : "\(MirrorStatsLine.number(megabits)) MB/S")
            }
            let dropped = host.droppedFrames + (client?.droppedFrames ?? 0)
            if dropped > 0 { items.append("\(dropped) DROP") }
        }
        if let badge = LinkBadgeKind.card(for: link) { items.append(badge.text) }
        return items.isEmpty ? ["WAITING"] : items
    }

    // MARK: Cursor badge

    /// The badge for `chrome.cursorElsewhere`, with the arrow pointing
    /// from the mirrored display toward the cursor's display in the Mac's
    /// arrangement (from `layout`); `.right` when the arrangement isn't
    /// known.
    public static func cursorBadge(
        chrome: MirrorDisplayChrome,
        displays: [DisplayInfo],
        mirroredDisplayID: UInt32?,
        layout: DisplayLayout?
    ) -> MirrorCursorBadge? {
        guard let target = chrome.cursorElsewhere,
              let index = displays.firstIndex(where: { $0.displayID == target.displayID }) else { return nil }
        let arrow = arrowDirection(from: mirroredDisplayID ?? displays.first(where: \.isMain)?.displayID, to: target.displayID, layout: layout)
        let side: String = switch arrow {
        case .left: "to the left"
        case .right: "to the right"
        case .up: "above"
        case .down: "below"
        }
        return MirrorCursorBadge(
            text: "ON \(index + 1)",
            arrow: arrow,
            displayID: target.displayID,
            spoken: "The pointer is on \(target.name), \(side). Double-tap to show it."
        )
    }

    /// The dominant axis between the two displays' centres.
    public static func arrowDirection(from source: UInt32?, to target: UInt32, layout: DisplayLayout?) -> MirrorBadgeArrow {
        guard let layout, let source, let a = layout.display(source)?.bounds, let b = layout.display(target)?.bounds else {
            return .right
        }
        let dx = (b.x + b.width / 2) - (a.x + a.width / 2)
        let dy = (b.y + b.height / 2) - (a.y + a.height / 2)
        if abs(dx) >= abs(dy) { return dx < 0 ? .left : .right }
        return dy < 0 ? .up : .down
    }

    // MARK: Display picker arrangement

    /// The displays drawn to scale in the Mac's arrangement, fitted and
    /// centred in a `boxWidth` × `boxHeight` box. Falls back to a row,
    /// side by side at their pixel sizes, when the Mac hasn't sent its
    /// layout. Every display keeps at least `minSide` points on its short
    /// side so it stays tappable; `gap` is drawn between touching edges.
    public static func arrangement(
        displays: [DisplayInfo],
        layout: DisplayLayout?,
        mirroredDisplayID: UInt32?,
        cursorDisplayID: UInt32?,
        boxWidth: Double,
        boxHeight: Double,
        gap: Double = 8
    ) -> [MirrorArrangedDisplay] {
        guard !displays.isEmpty, boxWidth > 0, boxHeight > 0 else { return [] }
        struct Raw { let info: DisplayInfo; var x, y, w, h: Double; let spaces: DisplaySpaces? }

        var raws: [Raw] = []
        var cursorX = 0.0
        for info in displays {
            let spaces = layout?.display(info.displayID)
            if let bounds = spaces?.bounds, bounds.width > 0, bounds.height > 0 {
                raws.append(Raw(info: info, x: bounds.x, y: bounds.y, w: bounds.width, h: bounds.height, spaces: spaces))
            } else {
                raws.append(Raw(info: info, x: cursorX, y: 0, w: Double(max(info.width, 1)), h: Double(max(info.height, 1)), spaces: spaces))
            }
            cursorX = (raws.last.map { $0.x + $0.w } ?? 0) + 1
        }
        // Mixed sources (some with bounds, some without) can overlap; a
        // layout without bounds for everyone is laid out as a row instead.
        if raws.contains(where: { $0.spaces == nil }) && raws.contains(where: { $0.spaces != nil }) {
            var x = 0.0
            for i in raws.indices {
                raws[i].x = x; raws[i].y = 0
                raws[i].w = Double(max(raws[i].info.width, 1)); raws[i].h = Double(max(raws[i].info.height, 1))
                x += raws[i].w + 1
            }
        }

        let minX = raws.map(\.x).min() ?? 0
        let minY = raws.map(\.y).min() ?? 0
        let maxX = raws.map { $0.x + $0.w }.max() ?? 1
        let maxY = raws.map { $0.y + $0.h }.max() ?? 1
        let spanW = max(maxX - minX, 1)
        let spanH = max(maxY - minY, 1)
        let scale = min(boxWidth / spanW, boxHeight / spanH)
        let offsetX = (boxWidth - spanW * scale) / 2
        let offsetY = (boxHeight - spanH * scale) / 2
        let mirrored = mirroredDisplayID ?? displays.first(where: \.isMain)?.displayID

        return raws.enumerated().map { index, raw in
            let inset = displays.count > 1 ? gap / 2 : 0
            let width = max(raw.w * scale - inset * 2, 1)
            let height = max(raw.h * scale - inset * 2, 1)
            let spaces = raw.spaces
            return MirrorArrangedDisplay(
                displayID: raw.info.displayID,
                name: raw.info.name,
                number: index + 1,
                x: ((raw.x - minX) * scale + offsetX + inset).rounded(),
                y: ((raw.y - minY) * scale + offsetY + inset).rounded(),
                width: width.rounded(),
                height: height.rounded(),
                isMirrored: raw.info.displayID == mirrored,
                hasCursor: raw.info.displayID == cursorDisplayID,
                spaceCount: (layout?.spacesKnown ?? false) ? spaces?.spaceCount : nil,
                currentSpaceIndex: (layout?.spacesKnown ?? false) ? spaces?.currentSpaceIndex : nil,
                fullScreenIndexes: Set(spaces?.fullScreenSpaces.map(\.index) ?? [])
            )
        }
    }

    /// "Display 1 · 3 desktops" under each display in the picker.
    public static func displaySubtitle(number: Int, spaceCount: Int?) -> String {
        guard let spaceCount else { return "Display \(number)" }
        return "Display \(number) · \(spaceCount) \(spaceCount == 1 ? "desktop" : "desktops")"
    }
}
