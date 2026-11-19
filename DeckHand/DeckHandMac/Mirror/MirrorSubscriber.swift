//
//  MirrorSubscriber.swift
//  DeckHandMac
//
//  One remote watching the mirror: its binary Loom stream
//  (`PixelHandStream.mirror`), what is in flight on it, the pointer images
//  it already has, and its stats window.
//
//  Send policy, per remote:
//
//   • Video: newest-frame-wins. While this remote's previous frame is still
//     on the wire the next one is dropped (and counted), so a slow link
//     lowers that remote's frame rate instead of queueing stale frames or
//     holding up the others.
//   • Cursor: never dropped behind video. One cursor send is in flight at a
//     time; a newer position replaces a waiting one.
//   • Pointer images go once per stream, just before the first position
//     that uses them.
//

import Foundation
import LoomKit

@MainActor
final class MirrorSubscriber {
    let id: UUID
    let handle: LoomConnectionHandle

    /// Throttles cursor updates to this remote.
    var cursorThrottle = MirrorCursorThrottle()
    /// This remote's half of the stats window (sent, dropped, bytes).
    var counter = MirrorStatsCounter()

    private var stream: LoomMultiplexedStream?
    private var opening: Task<LoomMultiplexedStream?, Never>?
    private var seq: UInt64 = 0
    private var frameInFlight = false
    private var cursorInFlight = false
    /// Pointer images waiting for the cursor send in flight (rare, kept).
    private var pendingShapes = Data()
    /// Newest position waiting for the cursor send in flight (replaced).
    private var pendingCursor: Data?
    private var sentShapes: Set<UInt32> = []
    /// The next video frame carries `formatChanged` (new stream, new size).
    private var formatChangedPending = true
    private var loggedSendFailure = false

    init(id: UUID, handle: LoomConnectionHandle) {
        self.id = id
        self.handle = handle
    }

    // MARK: Stream

    /// Opens this remote's binary stream if it isn't open. Returns whether
    /// it is open.
    @discardableResult
    func open() async -> Bool {
        if stream != nil { return true }
        if let opening { return await opening.value != nil }
        let handle = handle
        let task = Task<LoomMultiplexedStream?, Never> {
            do {
                return try await handle.openStream(label: PixelHandStream.mirror)
            } catch {
                DeckHandLog.app.error("Mirror: couldn't open the binary stream: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        opening = task
        let opened = await task.value
        opening = nil
        stream = opened
        if opened != nil {
            // A fresh stream on the remote: resend pointer images.
            sentShapes.removeAll()
            cursorThrottle.reset()
            formatChangedPending = true
            loggedSendFailure = false
        }
        return opened != nil
    }

    /// Closes the binary stream. The remote treats a closed stream as
    /// "mirror stopped".
    func close() async {
        opening?.cancel()
        opening = nil
        guard let stream else { return }
        self.stream = nil
        pendingCursor = nil
        pendingShapes = Data()
        try? await stream.close()
    }

    /// The next frame starts a new picture (display or size changed).
    func markFormatChanged() {
        formatChangedPending = true
    }

    // MARK: Video

    /// Sends one JPEG frame unless this remote's previous one is still on
    /// the wire. Returns `false` when the frame was dropped.
    @discardableResult
    func sendFrame(jpeg: Data, presentationTimeMicros: UInt64) -> Bool {
        guard let stream, !frameInFlight else {
            counter.noteDropped()
            return false
        }
        var flags: BinaryFrameHeader.Flags = []
        if formatChangedPending {
            flags.insert(.formatChanged)
            formatChangedPending = false
        }
        let frame = BinaryFrameHeader.frame(
            kind: .jpeg,
            flags: flags,
            seq: nextSeq(),
            presentationTimeMicros: presentationTimeMicros,
            payload: jpeg
        )
        frameInFlight = true
        counter.noteFrameOut(bytes: frame.count)
        Task { @MainActor [weak self] in
            do {
                try await stream.send(frame)
            } catch {
                self?.sendFailed(error)
            }
            self?.frameInFlight = false
        }
        return true
    }

    // MARK: Cursor

    /// Sends the pointer's state, preceded by its image the first time this
    /// stream sees that shape.
    func sendCursor(_ state: MirrorCursorState, shape: MirrorCursorShape?, presentationTimeMicros: UInt64) {
        guard stream != nil else { return }
        var shapeBytes = Data()
        if let shape, shape.id == state.shapeID, !sentShapes.contains(shape.id) {
            sentShapes.insert(shape.id)
            shapeBytes = BinaryFrameHeader.frame(
                kind: .cursorShape,
                seq: nextSeq(),
                presentationTimeMicros: presentationTimeMicros,
                payload: shape.encoded()
            )
        }
        let stateBytes = BinaryFrameHeader.frame(
            kind: .cursor,
            seq: nextSeq(),
            presentationTimeMicros: presentationTimeMicros,
            payload: state.encoded()
        )
        if cursorInFlight {
            pendingShapes.append(shapeBytes)
            pendingCursor = stateBytes
            return
        }
        sendCursorBytes(shapeBytes + stateBytes)
    }

    private func sendCursorBytes(_ bytes: Data) {
        guard let stream else { return }
        cursorInFlight = true
        Task { @MainActor [weak self] in
            do {
                try await stream.send(bytes)
            } catch {
                self?.sendFailed(error)
            }
            guard let self else { return }
            self.cursorInFlight = false
            if let next = self.pendingCursor {
                let shapes = self.pendingShapes
                self.pendingCursor = nil
                self.pendingShapes = Data()
                self.sendCursorBytes(shapes + next)
            }
        }
    }

    // MARK: Helpers

    private func nextSeq() -> UInt64 {
        seq &+= 1
        return seq
    }

    private func sendFailed(_ error: Error) {
        guard !loggedSendFailure else { return }
        loggedSendFailure = true
        DeckHandLog.app.error("Mirror: send to a remote failed: \(error.localizedDescription, privacy: .public)")
    }
}
