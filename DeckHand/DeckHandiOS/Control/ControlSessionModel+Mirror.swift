//
//  ControlSessionModel+Mirror.swift
//  DeckHandiOS
//
//  The live mirror's logic for one connection (owned by the mirror lane;
//  stored properties are under `// MARK: Mirror` in ControlSessionModel):
//
//  - start, stop and re-negotiate (WID-403);
//  - frames and the cursor from the binary mirror stream
//    (`MirrorStreamReceiver`, S3);
//  - the display picker, Follow cursor and the "Cursor is on …" badge
//    (the badge falls back to the Mac's display snapshot when the cursor
//    stream hasn't said yet);
//  - the desktop dots and ‹ › states (`mirrorSpaceStrip`);
//  - the stats window sent back to the Mac once a second (S6);
//  - HEVC video (S5): which codec to ask for, feeding the display layer,
//    and the watchdog (key frame requests, fallback to JPEG);
//  - one window instead of a display (S14): the picker's "Window…" entry
//    opens the capture window picker; the window ID rides every start
//    until a display is picked or the Mac falls back (`mirror.error` with
//    a `fallbackDisplayID`, shown as a passing notice);
//  - the Mac's sound (S17) starts and stops with the mirror
//    (ControlSessionModel+Audio.swift);
//  - Picture in Picture (UX-041) gets every frame and pointer update too,
//    and its pause lowers the frame rate asked for
//    (Mirror/ControlSessionModel+PiP.swift).
//

import LoomKit
import SwiftUI

/// A pointer image ready to draw.
struct MirrorCursorSprite {
    let shape: MirrorCursorShape
    let image: UIImage
}

extension ControlSessionModel: MirrorStreamSink {

    // MARK: - Loops started by run(settings:)

    /// Reads the mirror stream until the session ends.
    func runMirrorReceiver() async {
        // S17: the Mac's sound has its own stream and reader alongside.
        async let audio: Void = runMirrorAudio()
        await MirrorStreamReceiver(stats: mirrorStatsBox).run(connection: connection, sink: self)
        await audio
    }

    /// Four times a second, the HEVC watchdog's clock; once a second while
    /// the mirror runs, close the stats window, show it on the HUD and send
    /// it to the Mac for its log line.
    func runMirrorStatsLoop() async {
        mirrorVideoRenderer.onDecodeFailure = { [weak self] in
            guard let self, self.mirrorShowsVideo || self.isMirrorActive else { return }
            // In the background the inline layer isn't fed (UX-041).
            guard !self.mirrorAppInBackground else { return }
            self.handleWatchdog(self.mirrorWatchdog.decodeFailed(now: CACurrentMediaTime()))
        }
        // UX-041: PiP lives as long as the session.
        let pipObservers = startMirrorPiP()
        defer { stopMirrorPiP(observers: pipObservers) }
        var windowStart = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            if isMirrorActive, !mirrorAppInBackground {
                handleWatchdog(mirrorWatchdog.tick(now: CACurrentMediaTime()))
            }
            tickMirrorPiP()
            let elapsed = ContinuousClock.now - windowStart
            guard elapsed >= .seconds(MirrorStatsPolicy.reportInterval) else { continue }
            windowStart = .now
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            var stats = mirrorStatsBox.takeStats(elapsed: seconds)
            stats.audio = mirrorAudio.takeStats() // S17; nil while no sound arrives
            guard isMirrorActive else { continue }
            mirrorClientStats = stats
            try? await connection.send(.diagnostics(.mirrorClientStats(stats: stats)))
        }
    }

    // MARK: - MirrorStreamSink

    func mirrorDidDecode(_ image: UIImage, header: BinaryFrameHeader) {
        guard isMirrorActive else { return }
        if mirrorShowsVideo {
            // The Mac switched this remote to JPEG (fallback, or no encoder).
            mirrorShowsVideo = false
            mirrorVideoRenderer.flush()
            resetMirrorPiPStream()
        }
        mirrorImage = image
        feedMirrorPiP(image: image)
    }

    func mirrorDidReceiveVideo(_ event: MirrorVideoEvent) {
        guard isMirrorActive else { return }
        let now = CACurrentMediaTime()
        switch event {
        case let .parameterSets(valid, dimensions):
            guard valid else {
                handleWatchdog(mirrorWatchdog.decodeFailed(now: now))
                return
            }
            _ = mirrorWatchdog.frameArrived(.parameterSets, now: now)
            if let dimensions, mirrorVideoSize != dimensions {
                mirrorVideoSize = dimensions
            }

        case let .frame(kind, afterDrop, sample):
            if mirrorAppInBackground {
                // UX-041: the inline layer can't decode in the background;
                // only PiP gets the stream (and keeps its own recovery).
                if let sample { feedMirrorPiP(sample: sample, isKeyFrame: kind == .keyFrame) }
                return
            }
            let verdict = mirrorWatchdog.frameArrived(kind, afterDrop: afterDrop, now: now)
            handleWatchdog(verdict.action)
            guard verdict.decode else {
                mirrorStatsBox.update { $0.noteDropped() }
                return
            }
            if let sample { feedMirrorPiP(sample: sample, isKeyFrame: kind == .keyFrame) }
            guard let sample, mirrorVideoRenderer.enqueue(sample) else {
                handleWatchdog(mirrorWatchdog.decodeFailed(now: now))
                return
            }
            if mirrorLoupeActive, !mirrorLoupeRenderer.enqueue(sample) {
                // The loupe's layer lost the stream (it started between
                // key frames): it recovers at the next one.
                mirrorLoupeRenderer.flush()
            }
            mirrorWatchdog.frameDisplayed(now: now)
            mirrorStatsBox.update { $0.noteFrameOut() }
            if !mirrorShowsVideo {
                mirrorShowsVideo = true
                mirrorImage = nil
            }
        }
    }

    func mirrorCursorDidChange(_ state: MirrorCursorState) {
        guard isMirrorActive else { return }
        if mirrorCursorSprite?.shape.id != state.shapeID {
            mirrorCursorSprite = mirrorCursorShapes.entry(for: state.shapeID)
                .map { MirrorCursorSprite(shape: $0.shape, image: $0.image) }
        }
        if mirrorCursor != state {
            mirrorCursor = state
        }
        if mirrorCursorInsideMirror != state.isOnMirroredDisplay {
            mirrorCursorInsideMirror = state.isOnMirroredDisplay
        }
        let cursorDisplayID: UInt32? = state.displayID == 0 ? nil : state.displayID
        if mirrorCursorDisplayID != cursorDisplayID {
            mirrorCursorDisplayID = cursorDisplayID
        }
        followCursorIfNeeded(state)
        feedMirrorPiPPointer()
    }

    func mirrorDidReceiveCursorShape(_ shape: MirrorCursorShape, image: UIImage) {
        mirrorCursorShapes.insert(shape, image: image)
        if mirrorCursor?.shapeID == shape.id {
            mirrorCursorSprite = MirrorCursorSprite(shape: shape, image: image)
            feedMirrorPiPPointer()
        }
    }

    // MARK: - Control-stream messages

    func handleMirrorDisplayList(_ displays: [DisplayInfo], selected: UInt32, window: MirroredWindow?) {
        mirrorDisplays = displays
        if selectedMirrorDisplayID != selected {
            selectedMirrorDisplayID = selected
            mirrorFollower.reset()
        }
        if mirrorWindowSelection.window != window {
            mirrorWindowSelection.hostReported(window: window)
        }
    }

    func handleMirrorError(_ message: String, fallbackDisplayID: UInt32?) {
        if let fallbackDisplayID {
            // S14: the mirrored window ended; the Mac already shows its
            // display. Keep the mirror, say why.
            guard isMirrorActive else { return }
            mirrorWindowSelection.windowEnded()
            selectedMirrorDisplayID = fallbackDisplayID
            mirrorFollower.reset()
            showMirrorNotice(message)
            return
        }
        // Stop the mirror and surface the reason.
        guard isMirrorActive else { return }
        isMirrorActive = false
        clearMirrorState()
        syncMirrorAudio()
        mirrorPiPMirrorActiveChanged()
        // Build 19: the lock banner already knows the Mac is locked; say
        // so instead of whatever an older Mac sent.
        capture.showMirrorError(macLockState.isLocked ? LockPolicy.lockedErrorMessage : message)
    }

    // MARK: - Loupe (OT-12)

    /// The Type panel's loupe opens or closes: it follows the Mac's focused
    /// field, and its layer gets the mirror's frames from the next key
    /// frame (asked for now, so it doesn't wait for the periodic one).
    func setMirrorLoupe(active: Bool) {
        guard mirrorLoupeActive != active else { return }
        mirrorLoupeActive = active
        mirrorLoupeRenderer.flush()
        if active, isMirrorActive {
            let connection = connection
            Task { try? await connection.send(.mirror(.requestKeyFrame)) }
        }
        updateFocusWatch()
    }

    // MARK: - Start, stop, re-negotiate

    /// Flips the mirror on/off: updates local UI state immediately for
    /// responsiveness, then tells the Mac. Frame state is reset on stop so
    /// a later restart begins with the loading placeholder, and the last
    /// decoded frame isn't retained while the mirror is hidden.
    func toggleMirror(settings: DeckHandSettings) {
        guard let sender else { return }
        mirrorSettings = settings
        isMirrorActive.toggle()
        if isMirrorActive {
            clearMirrorState()
            // Seed from the layout the mirror will restore to, so a large
            // saved mirror opens at the right resolution instead of starting
            // small and immediately renegotiating.
            if settings.rememberMirrorLayout, let saved = settings.mirrorLayout {
                mirrorNaturalWidth = MirrorThumbnailView.streamWidth(for: CGFloat(saved.width))
            }
            let fps = mirrorPiPState.requestedFPS(settingsFPS: settings.mirrorFrameRate.rawValue)
            let width = settings.mirrorStreamWidth(naturalWidth: mirrorNaturalWidth)
            let displayID = selectedMirrorDisplayID
            let codec = mirrorRequestedCodec(settings)
            mirrorLastRequestedCodec = codec
            // A fresh mirror shows a display; a window is picked from it.
            Task { await sendMirrorStart(sender, fps: fps, maxWidth: width, displayID: displayID, codec: codec, windowID: nil) } // S15 away quality (network lane)
        } else {
            clearMirrorState()
            Task { await sender.stopMirror() }
        }
        // S17: the Mac's sound comes and goes with the mirror.
        syncMirrorAudio()
        // UX-041: so does Picture in Picture.
        mirrorPiPMirrorActiveChanged()
    }

    /// Re-negotiates the mirror to match how large the user has pinched the
    /// thumbnail and what the sharpness and frame-rate settings ask for. The
    /// Mac changes the running capture in place, so this is just another
    /// `start`; no stop, no new stream.
    func renegotiateMirror(settings: DeckHandSettings) {
        mirrorSettings = settings
        restartMirror(displayID: selectedMirrorDisplayID)
    }

    /// Points the mirror at another display (the picker, Follow cursor, the
    /// badge).
    func selectMirrorDisplay(_ displayID: UInt32) {
        // Picking the window's own display leaves the window (S14).
        guard displayID != selectedMirrorDisplayID || mirrorWindowSelection.isActive else { return }
        // Shown at once; the Mac confirms with `displayList`.
        mirrorWindowSelection.selectDisplay()
        selectedMirrorDisplayID = displayID
        mirrorFollower.reset()
        restartMirror(displayID: displayID)
    }

    /// Moves the Mac's pointer onto the mirrored display (the badge's
    /// "Bring here").
    func bringCursorToMirroredDisplay() {
        guard let displayID = selectedMirrorDisplayID else { return }
        let connection = connection
        Task { try? await connection.send(.mirror(.moveCursor(displayID: displayID))) }
    }

    func switchSpace(_ direction: SpaceDirection) {
        let displayID = selectedMirrorDisplayID
        Task { await sender?.switchSpace(direction, displayID: displayID) }
    }

    // MARK: - Window mirror (S14)

    /// The picker's "Window…": the capture window picker, whose pick
    /// mirrors that window.
    func openMirrorWindowPicker() {
        guard isMirrorActive, !macLockState.isLocked else { return }
        capture.onPickMirrorWindow = { [weak self] window in
            self?.mirrorWindow(window.windowID)
        }
        capture.openWindowPicker(purpose: .mirror)
    }

    /// Mirrors one window; the Mac confirms with `displayList(window:)` or
    /// falls back with `mirror.error`.
    func mirrorWindow(_ windowID: UInt32) {
        guard isMirrorActive, !macLockState.isLocked else { return }
        mirrorWindowSelection.selectWindow(windowID)
        mirrorFollower.reset()
        restartMirror(displayID: selectedMirrorDisplayID)
    }

    /// Whether the picker's "Window…" can be used: not while the Mac is
    /// locked (the gate refuses window mirrors then).
    var canMirrorWindow: Bool { !macLockState.isLocked }

    func showMirrorNotice(_ message: String) {
        mirrorNoticeTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { mirrorNotice = message }
        mirrorNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeInOut(duration: 0.2)) { self.mirrorNotice = nil }
        }
    }

    /// What the mirror's display chrome shows now.
    var mirrorChrome: MirrorDisplayChrome {
        MirrorDisplayChrome.make(
            displays: mirrorDisplays,
            mirroredDisplayID: selectedMirrorDisplayID,
            cursorDisplayID: MirrorDisplayChrome.cursorDisplayID(stream: mirrorCursorDisplayID, layout: displayLayout),
            followsCursor: mirrorSettings?.mirrorFollowsCursor ?? false,
            mirroringWindow: mirrorWindowSelection.isActive,
            cursorOverWindow: mirrorCursorInsideMirror
        )
    }

    /// The desktop dots and ‹ › states for the mirrored display, from the
    /// Mac's display snapshot (`displayLayout`, Mac system lane). None for
    /// a window.
    var mirrorSpaceStrip: MirrorSpaceStrip {
        if mirrorWindowSelection.isActive { return .window }
        return MirrorSpaceStrip.make(layout: displayLayout, mirroredDisplayID: selectedMirrorDisplayID)
    }

    /// The mirrored display's (or window's) width in points, for scaling
    /// the pointer.
    var mirroredDisplayPointWidth: Double {
        let display = mirrorDisplays.first { $0.displayID == selectedMirrorDisplayID }
        return mirrorWindowSelection.pointWidth(displayWidth: Double(display?.width ?? 1_440))
    }

    /// The mirrored display's size in points, for keeping the picture's
    /// pointer on it (VQ-095). Nil while a window is mirrored or before
    /// the display list arrives: then only the gain cap applies.
    var mirroredDisplayPointSize: (width: Double, height: Double)? {
        guard !mirrorWindowSelection.isActive,
              let display = mirrorDisplays.first(where: { $0.displayID == selectedMirrorDisplayID }),
              display.width > 0, display.height > 0
        else { return nil }
        return (Double(display.width), Double(display.height))
    }

    // MARK: - Helpers

    private func restartMirror(displayID: UInt32?) {
        guard let sender, isMirrorActive, let settings = mirrorSettings else { return }
        // UX-041: one frame a second while PiP is paused.
        let fps = mirrorPiPState.requestedFPS(settingsFPS: settings.mirrorFrameRate.rawValue)
        let width = settings.mirrorStreamWidth(naturalWidth: mirrorNaturalWidth)
        let codec = mirrorRequestedCodec(settings)
        if codec != mirrorLastRequestedCodec {
            // Another codec: HEVC starts over at the Mac's next key frame.
            // (No-op after a fallback, which lasts for the session.)
            mirrorWatchdog.reset(now: CACurrentMediaTime())
        }
        mirrorLastRequestedCodec = codec
        let windowID = mirrorWindowSelection.requestedWindowID
        Task { await sendMirrorStart(sender, fps: fps, maxWidth: width, displayID: displayID, codec: codec, windowID: windowID) } // S15 away quality (network lane)
    }

    /// The codec to ask the Mac for (S5).
    func mirrorRequestedCodec(_ settings: DeckHandSettings) -> MirrorCodec {
        MirrorCodecChoice.requested(
            prefersHEVC: settings.mirrorPrefersHEVC,
            hevcDecodeAvailable: MirrorVideoRenderer.hevcDecodeAvailable,
            fellBack: mirrorHEVCFellBack
        )
    }

    /// Carries out what the HEVC watchdog decided.
    func handleWatchdog(_ action: MirrorVideoWatchdog.Action) {
        switch action {
        case .none:
            break
        case .requestKeyFrame:
            DeckHandLog.connection.info("Mirror: HEVC picture broken, asking the Mac for a key frame")
            let connection = connection
            Task { try? await connection.send(.mirror(.requestKeyFrame)) }
        case .fallBackToJPEG:
            DeckHandLog.connection.error("Mirror: HEVC isn't recovering, falling back to JPEG for this session")
            mirrorHEVCFellBack = true
            restartMirror(displayID: selectedMirrorDisplayID)
        }
    }

    private func followCursorIfNeeded(_ state: MirrorCursorState) {
        // A window mirror doesn't follow the pointer to another display.
        guard mirrorSettings?.mirrorFollowsCursor == true, !mirrorWindowSelection.isActive else { return }
        let target = mirrorFollower.update(
            cursorDisplayID: state.displayID,
            mirroredDisplayID: selectedMirrorDisplayID,
            knownDisplayIDs: Set(mirrorDisplays.map(\.displayID)),
            now: CACurrentMediaTime()
        )
        if let target {
            selectMirrorDisplay(target)
        }
    }

    private func clearMirrorState() {
        mirrorImage = nil
        mirrorShowsVideo = false
        mirrorVideoSize = nil
        mirrorVideoRenderer.flush()
        mirrorLoupeRenderer.flush()
        resetMirrorPiPStream()
        mirrorWatchdog = MirrorVideoWatchdog(now: CACurrentMediaTime())
        mirrorCursor = nil
        mirrorCursorInsideMirror = nil
        mirrorCursorDisplayID = nil
        mirrorWindowSelection.selectDisplay()
        mirrorNoticeTask?.cancel()
        mirrorNotice = nil
        mirrorCursorSprite = nil
        mirrorHostStats = nil
        mirrorClientStats = nil
        mirrorFollower.reset()
    }
}
