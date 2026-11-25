//
//  MirrorTileKeepOutRegistry.swift
//  PixelHandCore
//
//  The areas each surface reserves from the floating screen tile, keyed by
//  owner (one per Mac session) and part (pad, deck header…).
//
//  Build 23 (VQ-083): when the deck went into edit mode, the edit header
//  reported its frame (appear) before the normal header withdrew its own
//  (disappear, after the transition). The late withdrawal wiped the header
//  just reported, so the tile homed to the canvas's top-trailing corner,
//  over Done. Each report now carries its reporter's token, and a
//  withdrawal only clears the part when the same reporter set it last.
//

import Foundation

public struct MirrorTileKeepOutRegistry<Owner: Hashable, Part: Hashable, Frame: Equatable>: Equatable {
    private struct Entry: Equatable {
        var frame: Frame
        var reporter: UUID
    }

    private var entries: [Owner: [Part: Entry]] = [:]

    public init() {}

    /// Records `frame` for `part`, reported by `reporter`. Returns whether
    /// anything changed.
    @discardableResult
    public mutating func report(_ frame: Frame, for part: Part, owner: Owner, reporter: UUID) -> Bool {
        let entry = Entry(frame: frame, reporter: reporter)
        guard entries[owner]?[part] != entry else { return false }
        entries[owner, default: [:]][part] = entry
        return true
    }

    /// Clears `part` only if `reporter` made the last report for it: a view
    /// leaving late can't erase the frame its replacement already reported.
    @discardableResult
    public mutating func withdraw(_ part: Part, owner: Owner, reporter: UUID) -> Bool {
        guard let entry = entries[owner]?[part], entry.reporter == reporter else { return false }
        entries[owner]?[part] = nil
        if entries[owner]?.isEmpty == true { entries[owner] = nil }
        return true
    }

    /// The frame currently reported for `part`.
    public func frame(_ part: Part, owner: Owner) -> Frame? {
        entries[owner]?[part]?.frame
    }

    /// Whether `owner` has reported anything.
    public func hasParts(owner: Owner) -> Bool {
        entries[owner] != nil
    }
}
