//
//  PixelHandEntities.swift
//  DeckHandiOS + DeckHandWidgets (compiled into both)
//
//  App Intents entities and enums (D6): deck keys and Macs, read from the
//  App Group snapshot so the Shortcuts editor, Spotlight, widgets and
//  Control Center controls can list them without the app running.
//

import AppIntents
import Foundation
import PixelHandCore

// MARK: - Deck key

struct DeckKeyEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Deck Key"
    static let defaultQuery = DeckKeyQuery()

    var id: String
    var label: String
    var pageTitle: String
    /// "Ask before running" is on for this key.
    var confirm: Bool

    init(id: String, label: String, pageTitle: String, confirm: Bool) {
        self.id = id
        self.label = label
        self.pageTitle = pageTitle
        self.confirm = confirm
    }

    init(_ key: WidgetKey) {
        self.init(id: key.id, label: key.label, pageTitle: key.pageTitle, confirm: key.confirm)
    }

    /// A free Mac key offered when the deck has none (VQ-078).
    init(_ choice: FreeMacKey.Choice) {
        self.init(id: choice.id, label: choice.label, pageTitle: FreeMacKey.groupTitle, confirm: false)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)", subtitle: "\(pageTitle)")
    }
}

struct DeckKeyQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [DeckKeyEntity.ID]) async throws -> [DeckKeyEntity] {
        let snapshot = PixelHandAppGroup.readSnapshot()
        return identifiers.compactMap { id in
            if let choice = FreeMacKey.choice(id: id) { return DeckKeyEntity(choice) }
            return snapshot.key(id: id).map(DeckKeyEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [DeckKeyEntity] {
        let snapshot = PixelHandAppGroup.readSnapshot()
        let keys = snapshot.keys(matching: string).map(DeckKeyEntity.init)
        guard snapshot.allKeys.isEmpty else { return keys }
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return FreeMacKey.choices
            .filter { needle.isEmpty || $0.label.localizedStandardContains(needle) }
            .map(DeckKeyEntity.init)
    }

    func suggestedEntities() async throws -> [DeckKeyEntity] {
        let snapshot = PixelHandAppGroup.readSnapshot()
        // The widget's keys first (the ones the user reaches for), then the rest.
        let first = snapshot.widgetKeys.map(\.id)
        let ordered = snapshot.widgetKeys + snapshot.allKeys.filter { !first.contains($0.id) }
        // An empty deck offers the free Mac keys the widget shows, rather
        // than a Choose sheet that says "No options available" (VQ-078).
        guard !ordered.isEmpty else { return FreeMacKey.choices.map(DeckKeyEntity.init) }
        return ordered.map(DeckKeyEntity.init)
    }
}

// MARK: - Mac

struct MacEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mac"
    static let defaultQuery = MacQuery()

    /// The Loom device ID (`RecentMac.id`).
    var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ mac: RecentMac) {
        self.init(id: mac.id, name: mac.name)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct MacQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [MacEntity.ID]) async throws -> [MacEntity] {
        let macs = PixelHandAppGroup.readSnapshot().macs
        return identifiers.compactMap { id in macs.first { $0.id == id }.map(MacEntity.init) }
    }

    func suggestedEntities() async throws -> [MacEntity] {
        PixelHandAppGroup.readSnapshot().macs.map(MacEntity.init)
    }
}

// MARK: - Enums

enum SystemActionOption: String, AppEnum, CaseIterable, Sendable {
    case missionControl
    case appExpose
    case showDesktop
    case launchpad
    case locateCursor
    case lockScreen

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mac Action"
    static let caseDisplayRepresentations: [SystemActionOption: DisplayRepresentation] = [
        .missionControl: DisplayRepresentation(title: "Mission Control", image: .init(systemName: "rectangle.3.group")),
        .appExpose: DisplayRepresentation(title: "App Exposé", image: .init(systemName: "rectangle.stack")),
        .showDesktop: DisplayRepresentation(title: "Show Desktop", image: .init(systemName: "menubar.dock.rectangle")),
        .launchpad: DisplayRepresentation(title: "Launchpad", image: .init(systemName: "square.grid.3x3")),
        .locateCursor: DisplayRepresentation(title: "Find the Pointer", image: .init(systemName: "cursorarrow.rays")),
        .lockScreen: DisplayRepresentation(title: "Lock Screen", image: .init(systemName: "lock")),
    ]

    var command: SystemCommand {
        switch self {
        case .missionControl: .missionControl
        case .appExpose: .appExpose
        case .showDesktop: .showDesktop
        case .launchpad: .launchpad
        case .locateCursor: .locateCursor
        case .lockScreen: .lockScreen
        }
    }
}

enum MediaKeyOption: String, AppEnum, CaseIterable, Sendable {
    case playPause
    case next
    case previous

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Media Key"
    static let caseDisplayRepresentations: [MediaKeyOption: DisplayRepresentation] = [
        .playPause: DisplayRepresentation(title: "Play/Pause", image: .init(systemName: "playpause")),
        .next: DisplayRepresentation(title: "Next Track", image: .init(systemName: "forward")),
        .previous: DisplayRepresentation(title: "Previous Track", image: .init(systemName: "backward")),
    ]

    var key: MediaKey {
        switch self {
        case .playPause: .playPause
        case .next: .next
        case .previous: .previous
        }
    }
}

enum MirrorModeOption: String, AppEnum, CaseIterable, Sendable {
    case start
    case stop
    case toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mirror"
    static let caseDisplayRepresentations: [MirrorModeOption: DisplayRepresentation] = [
        .start: "Start",
        .stop: "Stop",
        .toggle: "Toggle",
    ]

    var mode: MirrorIntentMode {
        switch self {
        case .start: .start
        case .stop: .stop
        case .toggle: .toggle
        }
    }
}
