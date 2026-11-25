//
//  RightColumn.swift
//  PixelHandCore
//
//  The right column beside the canvas (the deck and the front app's
//  shortcuts) can collapse to a slim edge handle, and it switches between
//  the deck and Ask (OR-06, owner review of build 18). These are the pure
//  rules: which arrangements have the column, which can collapse it, where
//  Ask (⌘K) opens, and the remembered collapsed state per arrangement.
//
//    rail        iPhone landscape: the column holds the header, so it
//                never collapses; it switches Deck | Ask.
//    sideBySide  iPad portrait: the column beside the pad (Split and
//                Pointer presets; Screen has none). Collapses; switches.
//    columns     iPad landscape: the trailing column. Collapses; switches.
//    single, stacked, book, laptop: no right column. Ask stays a sheet.
//

import Foundation

/// What the right column shows.
public enum RightColumnMode: String, Sendable, Hashable, CaseIterable, Codable {
    case deck
    case ask

    public var title: String {
        switch self {
        case .deck: "Deck"
        case .ask: "Ask"
        }
    }
}

/// One arrangement the person can be in: the canvas form plus its layout
/// preset where the form has presets. The right column's collapsed state is
/// remembered per arrangement.
public struct ArrangementPreset: Sendable, Hashable {
    public let form: CanvasPlan.Form
    /// The preset, on forms that use presets (sideBySide, columns); `nil`
    /// elsewhere, so a stray preset never splits a form's memory.
    public let preset: LayoutPreset?

    public init(form: CanvasPlan.Form, preset: LayoutPreset?) {
        self.form = form
        switch form {
        case .sideBySide, .columns: self.preset = preset ?? .split
        default: self.preset = nil
        }
    }

    public init(plan: CanvasPlan, preset: LayoutPreset?) {
        self.init(form: plan.form, preset: plan.usesPresets ? preset : nil)
    }

    /// The storage key: "columns|split", "rail".
    public var key: String {
        guard let preset else { return form.rawValue }
        return "\(form.rawValue)|\(preset.rawValue)"
    }
}

/// Where Ask opens when the person taps Ask or presses ⌘K.
public enum AskRoute: String, Sendable, Hashable {
    /// In place, in the right column (it expands if collapsed).
    case column
    /// In its sheet.
    case sheet
}

/// The right column for one arrangement.
public struct RightColumnPlan: Sendable, Hashable {
    /// The collapsed column's edge handle (visual width; its hit area is
    /// wider).
    public static let handleWidth: Double = 20
    /// The handle's touch target, centred on it.
    public static let handleHitWidth: Double = 44

    public let arrangement: ArrangementPreset
    /// The column's full width in this arrangement; 0 when there is none.
    public let expandedWidth: Double
    /// Whether the arrangement has a right column at all.
    public let exists: Bool
    /// Whether the column offers its collapse button.
    public let canCollapse: Bool
    /// Whether it is collapsed to the edge handle now.
    public let isCollapsed: Bool

    /// `collapsed` is the remembered state; it is ignored where the column
    /// can't collapse.
    public init(plan: CanvasPlan, preset: LayoutPreset?, collapsed: Bool) {
        arrangement = ArrangementPreset(plan: plan, preset: preset)
        switch plan.form {
        case .rail:
            exists = plan.hasDeckColumn
            canCollapse = false
        case .sideBySide:
            exists = plan.hasDeckColumn && arrangement.preset != .screen
            canCollapse = exists
        case .columns:
            exists = plan.hasDeckColumn
            canCollapse = exists
        case .single, .stacked, .book, .laptop:
            exists = false
            canCollapse = false
        }
        expandedWidth = exists ? plan.deckColumnWidth : 0
        isCollapsed = canCollapse && collapsed
    }

    /// The width the column takes now: full, the handle, or nothing.
    public var width: Double {
        guard exists else { return 0 }
        return isCollapsed ? Self.handleWidth : expandedWidth
    }

    /// Whether the column shows its Deck | Ask switch.
    public var offersAsk: Bool { exists }

    /// Ask runs in the column wherever there is one, the sheet elsewhere.
    public var askRoute: AskRoute { exists ? .column : .sheet }
}

/// The collapsed state per arrangement, as one small JSON string for
/// `@AppStorage`. Only collapsed arrangements are stored; damaged data
/// reads as "nothing collapsed".
public struct RightColumnMemory: Sendable, Hashable {
    public private(set) var collapsed: Set<String>

    /// Cap so the stored string stays small (7 forms × 3 presets is 21).
    public static let maximumEntries = 32

    public init(collapsed: Set<String> = []) {
        self.collapsed = collapsed
    }

    public init(json: String) {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String].self, from: data)
        else {
            self.collapsed = []
            return
        }
        self.collapsed = Set(raw.prefix(Self.maximumEntries))
    }

    public var json: String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(collapsed.sorted()), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    public func isCollapsed(_ arrangement: ArrangementPreset) -> Bool {
        collapsed.contains(arrangement.key)
    }

    public mutating func set(_ isCollapsed: Bool, for arrangement: ArrangementPreset) {
        if isCollapsed {
            guard collapsed.count < Self.maximumEntries || collapsed.contains(arrangement.key) else { return }
            collapsed.insert(arrangement.key)
        } else {
            collapsed.remove(arrangement.key)
        }
    }

    /// Opening Ask in the column expands it in that arrangement.
    public mutating func expandForAsk(_ plan: RightColumnPlan) {
        set(false, for: plan.arrangement)
    }
}
