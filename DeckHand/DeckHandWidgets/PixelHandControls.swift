//
//  PixelHandControls.swift
//  DeckHandWidgets
//
//  Control Center controls (iOS 18+, D6): a chosen deck key, Mission
//  Control and "Open Trackpad". Each is a `ControlWidgetButton` running the
//  same App Intent Siri and the widgets use; the intents open Pixel Hand
//  (`openAppWhenRun`), which runs them on the connected Mac.
//

import AppIntents
import PixelHandCore
import SwiftUI
import WidgetKit

/// Which key the "Deck Key" control runs.
@available(iOS 18.0, *)
struct DeckKeyControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Deck Key"

    @Parameter(title: "Key")
    var key: DeckKeyEntity?

    init() {}

    func perform() async throws -> some IntentResult { .result() }
}

@available(iOS 18.0, *)
struct DeckKeyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: PixelHandAppGroup.WidgetKind.keyControl,
            intent: DeckKeyControlConfiguration.self
        ) { configuration in
            // Without a chosen key the button explains itself when run
            // ("That deck key isn't in your deck anymore") rather than
            // doing something the user didn't pick.
            let key = configuration.key ?? DeckKeyEntity(id: "", label: "Choose a Key", pageTitle: "", confirm: false)
            ControlWidgetButton(action: RunDeckKeyIntent(key: key)) {
                Label(key.label, systemImage: "square.grid.3x2")
            }
        }
        .displayName("Deck Key")
        .description("Runs a Pixel Hand deck key on your Mac.")
        .promptsForUserConfiguration()
    }
}

@available(iOS 18.0, *)
struct MissionControlControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PixelHandAppGroup.WidgetKind.missionControl) {
            ControlWidgetButton(action: RunMacActionIntent(action: .missionControl)) {
                Label("Mission Control", systemImage: SystemCommand.missionControl.symbolName)
            }
        }
        .displayName("Mission Control")
        .description("Shows Mission Control on your Mac.")
    }
}

@available(iOS 18.0, *)
struct TrackpadControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PixelHandAppGroup.WidgetKind.trackpadControl) {
            ControlWidgetButton(action: OpenTrackpadIntent()) {
                Label("Trackpad", systemImage: "hand.draw")
            }
        }
        .displayName("Open Trackpad")
        .description("Opens Pixel Hand on the trackpad.")
    }
}
