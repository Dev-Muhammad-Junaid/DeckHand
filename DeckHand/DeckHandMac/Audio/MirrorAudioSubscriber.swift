//
//  MirrorAudioSubscriber.swift
//  DeckHandMac
//
//  One remote listening to the Mac's sound (S17): its audio Loom stream
//  (`PixelHandStream.audio`), its send queue and its stats window.
//
//  Send policy (`MirrorAudioSendQueue`): one send on the wire at a time;
//  packets that arrive meanwhile wait and go out together; at most four
//  wait (~85 ms), and a newer packet pushes the oldest out. The remote
//  sees the gap in the sequence numbers. A slow link costs a dropout,
//  never a growing delay. The format frame is never dropped: it goes ahead
//  of the next batch whenever it changed.
//

import Foundation
import Loom
import LoomKit

@MainActor
final class MirrorAudioSubscriber {
    let id: UUID
    let handle: LoomConnectionHandle

    /// This remote's audio stats window.
    var counter = MirrorAudioHostCounter()
    /// The codec this remote was last sent.
    private(set) var codec: MirrorAudioCodec?

    private var stream: LoomMultiplexedStream?
    private var opening: Task<LoomMultiplexedStream?, Never>?
    private var queue = MirrorAudioSendQueue<Data>()
    private var sentFormat: MirrorAudioFormat?
    private var pendingFormat: Data?
    private var seq: UInt64 = 0
    private var loggedSendFailure = false

    init(id: UUID, handle: LoomConnectionHandle) {
        self.id = id
        self.handle = handle
    }

    var isOpen: Bool { stream != nil }

    /// Opens this remote's audio stream if it isn't open. Returns whether
    /// it is open.
    @discardableResult
    func open() async -> Bool {
        if stream != nil { return true }
        if let opening { return await opening.value != nil }
        let handle = handle
        let task = Task<LoomMultiplexedStream?, Never> {
            do {
                return try await handle.openStream(label: PixelHandStream.audio)
            } catch {
                DeckHandLog.app.error("Mirror audio: couldn't open the audio stream: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        opening = task
        let opened = await task.value
        opening = nil
        stream = opened
        if opened != nil {
            // A fresh stream on the remote: it needs the format first.
            sentFormat = nil
            pendingFormat = nil
            queue.removeAll()
            loggedSendFailure = false
        }
        return opened != nil
    }

    /// Closes the audio stream; the remote stops playing.
    func close() async {
        opening?.cancel()
        opening = nil
        guard let stream else { return }
        self.stream = nil
        queue.removeAll()
        pendingFormat = nil
        try? await stream.close()
    }

    /// Queues one packet, preceded by the format when this stream hasn't
    /// had it yet.
    func send(_ packet: MirrorAudioPacket, format: MirrorAudioFormat, presentationTimeMicros: UInt64) {
        guard stream != nil else { return }
        if sentFormat != format {
            sentFormat = format
            codec = format.codec
            pendingFormat = BinaryFrameHeader.frame(
                kind: .audioFormat,
                seq: nextSeq(),
                presentationTimeMicros: presentationTimeMicros,
                payload: format.encoded()
            )
        }
        queue.enqueue(BinaryFrameHeader.frame(
            kind: .audioPacket,
            seq: nextSeq(),
            presentationTimeMicros: presentationTimeMicros,
            payload: packet.encoded()
        ))
        counter.noteDropped(queue.takeDropped())
        pump()
    }

    /// The stats window, or `nil` before the first packet.
    func takeStats(elapsed: Double) -> MirrorAudioHostStats? {
        guard let codec else { return nil }
        return counter.take(codec: codec, elapsed: elapsed)
    }

    private func pump() {
        guard let stream, let batch = queue.takeBatch() else { return }
        var bytes = pendingFormat ?? Data()
        pendingFormat = nil
        for frame in batch { bytes.append(frame) }
        counter.noteSent(packets: batch.count, bytes: bytes.count)
        Task { @MainActor [weak self] in
            do {
                try await stream.send(bytes)
            } catch {
                self?.sendFailed(error)
            }
            guard let self else { return }
            self.queue.sendFinished()
            self.pump()
        }
    }

    private func nextSeq() -> UInt64 {
        seq &+= 1
        return seq
    }

    private func sendFailed(_ error: Error) {
        guard !loggedSendFailure else { return }
        loggedSendFailure = true
        DeckHandLog.app.error("Mirror audio: send to a remote failed: \(error.localizedDescription, privacy: .public)")
    }
}
