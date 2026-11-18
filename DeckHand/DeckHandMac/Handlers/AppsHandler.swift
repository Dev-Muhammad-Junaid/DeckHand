//
//  AppsHandler.swift
//  DeckHandMac
//
//  Domain: apps and context. Launching and activating apps, app-targeted
//  shortcuts, the installed-app list, and dialog-button presses. Owned by
//  the Mac system control lane (context side: `ContextObserver`,
//  `RunningAppMonitor`, `ActiveAppMonitor`).
//

import Foundation
import LoomKit

@MainActor
final class AppsHandler: DomainHandler {
    private let injector = InputInjector.shared
    private let launcher = AppLauncher.shared

    func handle(_ message: AppsMessage, from connection: LoomConnectionHandle) async {
        switch message {
        // Slow or blocking work runs in its own task, so the message loop
        // (and with it input and liveness) never waits on it.
        case let .launchApp(bundleID):
            Task { await self.launcher.launch(bundleID: bundleID) }

        case let .appShortcut(bundleID, keys):
            // Activate the target app, wait for it to become frontmost
            // (≤600 ms), then inject — self-contained ordering inside its
            // own task.
            Task {
                await self.launcher.activateAndWait(bundleID: bundleID)
                self.injector.sendShortcut(keys: keys)
            }

        case .requestAppList:
            Task { await self.sendAppList(to: connection) }

        case let .triggerContextAction(id):
            // AXUIElementPerformAction can block up to the AX messaging
            // timeout (~6 s) on an unresponsive app — own task.
            Task { ContextObserver.shared.performAction(id: id) }

        case .appListResponse, .runningAppsUpdate, .activeAppUpdate, .uiContextUpdate:
            break // Mac → remote only
        }
    }

    private func sendAppList(to handle: LoomConnectionHandle) async {
        let apps = InstalledAppScanner.shared.installedApps()
        try? await handle.send(.apps(.appListResponse(apps: apps)))
    }
}
