//
//  MirrorAudioReceiver.swift
//  DeckHandiOS
//
//  S17: reads the Mac's audio streams (`PixelHandStream.audio`) for one
//  connection and hands formats and packets to the player. The control
//  stream still has exactly one reader (`ControlSessionModel`), and the
//  mirror's video stream has its own (`MirrorStreamReceiver`).
//
//  The Mac opens an audio stream when audio is turned on and closes it
//  when audio or the mirror stops, so a session can see several; each is
//  drained to its end in its own task, so Loom's receive buffer never
//  fills. Packets before the first valid format are ignored.
//

import Foundation
import LoomKit

/// Where the audio stream's contents go (`MirrorAudioPlayer`). Called from
/// the reader's task, never the main actor; `stream` tells overlapping
/// streams apart.
protocol MirrorAudioSink: AnyObject, Sendable {
    func audioFormatArrived(_ format: MirrorAudioFormat, stream: ObjectIdentifier)
    func audioPacketArrived(_ packet: MirrorAudioPacket, arrival: Double, stream: ObjectIdentifier)
    func audioStreamEnded(stream: ObjectIdentifier)
}

struct MirrorAudioReceiver: Sendable {
    /// Runs until the session ends or the task is cancelled.
    func run(connection: LoomConnectionHandle, sink: any MirrorAudioSink) async {
        let session = await connection.session
        await withTaskGroup(of: Void.self) { group in
            for await stream in session.makeIncomingStreamObserver() {
                guard stream.label == PixelHandStream.audio else { continue }
                group.addTask {
                    await Self.read(stream, sink: sink)
                }
            }
        }
    }

    private static func read(_ stream: LoomMultiplexedStream, sink: any MirrorAudioSink) async {
        let id = ObjectIdentifier(stream)
        var reader = BinaryFrameReader()
        var hasFormat = false
        var loggedFailure = false
        for await bytes in stream.incomingBytes {
            let frames: [BinaryFrameReader.Frame]
            do {
                frames = try reader.append(bytes)
            } catch {
                // Can't resynchronise: keep draining, ignore the rest.
                if !loggedFailure {
                    loggedFailure = true
                    DeckHandLog.connection.error("Mirror audio framing error: \(String(describing: error), privacy: .public)")
                }
                continue
            }
            for frame in frames {
                switch frame.header.kind {
                case .audioFormat:
                    do {
                        let format = try MirrorAudioFormat.decode(frame.payload)
                        hasFormat = true
                        sink.audioFormatArrived(format, stream: id)
                    } catch {
                        hasFormat = false
                        DeckHandLog.connection.error("Mirror audio: unusable format: \(String(describing: error), privacy: .public)")
                    }

                case .audioPacket:
                    guard hasFormat, let packet = try? MirrorAudioPacket.decode(frame.payload) else { continue }
                    sink.audioPacketArrived(packet, arrival: ProcessInfo.processInfo.systemUptime, stream: id)

                case .jpeg, .hevcParameterSets, .hevcKeyFrame, .hevcDeltaFrame, .cursor, .cursorShape:
                    continue // video kinds belong on the mirror stream
                }
            }
        }
        sink.audioStreamEnded(stream: id)
    }
}
