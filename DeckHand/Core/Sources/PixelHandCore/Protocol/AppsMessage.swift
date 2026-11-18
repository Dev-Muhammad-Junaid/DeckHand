//
//  AppsMessage.swift
//  PixelHandCore
//
//  Domain: apps and context. Installed and running apps, the frontmost app,
//  and what is interactable in it (dialog buttons, text fields). Both ways.
//  Owned by the Mac context side (`AppsHandler`, `ContextObserver`,
//  `RunningAppMonitor`) and the remote's app grid.
//

import Foundation

public enum AppsMessage: Codable, Sendable, Equatable {
    // MARK: Remote → Mac

    /// Launch or activate `bundleID`.
    case launchApp(bundleID: String)
    /// Activate `bundleID`, wait for it to become frontmost, then post
    /// `keys`. Kept separate from `keyboardShortcut` so the chord always
    /// lands in the intended app.
    case appShortcut(bundleID: String, keys: [String])
    /// Ask for every installed app. Reply: `appListResponse`.
    case requestAppList
    /// Press a dialog button from the latest `uiContextUpdate`. `id` is the
    /// opaque `DialogButton.id`; a stale id is ignored by the Mac.
    case triggerContextAction(id: String)

    // MARK: Mac → remote

    case appListResponse(apps: [InstalledAppInfo])
    /// Running user-facing apps, most recently activated first (⌘Tab
    /// order). Sent on connect and on every launch, quit and activation.
    case runningAppsUpdate(bundleIDs: [String])
    /// The frontmost app changed.
    case activeAppUpdate(name: String, bundleID: String?)
    /// What is interactable in the frontmost app, read through
    /// Accessibility. `.none` means the remote shows its per-app chips.
    case uiContextUpdate(snapshot: UIContextSnapshot)
}
