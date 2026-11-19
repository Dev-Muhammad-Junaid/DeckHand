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
//  - the display picker, Follow cursor and the "Cursor is on …" badge;
//  - the stats window sent back to the Mac once a second (S6).
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
        await MirrorStreamReceiver(stats: mirrorStatsBox).run(connection: connection, sink: self)
    }

    /// Once a second while the mirror runs: close the stats window, show it
    /// on the HUD and send it to the Mac for its log line.
    func runMirrorStatsLoop() async {
        var windowStart = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(MirrorStatsPolicy.reportInterval))
            let elapsed = ContinuousClock.now - windowStart
            windowStart = .now
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let stats = mirrorStatsBox.takeStats(elapsed: seconds)
            guard isMirrorActive else { continue }
            mirrorClientStats = stats
            try? await connection.send(.diagnostics(.mirrorClientStats(stats: stats)))
        }
    }

    // MARK: - MirrorStreamSink

    func mirrorDidDecode(_ image: UIImage, header: BinaryFrameHeader) {
        guard isMirrorActive else { return }
        mirrorImage = image
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
        let cursorDisplayID: UInt32? = state.displayID == 0 ? nil : state.displayID
        if mirrorCursorDisplayID != cursorDisplayID {
            mirrorCursorDisplayID = cursorDisplayID
        }
        followCursorIfNeeded(state)
    }

    func mirrorDidReceiveCursorShape(_ shape: MirrorCursorShape, image: UIImage) {
        mirrorCursorShapes.insert(shape, image: image)
        if mirrorCursor?.shapeID == shape.id {
            mirrorCursorSprite = MirrorCursorSprite(shape: shape, image: image)
        }
    }

    // MARK: - Control-stream messages

    func handleMirrorDisplayList(_ displays: [DisplayInfo], selected: UInt32) {
        mirrorDisplays = displays
        if selectedMirrorDisplayID != selected {
            selectedMirrorDisplayID = selected
            mirrorFollower.reset()
        }
    }

    func handleMirrorError(_ message: String) {
        // Stop the mirror and surface the reason.
        guard isMirrorActive else { return }
        isMirrorActive = false
        clearMirrorState()
        capture.showMirrorError(message)
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
            let fps = settings.mirrorFrameRate.rawValue
            let width = settings.mirrorStreamWidth(naturalWidth: mirrorNaturalWidth)
            let displayID = selectedMirrorDisplayID
            Task { await sender.startMirror(fps: fps, maxWidth: width, displayID: displayID) }
        } else {
            clearMirrorState()
            Task { await sender.stopMirror() }
        }
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
        guard displayID != selectedMirrorDisplayID else { return }
        // Shown at once; the Mac confirms with `displayList`.
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

    /// What the mirror's display chrome shows now.
    var mirrorChrome: MirrorDisplayChrome {
        MirrorDisplayChrome.make(
            displays: mirrorDisplays,
            mirroredDisplayID: selectedMirrorDisplayID,
            cursorDisplayID: mirrorCursorDisplayID,
            followsCursor: mirrorSettings?.mirrorFollowsCursor ?? false
        )
    }

    /// The mirrored display's width in points, for scaling the pointer.
    var mirroredDisplayPointWidth: Double {
        let display = mirrorDisplays.first { $0.displayID == selectedMirrorDisplayID }
        return Double(display?.width ?? 1_440)
    }

    // MARK: - Helpers

    private func restartMirror(displayID: UInt32?) {
        guard let sender, isMirrorActive, let settings = mirrorSettings else { return }
        let fps = settings.mirrorFrameRate.rawValue
        let width = settings.mirrorStreamWidth(naturalWidth: mirrorNaturalWidth)
        Task { await sender.startMirror(fps: fps, maxWidth: width, displayID: displayID) }
    }

    private func followCursorIfNeeded(_ state: MirrorCursorState) {
        guard mirrorSettings?.mirrorFollowsCursor == true else { return }
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
        mirrorCursor = nil
        mirrorCursorDisplayID = nil
        mirrorCursorSprite = nil
        mirrorHostStats = nil
        mirrorClientStats = nil
        mirrorFollower.reset()
    }
}
