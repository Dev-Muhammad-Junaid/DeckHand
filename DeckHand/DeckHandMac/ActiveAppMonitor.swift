//
//  ActiveAppMonitor.swift
//  DeckHandMac
//
//  Tells remotes which app is frontmost. Withheld while the Mac is locked
//  (`LockPolicy.withholdsContext`) and sent again at the unlock.
//
//  `addConnection` / `removeConnection` are also where the Mac system
//  control lane's other monitors learn about connections
//  (`MacSystemSession`), so `ControlReceiver` registers each connection once.

import AppKit
import Combine
import Foundation
import LoomKit

@MainActor
final class ActiveAppMonitor {
    static let shared = ActiveAppMonitor()

    private var cancellables = Set<AnyCancellable>()
    private var activeConnections: [UUID: LoomConnectionHandle] = [:]

    private init() {
        // Observe app activations
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   let name = app.localizedName {
                    Task {
                        await self?.broadcastActiveApp(name: name, bundleID: app.bundleIdentifier)
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Register a new connection to receive active app updates.
    /// Also sends the current active app immediately upon connection.
    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {
        // Lock state, display wake and the Spaces snapshot first.
        MacSystemSession.connectionAdded(handle, id: id)
        activeConnections[id] = handle

        // Send current frontmost app immediately
        if !isWithheld,
           let currentApp = NSWorkspace.shared.frontmostApplication,
           let name = currentApp.localizedName {
            Task {
                try? await handle.send(.apps(.activeAppUpdate(name: name, bundleID: currentApp.bundleIdentifier)))
            }
        }
    }

    func removeConnection(id: UUID) {
        activeConnections.removeValue(forKey: id)
        MacSystemSession.connectionRemoved(id: id)
    }

    /// The Mac locked or unlocked: at the unlock, send the frontmost app.
    func contextVisibilityChanged() {
        guard !isWithheld,
              let currentApp = NSWorkspace.shared.frontmostApplication,
              let name = currentApp.localizedName else { return }
        Task { await broadcastActiveApp(name: name, bundleID: currentApp.bundleIdentifier) }
    }

    private var isWithheld: Bool {
        LockPolicy.withholdsContext(MacLockMonitor.shared.state)
    }

    private func broadcastActiveApp(name: String, bundleID: String?) async {
        guard !isWithheld else { return }
        let msg = ControlMessage.apps(.activeAppUpdate(name: name, bundleID: bundleID))
        for handle in activeConnections.values {
            try? await handle.send(msg)
        }
    }
}
