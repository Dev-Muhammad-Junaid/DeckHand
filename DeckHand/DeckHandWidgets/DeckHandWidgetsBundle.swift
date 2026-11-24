//
//  DeckHandWidgetsBundle.swift
//  DeckHandWidgets
//
//  The widget extension's entry point (D6). Shares
//  `DeckHandiOS/Intents/Shared/` with the app (the intents, entities and
//  App Group store) and reads only the App Group snapshot.
//

import SwiftUI
import WidgetKit

@main
struct DeckHandWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DeckWidget()
        DeckAccessoryWidget()
        if #available(iOS 18.0, *) {
            DeckKeyControl()
            MissionControlControl()
            TrackpadControl()
        }
    }
}
