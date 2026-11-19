//
//  MirrorStreamTests.swift
//  PixelHandCoreTests
//
//  The binary mirror stream's reader and receive mailbox, S6 stats, and the
//  remote's display picker logic.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct BinaryFrameReaderTests {
    private func frame(_ seq: UInt64, kind: BinaryFrameHeader.Kind = .jpeg, size: Int = 5) -> Data {
        BinaryFrameHeader.frame(kind: kind, seq: seq, presentationTimeMicros: seq * 1_000, payload: Data(repeating: UInt8(seq), count: size))
    }

    @Test("One payload per frame, as Loom delivers them")
    func wholeFrames() throws {
        var reader = BinaryFrameReader()
        let first = try reader.append(frame(1))
        #expect(first.map(\.header.seq) == [1])
        #expect(first.first?.payload == Data(repeating: 1, count: 5))
        do { let r = try reader.append(frame(2, kind: .cursor)); #expect(r.map(\.header.kind) == [.cursor]) }
        #expect(reader.bufferedByteCount == 0)
    }

    @Test("Split and joined payloads still give whole frames, in order")
    func splitAndJoined() throws {
        var reader = BinaryFrameReader()
        let bytes = frame(1) + frame(2, size: 0) + frame(3, size: 40)
        var seqs: [UInt64] = []
        // Feed in 7-byte pieces.
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let end = min(index + 7, bytes.endIndex)
            seqs += try reader.append(Data(bytes[index..<end])).map(\.header.seq)
            index = end
        }
        #expect(seqs == [1, 2, 3])
        #expect(reader.bufferedByteCount == 0)
    }

    @Test("A framing error fails the reader for good")
    func failure() throws {
        var reader = BinaryFrameReader()
        var bad = [UInt8](frame(1))
        bad[0] = 0
        #expect(throws: BinaryFrameHeader.DecodeError.badMagic) { try reader.append(Data(bad)) }
        #expect(reader.failure == .badMagic)
        #expect(throws: BinaryFrameHeader.DecodeError.badMagic) { try reader.append(frame(2)) }
    }

    @Test("The cursor kinds are part of the header's kinds")
    func cursorKinds() throws {
        #expect(BinaryFrameHeader.Kind.cursor.rawValue == 5)
        #expect(BinaryFrameHeader.Kind.cursorShape.rawValue == 6)
        let state = MirrorCursorState(x: 0.5, y: 0.5, shapeID: 3, displayID: 1, isOnMirroredDisplay: true, isHidden: false)
        let data = BinaryFrameHeader.frame(kind: .cursor, seq: 1, presentationTimeMicros: 0, payload: state.encoded())
        let (header, payload) = try BinaryFrameHeader.decodeFrame(data)
        #expect(header.kind == .cursor)
        #expect(try MirrorCursorState.decode(payload) == state)
    }
}

@Suite struct MirrorFrameMailboxTests {
    @Test("The newest value wins and replaced values are counted")
    func newestWins() {
        let mailbox = MirrorFrameMailbox<Int>()
        #expect(mailbox.take() == nil)
        #expect(!mailbox.put(1))
        #expect(mailbox.put(2))
        #expect(mailbox.put(3))
        #expect(mailbox.take() == 3)
        #expect(mailbox.take() == nil)
        #expect(mailbox.takeReplacedCount() == 2)
        #expect(mailbox.takeReplacedCount() == 0)
        mailbox.put(4)
        mailbox.clear()
        #expect(mailbox.take() == nil)
    }

    @Test("Concurrent puts and takes never lose the last value")
    func concurrent() async {
        let mailbox = MirrorFrameMailbox<Int>()
        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<4 {
                group.addTask {
                    for i in 0..<500 { mailbox.put(writer * 1_000 + i) }
                }
            }
            group.addTask {
                for _ in 0..<500 { _ = mailbox.take() }
            }
        }
        mailbox.put(-1)
        #expect(mailbox.take() == -1)
    }
}

@Suite struct MirrorStatsTests {
    @Test("A window's counts become per-second rates, rounded to one decimal")
    func hostRates() {
        var counter = MirrorStatsCounter()
        for _ in 0..<40 { counter.noteFrameIn() }
        for _ in 0..<39 { counter.noteFrameOut(bytes: 25_000) }
        counter.noteDropped()
        counter.noteWork(seconds: 0.004)
        counter.noteWork(seconds: 0.006)
        counter.noteWork(seconds: .nan) // ignored
        let stats = counter.hostStats(codec: .jpeg, width: 1440, height: 900, elapsed: 2)
        #expect(stats.capturedFPS == 20)
        #expect(stats.sentFPS == 19.5)
        #expect(stats.droppedFrames == 1)
        #expect(stats.encodeMilliseconds == 5)
        #expect(stats.kilobitsPerSecond == 3_900) // 975 000 B × 8 / 2 s
        counter.reset()
        #expect(counter == MirrorStatsCounter())
    }

    @Test("The remote's window reports received and displayed separately")
    func clientRates() {
        var counter = MirrorStatsCounter()
        for _ in 0..<10 { counter.noteFrameIn(bytes: 1_000) }
        for _ in 0..<8 { counter.noteFrameOut() }
        counter.noteDropped(2)
        let stats = counter.clientStats(elapsed: 1)
        #expect(stats.receivedFPS == 10)
        #expect(stats.displayedFPS == 8)
        #expect(stats.droppedFrames == 2)
        #expect(stats.decodeMilliseconds == 0)
        #expect(stats.kilobitsPerSecond == 80)
    }

    @Test("A remote's stats are made safe before the Mac logs them")
    func sanitize() {
        let hostile = MirrorClientStats(receivedFPS: .infinity, displayedFPS: -5, droppedFrames: -1, decodeMilliseconds: .nan, kilobitsPerSecond: 1e300)
        let safe = hostile.sanitized()
        #expect(safe.receivedFPS == 0)
        #expect(safe.displayedFPS == 0)
        #expect(safe.droppedFrames == 0)
        #expect(safe.decodeMilliseconds == 0)
        #expect(safe.kilobitsPerSecond == 10_000_000)
        let message = ControlMessage.diagnostics(.mirrorClientStats(stats: hostile))
        #expect(RemoteInputValidation.sanitize(message) == .diagnostics(.mirrorClientStats(stats: safe)))
    }

    @Test("The stats line reads the same on both ends")
    func line() {
        let host = MirrorHostStats(codec: .jpeg, width: 1440, height: 900, capturedFPS: 20, sentFPS: 20, droppedFrames: 3, encodeMilliseconds: 6.1, kilobitsPerSecond: 1_234)
        let client = MirrorClientStats(receivedFPS: 19.8, displayedFPS: 19.8, droppedFrames: 0, decodeMilliseconds: 4, kilobitsPerSecond: 1_200)
        #expect(MirrorStatsLine.text(host: host, client: client)
            == "JPEG 1440×900 · Mac 20 fps, 6.1 ms, 1.2 Mb/s, 3 dropped · iPad 20 fps, 4.0 ms")
        let quiet = MirrorHostStats(codec: .hevc, width: 640, height: 400, capturedFPS: 5, sentFPS: 5, droppedFrames: 0, encodeMilliseconds: 12.4, kilobitsPerSecond: 300.4)
        #expect(MirrorStatsLine.text(host: quiet, client: nil) == "HEVC 640×400 · Mac 5.0 fps, 12 ms, 300 kb/s")
        #expect(MirrorStatsLine.text(host: nil, client: nil) == "Waiting for stats…")
        #expect(MirrorStatsLine.text(host: nil, client: MirrorClientStats(receivedFPS: 3, displayedFPS: 2.5, droppedFrames: 1, decodeMilliseconds: 0.25, kilobitsPerSecond: 0), clientName: "iPhone")
            == "iPhone 2.5 fps, 0.3 ms, 1 skipped")
    }
}

@Suite struct MirrorDisplayPickerTests {
    private let builtIn = DisplayInfo(displayID: 1, name: "Built-in Retina Display", isMain: true, width: 1512, height: 982)
    private let studio = DisplayInfo(displayID: 2, name: "Studio Display", isMain: false, width: 2560, height: 1440)

    @Test("The picker shows only with more than one display")
    func picker() {
        #expect(!MirrorDisplayChrome.make(displays: [builtIn], mirroredDisplayID: 1, cursorDisplayID: 1, followsCursor: false).showsPicker)
        #expect(MirrorDisplayChrome.make(displays: [builtIn, studio], mirroredDisplayID: 1, cursorDisplayID: 1, followsCursor: false).showsPicker)
    }

    @Test("The badge names the cursor's display when it isn't the mirrored one")
    func badge() {
        let displays = [builtIn, studio]
        #expect(MirrorDisplayChrome.make(displays: displays, mirroredDisplayID: 1, cursorDisplayID: 2, followsCursor: false).cursorElsewhere == studio)
        #expect(MirrorDisplayChrome.make(displays: displays, mirroredDisplayID: 2, cursorDisplayID: 2, followsCursor: false).cursorElsewhere == nil)
        // Following the cursor: the mirror is about to switch, no badge.
        #expect(MirrorDisplayChrome.make(displays: displays, mirroredDisplayID: 1, cursorDisplayID: 2, followsCursor: true).cursorElsewhere == nil)
        // Unknown or unlisted displays: no badge.
        #expect(MirrorDisplayChrome.make(displays: displays, mirroredDisplayID: 1, cursorDisplayID: 0, followsCursor: false).cursorElsewhere == nil)
        #expect(MirrorDisplayChrome.make(displays: displays, mirroredDisplayID: 1, cursorDisplayID: 9, followsCursor: false).cursorElsewhere == nil)
        #expect(MirrorDisplayChrome.make(displays: displays, mirroredDisplayID: nil, cursorDisplayID: 2, followsCursor: false).cursorElsewhere == nil)
    }

    @Test("Follow cursor switches after the pointer dwells, then cools down")
    func follow() {
        var follower = MirrorDisplayFollower()
        let known: Set<UInt32> = [1, 2]
        do { let r = follower.update(cursorDisplayID: 2, mirroredDisplayID: 1, knownDisplayIDs: known, now: 0); #expect(r == nil) }
        do { let r = follower.update(cursorDisplayID: 2, mirroredDisplayID: 1, knownDisplayIDs: known, now: 0.2); #expect(r == nil) }
        do { let r = follower.update(cursorDisplayID: 2, mirroredDisplayID: 1, knownDisplayIDs: known, now: 0.4); #expect(r == 2) }
        // Swept straight back: the cooldown holds it on 2.
        do { let r = follower.update(cursorDisplayID: 1, mirroredDisplayID: 2, knownDisplayIDs: known, now: 0.5); #expect(r == nil) }
        do { let r = follower.update(cursorDisplayID: 1, mirroredDisplayID: 2, knownDisplayIDs: known, now: 0.9); #expect(r == nil) }
        do { let r = follower.update(cursorDisplayID: 1, mirroredDisplayID: 2, knownDisplayIDs: known, now: 1.5); #expect(r == 1) }
    }

    @Test("A pointer that crosses and returns before the dwell doesn't switch")
    func flicker() {
        var follower = MirrorDisplayFollower()
        let known: Set<UInt32> = [1, 2]
        do { let r = follower.update(cursorDisplayID: 2, mirroredDisplayID: 1, knownDisplayIDs: known, now: 0); #expect(r == nil) }
        do { let r = follower.update(cursorDisplayID: 1, mirroredDisplayID: 1, knownDisplayIDs: known, now: 0.2); #expect(r == nil) }
        do { let r = follower.update(cursorDisplayID: 2, mirroredDisplayID: 1, knownDisplayIDs: known, now: 0.3); #expect(r == nil) }
        do { let r = follower.update(cursorDisplayID: 2, mirroredDisplayID: 1, knownDisplayIDs: known, now: 0.5); #expect(r == nil) }
        do { let r = follower.update(cursorDisplayID: 2, mirroredDisplayID: 1, knownDisplayIDs: known, now: 0.7); #expect(r == 2) }
        // Unknown displays are never followed.
        var other = MirrorDisplayFollower()
        do { let r = other.update(cursorDisplayID: 9, mirroredDisplayID: 1, knownDisplayIDs: known, now: 0); #expect(r == nil) }
        do { let r = other.update(cursorDisplayID: 9, mirroredDisplayID: 1, knownDisplayIDs: known, now: 5); #expect(r == nil) }
    }
}
