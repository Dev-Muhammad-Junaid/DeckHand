//
//  AppUpdater.swift
//  DeckHandMac
//
//  Sparkle 2 self-updates for the Developer ID build that the website
//  distributes. The appcast URL and EdDSA public key come from Info.plist
//  (`SUFeedURL`, `SUPublicEDKey`), which project.yml fills in from the
//  `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY` build settings.
//
//  Behaviour:
//  - automatic checks are on (`SUEnableAutomaticChecks`), automatic install
//    is off (`SUAutomaticallyUpdate`), so the user always sees the update
//    alert and chooses when to install;
//  - "Check for Updates…" in the menu-bar panel calls `checkForUpdates()`;
//  - when an iPhone or iPad is connected, the relaunch waits for a
//    confirmation, because installing quits the app and drops the session.
//
//  If the build has no public key (a development build before the owner has
//  run `generate_keys`), the updater is never started and the menu item is
//  disabled, instead of Sparkle showing a configuration error at launch.
//
//  Release/RELEASING.md covers keys, signing and the appcast.
//

import AppKit
import Combine
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    static let shared = AppUpdater()

    /// Mirrors `SPUUpdater.canCheckForUpdates` (false while a check runs).
    @Published private(set) var canCheckForUpdates = false

    /// Whether this build carries a feed URL and public key at all.
    let isConfigured: Bool

    /// Remotes with a live session, kept current by the app delegate. Used to
    /// warn before an install relaunches the app.
    var liveConnections = 0

    private var controller: SPUStandardUpdaterController?
    private var canCheckObserver: AnyCancellable?

    private override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let feed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        isConfigured = !key.isEmpty && URL(string: feed)?.scheme == "https"
        super.init()
    }

    /// Starts Sparkle's scheduler. Call once, from `applicationDidFinishLaunching`.
    func start() {
        guard controller == nil else { return }
        guard isConfigured else {
            DeckHandLog.app.notice("Sparkle not started: SUPublicEDKey or SUFeedURL is missing from this build")
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        canCheckObserver = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                MainActor.assumeIsolated { self?.canCheckForUpdates = value }
            }
    }

    /// The "Check for Updates…" action. Sparkle shows its own window.
    func checkForUpdates() {
        guard let controller else { return }
        // A menu-bar agent isn't frontmost; bring Sparkle's window forward.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate

extension AppUpdater: SPUUpdaterDelegate {
    /// Beta testers opt in with
    /// `defaults write com.widgetsflow.pixelhand.mac PixelHandBetaUpdates -bool YES`;
    /// they then also see appcast items on the "beta" channel.
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: "PixelHandBetaUpdates") ? ["beta"] : []
    }

    /// Holds the relaunch while a remote is connected, until the user agrees.
    nonisolated func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        // Sparkle calls this on the main thread, so the handler never leaves it.
        nonisolated(unsafe) let installHandler = installHandler
        return MainActor.assumeIsolated {
            guard liveConnections > 0 else { return false }
            let alert = NSAlert()
            alert.messageText = "Updating disconnects your devices"
            alert.informativeText = liveConnections == 1
                ? "Pixel Hand will quit and reopen to install version \(item.displayVersionString). The connected iPhone or iPad will need to reconnect."
                : "Pixel Hand will quit and reopen to install version \(item.displayVersionString). The \(liveConnections) connected devices will need to reconnect."
            alert.addButton(withTitle: "Update Now")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                installHandler()
            }
            // "Later": Sparkle keeps the downloaded update and installs it
            // when the app next quits.
            return true
        }
    }
}
