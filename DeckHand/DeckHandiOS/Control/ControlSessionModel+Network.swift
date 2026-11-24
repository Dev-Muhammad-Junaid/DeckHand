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
//    with the Mac's `session.link` report, shown as "Wired", "Wi-Fi", "VPN"…
//  - Remote access (S15): the Mac's VPN addresses (`session.remoteHosts`)
//    are saved for a paired Mac; round trips from ping/pong and the link
//    drive `AwayQualityPolicy`, which lowers the mirror request over a VPN
//    or a slow link and re-negotiates a running mirror when that changes.
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
        RemoteLinkStatus.shared.isAway = false
        roundTrips.reset()
        awayQuality = AwayQualityPolicy()
        awaySentMirrorCodec = nil
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
        RemoteLinkStatus.shared.isAway = false
    }

    // MARK: - Heartbeat

    private func heartbeatTask(sender s: TrackpadSender, liveness: LivenessClock) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.keepAlive.isPinging {
                    self.pingSeq &+= 1
                    self.roundTrips.pingSent(seq: self.pingSeq, at: ProcessInfo.processInfo.systemUptime)
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
        // PiP lane hook (UX-041): while Picture in Picture shows the
        // mirror, the session counts as in front, so ticks and the
        // heartbeat keep the connection alive in the background. PiP calls
        // this again when it starts or stops.
        let foreground = foreground || mirrorPiPHoldsSession
        switch keepAlive.setForeground(foreground) {
        case .none:
            break
        case .paused:
            DeckHandLog.connection.info("In the background: keep-alive ticks and pings paused")
        case .resumed:
            // Time spent suspended is not the Mac's silence.
            livenessClock?.restart()
            // A round trip that spans a suspension isn't the link's.
            roundTrips.reset()
            DeckHandLog.connection.info("Back in front: liveness clock restarted, pinging now")
            if let sender {
                pingSeq &+= 1
                let seq = pingSeq
                roundTrips.pingSent(seq: seq, at: ProcessInfo.processInfo.systemUptime)
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
        if awayQuality.setLink(shown) { awayChanged() }
    }

    // MARK: - Remote access (S15)

    /// The Mac's own VPN addresses. Saved only if this Mac is paired
    /// (`RemoteHostsStore` re-checks against the pairing list).
    func applyRemoteHosts(_ hosts: [String]) {
        guard let mac = pairingMac else { return }
        RemoteHostsStore.shared.macReported(hosts, mac: mac.ref)
    }

    /// A pong: one round-trip sample for the away policy.
    func notePong(seq: UInt64) {
        guard let smoothed = roundTrips.pongReceived(seq: seq, at: ProcessInfo.processInfo.systemUptime) else { return }
        if awayQuality.noteRoundTrip(smoothed) { awayChanged() }
    }

    private func awayChanged() {
        let rttMs = Int((roundTrips.smoothed ?? 0) * 1_000)
        DeckHandLog.connection.info("Mirror quality: \(self.awayQuality.isAway ? "away (VPN or slow link)" : "home", privacy: .public); link \(self.awayQuality.link.rawValue, privacy: .public), smoothed RTT \(rttMs, privacy: .public) ms")
        RemoteLinkStatus.shared.isAway = awayQuality.isAway
        guard isMirrorActive, let settings = mirrorSettings else { return }
        renegotiateMirror(settings: settings)
    }

    /// Sends `mirror.start` through the away policy. The Mirror code calls
    /// this with what its settings ask for; at home it goes out unchanged.
    func sendMirrorStart(_ sender: TrackpadSender, fps: Int, maxWidth: Int, displayID: UInt32?, codec: MirrorCodec, windowID: UInt32?) async {
        let hevcAvailable = MirrorVideoRenderer.hevcDecodeAvailable && !mirrorHEVCFellBack
        let shape = awayQuality.adjust(MirrorRequestShape(fps: fps, maxWidth: maxWidth, codec: codec), hevcAvailable: hevcAvailable)
        if let sent = awaySentMirrorCodec, sent != shape.codec, codec == mirrorLastRequestedCodec {
            // The away policy switched codecs: HEVC starts over at the
            // Mac's next key frame, as after a settings change.
            mirrorWatchdog.reset(now: CACurrentMediaTime())
        }
        awaySentMirrorCodec = shape.codec
        await sender.startMirror(fps: shape.fps, maxWidth: shape.maxWidth, displayID: displayID, codec: shape.codec, windowID: windowID)
    }
}
