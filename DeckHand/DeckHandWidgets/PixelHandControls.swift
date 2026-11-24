//
//  PixelHandControls.swift
//  DeckHandWidgets
//
//  Control Center controls (iOS 18+, D6): a chosen deck key, Mission
//  Control and Trackpad. Each is a `ControlWidgetButton` running the same
//  App Intent Siri and the widgets use; the intents open Pixel Hand
//  (`openAppWhenRun`), which runs them on the connected Mac.
//
//  The labels use Pixel Hand's dot glyphs, exported as custom SF Symbols
//  into this extension's asset catalog (`ControlSymbolTemplate`,
//  `Scripts/make-control-symbols.sh`; VQ-076), tinted cobalt (VQ-077).
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
            // Without a chosen key the button opens the deck, where keys
            // are added; with an empty deck the Choose sheet offers the
            // free Mac keys (VQ-078).
            let key = configuration.key ?? DeckKeyEntity(id: "", label: "Choose a key", pageTitle: "", confirm: false)
            ControlWidgetButton(action: RunDeckKeyIntent(key: key)) {
                Label(key.label, image: PixelHandControlSymbol.name(for: key))
            }
            .tint(WidgetPalette.cobalt)
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
                Label("Mission Control", image: SystemCommand.missionControl.controlSymbolName)
            }
            .tint(WidgetPalette.cobalt)
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
                Label("Trackpad", image: ControlSymbolTemplate.handName)
            }
            .tint(WidgetPalette.cobalt)
        }
        // One name in the gallery and on the control (VQ-079).
        .displayName("Trackpad")
        .description("Opens Pixel Hand on the trackpad.")
    }
}

/// The custom symbol a Deck Key control shows.
enum PixelHandControlSymbol {
    static func name(for key: DeckKeyEntity) -> String {
        if let choice = FreeMacKey.choice(id: key.id) {
            switch choice.command {
            case let .system(command): return command.controlSymbolName
            case .media: return ControlSymbolTemplate.symbolName(glyph: PixelGlyphs.play.name)
            default: break
            }
        }
        return ControlSymbolTemplate.symbolName(glyph: PixelGlyphs.deck.name)
    }
}
