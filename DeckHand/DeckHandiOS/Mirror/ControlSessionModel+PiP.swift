//
//  ControlSessionModel+PiP.swift
//  DeckHandiOS
//
//  UX-041, the live mirror in Picture in Picture (mirror lane). Stored
//  properties are under `// MARK: Mirror` in ControlSessionModel; the rules
//  are `MirrorPiPState` and friends in Core.
//
//  - Available while the mirror is open and Pro allows it; starts by
//    itself when the app leaves if Settings › Live mirror › "Keep
//    watching in Picture in Picture" is on, or from the mirror's PiP
//    button.
//  - While PiP could start, `MirrorPiPCompositor` keeps PiP's layer
//    current (two frames a second), with the pointer drawn in; while PiP
//    shows, at the stream's rate.
//  - While PiP shows, the session counts as in front for the network
//    lane's keep-alive and heartbeat (`mirrorPiPHoldsSession`, read by
//    `setForeground`), so the connection lives on in the background; the
//    Mac's sound (S17) keeps playing unless PiP is paused.
//  - Pause = freeze: the picture is held and the Mac is asked for one
//    frame a second; play asks for the full rate again.
//  - In the background the inline display layer can't decode, so HEVC
//    frames go only to PiP; back in front the inline watchdog starts over
//    and a key frame is asked for.
//  - 10 minutes paused, the device locking, the mirror stopping, Pro
//    ending or the session ending closes PiP.
//

import AVFoundation
import LoomKit
import SwiftUI
import UIKit

extension Notification.Name {
    /// The person tapped PiP to go back to the app: show the Screen
    /// surface.
    static let mirrorPiPRestoreScreen = Notification.Name("PixelHand.mirrorPiPRestoreScreen")
}

extension ControlSessionModel {

    // MARK: - Lifetime (from runMirrorStatsLoop)

    /// Wires the PiP controller and compositor and follows the app's
    /// lifecycle. Returns the observers to remove at the end.
    func startMirrorPiP() -> [NSObjectProtocol] {
        mirrorPiP.onActiveChanged = { [weak self] active in
            guard let self else { return }
            self.applyMirrorPiP(active ? self.mirrorPiPState.didStart() : self.mirrorPiPState.didStop())
        }
        mirrorPiP.onPausedChanged = { [weak self] paused in
            guard let self else { return }
            self.applyMirrorPiP(self.mirrorPiPState.setPaused(paused, now: CACurrentMediaTime()))
        }
        mirrorPiP.onWindowWidthChanged = { [weak self] width in
            guard let self else { return }
            self.mirrorPiPCompositor.windowPointWidth = width
            self.feedMirrorPiPPointer()
        }
        mirrorPiP.onPossibleChanged = { [weak self] possible in
            guard let self, self.mirrorPiPPossible != possible else { return }
            self.mirrorPiPPossible = possible
        }
        mirrorPiP.onRestore = {
            NotificationCenter.default.post(name: .mirrorPiPRestoreScreen, object: nil)
        }
        mirrorPiPCompositor.onFrame = { [weak self] sample in
            self?.mirrorPiP.enqueue(sample)
        }
        mirrorPiPCompositor.onPassthrough = { [weak self] sample in
            self?.mirrorPiP.enqueuePassthrough(sample)
        }
        mirrorPiPCompositor.onNeedsKeyFrame = { [weak self] in
            self?.requestMirrorKeyFrame()
        }
        mirrorAppInBackground = UIApplication.shared.applicationState == .background

        let center = NotificationCenter.default
        return [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.mirrorPiPAppDidEnterBackground() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.mirrorPiPAppWillEnterForeground() }
            },
            center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.applyMirrorPiP(self.mirrorPiPState.deviceLocked())
                }
            },
        ]
    }

    /// The session ended: close PiP and let go of everything it held.
    func stopMirrorPiP(observers: [NSObjectProtocol]) {
        observers.forEach(NotificationCenter.default.removeObserver)
        applyMirrorPiP(mirrorPiPState.sessionEnded())
        mirrorPiPCompositor.setMode(.off)
        mirrorPiPCompositor.reset()
        mirrorPiP.setAutoStart(false)
        mirrorPiP.flush()
        MirrorAudioSessionHold.shared.setHeld(false, stillPlaying: false)
    }

    /// Four times a second from the stats loop: the paused timeout.
    func tickMirrorPiP() {
        applyMirrorPiP(mirrorPiPState.tick(now: CACurrentMediaTime()))
    }

    // MARK: - What the views and the network lane read

    /// While PiP shows, the network lane keeps its keep-alive tick and
    /// heartbeat running in the background (`setForeground`).
    var mirrorPiPHoldsSession: Bool { mirrorPiPState.holdsSession }

    /// The mirror's PiP button can be used now.
    var mirrorPiPCanStart: Bool {
        MirrorPiPController.isSupported && mirrorPiPState.isAvailable && (mirrorPiPPossible || mirrorPiPState.isActive)
    }

    /// Whether to show a PiP button at all (the device supports PiP).
    var mirrorPiPSupported: Bool { MirrorPiPController.isSupported }

    // MARK: - Inputs from the views

    /// Pro (the mirror's feature) from the view environment.
    func setMirrorPiPEntitled(_ entitled: Bool) {
        guard entitled != mirrorPiPState.entitled else { return }
        applyMirrorPiP(mirrorPiPState.setEntitled(entitled))
    }

    /// Settings › Live mirror › "Keep watching in Picture in Picture".
    func setMirrorPiPAutoStart(_ enabled: Bool) {
        guard enabled != mirrorPiPState.autoStartEnabled else { return }
        mirrorPiPState.setAutoStartEnabled(enabled)
        updateMirrorPiPPipeline()
    }

    /// The PiP button: start, or close an open PiP.
    func toggleMirrorPiP() {
        if mirrorPiPState.isActive || mirrorPiP.isActive {
            mirrorPiP.stop()
        } else if mirrorPiPState.isAvailable {
            mirrorPiP.start()
        }
    }

    /// The mirror opened or closed (toggle, a Mac error).
    func mirrorPiPMirrorActiveChanged() {
        guard isMirrorActive != mirrorPiPState.mirrorActive else { return }
        applyMirrorPiP(mirrorPiPState.setMirrorActive(isMirrorActive))
    }

    // MARK: - Frames (from ControlSessionModel+Mirror)

    /// An HEVC sample the watchdog let through (or, in the background,
    /// every sample).
    func feedMirrorPiP(sample: CMSampleBuffer, isKeyFrame: Bool) {
        guard mirrorPiPCompositor.isRunning else { return }
        mirrorPiPCompositor.receive(sample: sample, isKeyFrame: isKeyFrame)
    }

    /// A JPEG frame.
    func feedMirrorPiP(image: UIImage) {
        guard mirrorPiPCompositor.isRunning else { return }
        mirrorPiPCompositor.receive(image: image)
    }

    /// The pointer moved, changed shape, or the PiP window resized.
    func feedMirrorPiPPointer() {
        guard mirrorPiPCompositor.isRunning else { return }
        let pointer = mirrorCursor.map {
            MirrorPiPCompositor.Pointer(state: $0, sprite: mirrorCursorSprite, displayPointWidth: mirroredDisplayPointWidth)
        }
        mirrorPiPCompositor.receive(pointer: pointer)
    }

    /// A new stream (mirror stopped, display or codec changed).
    func resetMirrorPiPStream() {
        mirrorPiPCompositor.reset()
    }

    // MARK: - Carrying out

    func applyMirrorPiP(_ effects: MirrorPiPState.Effects) {
        mirrorPiP.isPaused = mirrorPiPState.isPaused
        if effects.contains(.close) {
            DeckHandLog.connection.info("PiP: closing (\(self.mirrorPiPState.closeReason?.rawValue ?? "", privacy: .public))")
            mirrorPiP.stop()
        }
        if effects.contains(.sessionHoldChanged) {
            // Network lane: re-judge "in front" with PiP's hold.
            setForeground(UIApplication.shared.applicationState != .background)
            DeckHandLog.connection.info("PiP: \(self.mirrorPiPState.holdsSession ? "holding the connection in the background" : "released the connection", privacy: .public)")
        }
        if effects.contains(.renegotiate) {
            mirrorPiP.playbackStateChanged()
            if isMirrorActive, let settings = mirrorSettings {
                renegotiateMirror(settings: settings)
            }
        }
        if effects.contains(.audioChanged) {
            syncMirrorAudio()
        }
        updateMirrorPiPPipeline()
    }

    /// Compositor pace, automatic start and the audio session, from the
    /// state.
    func updateMirrorPiPPipeline() {
        let supported = MirrorPiPController.isSupported
        let fps = mirrorSettings?.mirrorFrameRate.rawValue ?? MirrorFrameRate.smooth.rawValue
        let mode = supported ? MirrorPiPPacer.mode(for: mirrorPiPState, streamFPS: fps) : .off
        let wasRunning = mirrorPiPCompositor.isRunning
        mirrorPiPCompositor.setMode(mode)
        mirrorPiP.setAutoStart(supported && mirrorPiPState.canStartAutomatically)
        let appActive = UIApplication.shared.applicationState != .background
        MirrorAudioSessionHold.shared.setHeld(mode != .off, stillPlaying: mirrorAudioWanted(appActive: appActive))
        guard mode != .off, !wasRunning else { return }
        // Just started: give the layer a picture as soon as possible.
        feedMirrorPiPPointer()
        if let mirrorImage {
            mirrorPiPCompositor.receive(image: mirrorImage)
        } else if mirrorShowsVideo {
            requestMirrorKeyFrame()
        }
    }

    // MARK: - Background

    private func mirrorPiPAppDidEnterBackground() {
        mirrorAppInBackground = true
    }

    private func mirrorPiPAppWillEnterForeground() {
        let wasBackground = mirrorAppInBackground
        mirrorAppInBackground = false
        // The inline layer got nothing (or failed) in the background:
        // start its watchdog over at the next key frame.
        guard wasBackground, isMirrorActive, mirrorShowsVideo else { return }
        mirrorWatchdog.reset(now: CACurrentMediaTime())
        requestMirrorKeyFrame()
    }

    private func requestMirrorKeyFrame() {
        guard isMirrorActive else { return }
        let connection = connection
        Task { try? await connection.send(.mirror(.requestKeyFrame)) }
    }
}
