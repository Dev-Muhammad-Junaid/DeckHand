//
//  ControlSessionModel+Network.swift
//  DeckHandiOS
//
//  The network lane's part of the session model (S1, S13):
//
//  - Heartbeat: ping every 2 s; declare the Mac gone after 10 s with no
//    traffic at all from it (any message counts, not only pongs). A check
//    that runs late means this device stalled, and restarts the silence
//    clock instead of blaming the Mac.
//  - Keep-alive tick: a tiny `session.tick` every 0.25 s while in front on
//    a link that dozes (Wi-Fi), so the radio doesn't fall into power save
//    between pings. None over the USB cable or Ethernet.
//  - Background: ticks and pings stop when the app leaves the front; on
//    the way back the liveness clock restarts and a ping goes out at once.
//  - Link: this side's judgement from Loom's path (public API only) merged
//    with the Mac's `session.link` report, shown as "Wired", "Wi-Fi", …
//
//  Every task here is cancelled by `stopNetwork()`, which `run` defers, so
//  they end with the view's `.task`.
//

import Foundation
import LoomKit
import SwiftUI
import UIKit

extension ControlSessionModel {

    /// Starts the heartbeat, the keep-alive tick, link judging and the
    /// background observers. Returns the liveness clock the message loop
    /// stamps.
    func startNetwork(sender s: TrackpadSender) -> LivenessClock {
        let liveness = LivenessClock(LivenessPolicy.remoteMonitor())
        livenessClock = liveness
        keepAlive = KeepAliveGate(isForeground: UIApplication.shared.applicationState != .background)
        link = .unknown
        RemoteLinkStatus.shared.current = .unknown
        networkTasks = [
            heartbeatTask(sender: s, liveness: liveness),
            keepAliveTask(),
            linkTask(),
        ]
        observeLifecycle()
        return liveness
    }

    func stopNetwork() {
        networkTasks.forEach { $0.cancel() }
        networkTasks = []
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers = []
        RemoteLinkStatus.shared.current = nil
    }

    // MARK: - Heartbeat

    private func heartbeatTask(sender s: TrackpadSender, liveness: LivenessClock) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.keepAlive.isPinging {
                    self.pingSeq &+= 1
                    await s.sendPing(seq: self.pingSeq)
                }
                try? await Task.sleep(for: .seconds(LivenessPolicy.pingInterval))
                guard !Task.isCancelled else { return }
                // In the background nothing is checked: the Mac can't be
                // blamed for silence while this side isn't listening.
                guard self.keepAlive.isPinging else { continue }
                switch liveness.check() {
                case let .localStall(gap):
                    DeckHandLog.connection.info("Heartbeat check ran \(gap, format: .fixed(precision: 1), privacy: .public)s late (iPad stalled or suspended); restarting the silence clock")
                case let .dead(silence, sinceHeartbeat):
                    liveness.markGaveUp()
                    let state = liveness.snapshot
                    DeckHandLog.connection.error("Heartbeat: IPAD GAVE UP on the Mac: nothing received for \(silence, format: .fixed(precision: 1), privacy: .public)s (last pong \(sinceHeartbeat, format: .fixed(precision: 1), privacy: .public)s ago, \(state.inboundCount, privacy: .public) messages total, last ping seq \(self.pingSeq, privacy: .public), timeout \(LivenessPolicy.remoteTimeout, privacy: .public)s)")
                    if self.lastAuthStatus != "denied" {
                        self.onAuthStatusChanged("host_disconnected")
                    }
                    return
                case .alive, .notEstablished:
                    break
                }
            }
        }
    }

    // MARK: - Keep-alive tick (S1)

    private func keepAliveTask() -> Task<Void, Never> {
        let connection = connection
        return Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(KeepAlivePolicy.tickInterval))
                guard let self, !Task.isCancelled else { return }
                guard self.keepAlive.isTicking else { continue }
                do {
                    try await connection.send(.session(.tick))
                    failures = 0
                } catch {
                    // Log once per run of failures; the heartbeat decides
                    // whether the Mac is gone.
                    failures += 1
                    if failures == 1 {
                        DeckHandLog.connection.error("Keep-alive tick failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    // MARK: - Background pause

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setForeground(false) }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setForeground(true) }
            },
        ]
    }

    func setForeground(_ foreground: Bool) {
        switch keepAlive.setForeground(foreground) {
        case .none:
            break
        case .paused:
            DeckHandLog.connection.info("In the background: keep-alive ticks and pings paused")
        case .resumed:
            // Time spent suspended is not the Mac's silence.
            livenessClock?.restart()
            DeckHandLog.connection.info("Back in front: liveness clock restarted, pinging now")
            if let sender {
                pingSeq &+= 1
                let seq = pingSeq
                Task { await sender.sendPing(seq: seq) }
            }
        }
    }

    // MARK: - Link (S13)

    private func linkTask() -> Task<Void, Never> {
        let connection = connection
        return Task { [weak self] in
            for await snapshot in connection.networkPathUpdates {
                let local = LinkJudge.judge(LinkObservation(snapshot: snapshot, addressOwners: InterfaceAddressTable.current()))
                guard let self else { return }
                self.keepAlive.setLocalLink(local)
                self.publishLink()
            }
        }
    }

    /// The Mac's judgement, from `session.link`.
    func applyHostLink(_ kind: LinkKind) {
        keepAlive.setPeerLink(kind)
        publishLink()
    }

    private func publishLink() {
        let shown = keepAlive.displayedLink
        guard shown != link else { return }
        DeckHandLog.connection.info("Link: \(self.link.rawValue, privacy: .public) → \(shown.rawValue, privacy: .public) (this side \(self.keepAlive.localLink.rawValue, privacy: .public), Mac \(self.keepAlive.peerLink?.rawValue ?? "unknown", privacy: .public); ticking \(self.keepAlive.isTicking, privacy: .public))")
        withAnimation(.easeInOut(duration: 0.2)) {
            link = shown
        }
        RemoteLinkStatus.shared.current = shown
    }
}
