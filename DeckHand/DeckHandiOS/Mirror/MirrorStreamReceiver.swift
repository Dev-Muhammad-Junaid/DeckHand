//
//  MirrorStreamReceiver.swift
//  DeckHandiOS
//
//  Reads the Mac's binary mirror stream (`PixelHandStream.mirror`) for one
//  connection. This is the mirror's own reader: the control stream still
//  has exactly one reader, `ControlSessionModel.listenForHostMessages`.
//
//  The Mac opens a mirror stream when a mirror starts and closes it when it
//  stops, so a session can see several over its life; each is drained in
//  its own task. Every stream is drained to the end even while the mirror
//  is hidden, so Loom's receive buffer never fills.
//
//  Video is newest-frame-wins: the reader drops each JPEG in a one-slot
//  mailbox and a single decoder takes the newest one, off the main actor.
//  A slow decode shows fewer frames, never older ones. Cursor updates skip
//  the mailbox and go straight to the main actor; they are tiny.
//

import Foundation
import LoomKit
import UIKit

/// Where decoded mirror output goes. The session model implements it.
@MainActor
protocol MirrorStreamSink: AnyObject, Sendable {
    func mirrorDidDecode(_ image: UIImage, header: BinaryFrameHeader)
    func mirrorCursorDidChange(_ state: MirrorCursorState)
    func mirrorDidReceiveCursorShape(_ shape: MirrorCursorShape, image: UIImage)
}

/// The remote's half of the stats window, shared by the reader, the decoder
/// and the main actor.
final class MirrorClientStatsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var counter = MirrorStatsCounter()

    func update(_ body: (inout MirrorStatsCounter) -> Void) {
        lock.lock()
        body(&counter)
        lock.unlock()
    }

    /// The window's stats, starting a new window.
    func takeStats(elapsed: Double) -> MirrorClientStats {
        lock.lock()
        defer { lock.unlock() }
        let stats = counter.clientStats(elapsed: elapsed)
        counter.reset()
        return stats
    }
}

struct MirrorStreamReceiver: Sendable {
    /// A JPEG waiting for the decoder.
    private struct PendingFrame: Sendable {
        let header: BinaryFrameHeader
        let jpeg: Data
    }

    let stats: MirrorClientStatsBox

    /// Runs until the session ends or the task is cancelled.
    func run(connection: LoomConnectionHandle, sink: MirrorStreamSink) async {
        let session = await connection.session
        let mailbox = MirrorFrameMailbox<PendingFrame>()
        // One wake-up is enough: the decoder empties the mailbox each time.
        let (wakeups, wake) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let stats = stats

        await withTaskGroup(of: Void.self) { group in
            // Decoder: newest frame only, off the main actor.
            group.addTask {
                for await _ in wakeups {
                    while let frame = mailbox.take() {
                        let started = CACurrentMediaTime()
                        guard let image = UIImage(data: frame.jpeg)?.preparingForDisplay() else { continue }
                        let seconds = CACurrentMediaTime() - started
                        stats.update {
                            $0.noteWork(seconds: seconds)
                            $0.noteFrameOut()
                        }
                        await sink.mirrorDidDecode(image, header: frame.header)
                    }
                    stats.update { $0.noteDropped(mailbox.takeReplacedCount()) }
                }
            }

            // Readers: one per mirror stream the Mac opens.
            for await stream in session.makeIncomingStreamObserver() {
                guard stream.label == PixelHandStream.mirror else { continue }
                group.addTask {
                    await Self.read(stream, mailbox: mailbox, wake: wake, stats: stats, sink: sink)
                }
            }
            wake.finish()
        }
    }

    private static func read(
        _ stream: LoomMultiplexedStream,
        mailbox: MirrorFrameMailbox<PendingFrame>,
        wake: AsyncStream<Void>.Continuation,
        stats: MirrorClientStatsBox,
        sink: MirrorStreamSink
    ) async {
        var reader = BinaryFrameReader()
        var loggedFailure = false
        for await bytes in stream.incomingBytes {
            let frames: [BinaryFrameReader.Frame]
            do {
                frames = try reader.append(bytes)
            } catch {
                // A framing error can't be resynchronised. Keep draining so
                // Loom's buffer doesn't fill, but ignore what follows.
                if !loggedFailure {
                    loggedFailure = true
                    DeckHandLog.connection.error("Mirror stream framing error: \(String(describing: error), privacy: .public)")
                }
                continue
            }
            for frame in frames {
                switch frame.header.kind {
                case .jpeg:
                    stats.update { $0.noteFrameIn(bytes: frame.payload.count) }
                    mailbox.put(PendingFrame(header: frame.header, jpeg: frame.payload))
                    wake.yield()

                case .cursor:
                    guard let state = try? MirrorCursorState.decode(frame.payload) else { continue }
                    await sink.mirrorCursorDidChange(state)

                case .cursorShape:
                    guard let shape = try? MirrorCursorShape.decode(frame.payload),
                          let image = UIImage(data: shape.png) else { continue }
                    await sink.mirrorDidReceiveCursorShape(shape, image: image)

                case .hevcParameterSets, .hevcKeyFrame, .hevcDeltaFrame:
                    // S5: not sent by this build's Mac.
                    continue
                }
            }
        }
    }
}
