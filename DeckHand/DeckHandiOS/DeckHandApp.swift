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
                    serviceType: "_pixelhand._tcp",
                    serviceName: Self.deviceName(),
                    deviceIDSuiteName: "DeckHandLoomStore",
                    // Same-iCloud awareness: this device publishes its identity
                    // to the user's private CloudKit DB; Macs on the same
                    // account surface with `.cloudKitOwn` → "My Mac" badge,
                    // priority sort, and host-side auto-allow (DeckHandCloud).
                    cloudKit: DeckHandCloud.cloudKitConfiguration,
                    // S15: probe the saved VPN hosts of paired Macs, so a
                    // Mac Bonjour can't see still shows up (RemoteHostsStore).
                    overlayDirectory: RemoteHostsStore.overlayConfiguration,
                    remoteSignaling: DeckHandCloud.remoteSignalingConfiguration,
                    // S1: no AWDL. Peer-to-peer Wi-Fi takes the radio off
                    // channel every half second (p90 ~50 ms instead of ~4 ms).
                    enablePeerToPeer: false,
                    // `ph-proto` in the Bonjour TXT record, so the Mac's menu
                    // bar can say "Please update" (PeerCompatibility), and
                    // `ph-role` so other remotes don't list this one as a Mac.
                    advertisementMetadata: PixelHandProtocol.advertisementMetadata(role: .remote),
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
        IntentBridge.shared.start() // Intents lane: App Intents, widgets, controls
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
            .subscriptionStore() // Store lane: StoreKit, \.entitlements, paywalls
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
            title: "Pixel Hand couldn't start",
            message: [
                message,
                "Quit Pixel Hand from the app switcher and open it again. If this keeps happening, reinstall the app.",
            ]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
