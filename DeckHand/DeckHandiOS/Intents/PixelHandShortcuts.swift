//
//  PixelHandShortcuts.swift
//  DeckHandiOS
//
//  App Shortcuts (D6): the phrases Siri and Spotlight know without any
//  setup. Every phrase names the app (`.applicationName`, required). At
//  most 10 shortcuts; parameterised phrases use the enums and the deck
//  key entity, refreshed by `WidgetSnapshotWriter` through
//  `updateAppShortcutParameters()`.
//

import AppIntents

struct PixelHandShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .navy

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunDeckKeyIntent(),
            phrases: [
                "Run \(\.$key) with \(.applicationName)",
                "Press \(\.$key) in \(.applicationName)",
                "Run a deck key with \(.applicationName)",
            ],
            shortTitle: "Run Deck Key",
            systemImageName: "square.grid.3x2"
        )
        AppShortcut(
            intent: RunMacActionIntent(),
            phrases: [
                "\(\.$action) on my Mac with \(.applicationName)",
                "Show \(\.$action) with \(.applicationName)",
                "Run a Mac action with \(.applicationName)",
            ],
            shortTitle: "Mac Action",
            systemImageName: "rectangle.3.group"
        )
        AppShortcut(
            intent: LockMacIntent(),
            phrases: [
                "Lock my Mac with \(.applicationName)",
                "Lock the Mac with \(.applicationName)",
            ],
            shortTitle: "Lock Mac",
            systemImageName: "lock"
        )
        AppShortcut(
            intent: PressMediaKeyIntent(),
            phrases: [
                "\(\.$key) on my Mac with \(.applicationName)",
                "Play or pause my Mac with \(.applicationName)",
            ],
            shortTitle: "Media Key",
            systemImageName: "playpause"
        )
        AppShortcut(
            intent: TypeTextIntent(),
            phrases: [
                "Type on my Mac with \(.applicationName)",
                "Type text with \(.applicationName)",
            ],
            shortTitle: "Type on Mac",
            systemImageName: "keyboard"
        )
        AppShortcut(
            intent: TakeMacScreenshotIntent(),
            phrases: [
                "Take a Mac screenshot with \(.applicationName)",
                "Screenshot my Mac with \(.applicationName)",
            ],
            shortTitle: "Mac Screenshot",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: SetMirrorIntent(),
            phrases: [
                "\(\.$mode) the mirror in \(.applicationName)",
                "Mirror my Mac with \(.applicationName)",
            ],
            shortTitle: "Mirror",
            systemImageName: "rectangle.on.rectangle"
        )
        AppShortcut(
            intent: OpenTrackpadIntent(),
            phrases: [
                "Open the trackpad in \(.applicationName)",
                "Open \(.applicationName) trackpad",
            ],
            shortTitle: "Open Trackpad",
            systemImageName: "hand.draw"
        )
    }
}
