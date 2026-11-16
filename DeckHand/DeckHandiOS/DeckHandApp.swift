//
//  DeckHandApp.swift
//  DeckHandiOS
//

import LoomKit
import SwiftUI
import UIKit

@main
struct DeckHandApp: App {
    /// `nil` when the container could not be built. The app then shows a
    /// startup-failure screen instead of crashing at launch, mirroring how
    /// `MacDaemon` surfaces the same failure in the menu bar.
    let loomContainer: LoomContainer?
    let startupError: String?
    @StateObject private var settings = DeckHandSettings()

    init() {
        // First, so a crash anywhere in launch is reported (if allowed).
        DeckHandDiagnostics.startIfEnabled()
        do {
            loomContainer = try LoomContainer(
                for: LoomContainerConfiguration(
                    serviceType: "_deckhand._tcp",
                    serviceName: Self.deviceName(),
                    deviceIDSuiteName: "DeckHandLoomStore",
                    // Same-iCloud awareness: this device publishes its identity
                    // to the user's private CloudKit DB; Macs on the same
                    // account surface with `.cloudKitOwn` → "My Mac" badge,
                    // priority sort, and host-side auto-allow (DeckHandCloud).
                    cloudKit: DeckHandCloud.cloudKitConfiguration,
                    remoteSignaling: DeckHandCloud.remoteSignalingConfiguration,
                    // Manual lifecycle only — see MacHostApp for rationale.
                    retryPolicy: .disabled
                )
            )
            startupError = nil
        } catch {
            DeckHandLog.app.fault("LoomContainer init failed: \(error.localizedDescription, privacy: .public)")
            DeckHandDiagnostics.capture(error)
            loomContainer = nil
            startupError = error.localizedDescription
        }
    }

    /// The name Macs see in their approval prompt. Loom rejects an empty
    /// name, so fall back to the device model rather than fail to start.
    @MainActor
    private static func deviceName() -> String {
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? UIDevice.current.model : name
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let loomContainer {
                    ContentRootView()
                        .loomContainer(loomContainer, autostart: false)
                } else {
                    StartupFailureView(message: startupError)
                }
            }
            .environmentObject(settings)
            .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}

/// Shown in place of the remote when the Loom container could not be built.
/// There is nothing to retry in-process, so it says what to do instead.
private struct StartupFailureView: View {
    let message: String?

    var body: some View {
        DeckHandEmptyState(
            glyph: PixelArt.cross,
            title: "Deck Hand couldn't start",
            message: [
                message,
                "Quit Deck Hand from the app switcher and open it again. If this keeps happening, reinstall the app.",
            ]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
