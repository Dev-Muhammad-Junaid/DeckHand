//
//  BinaryFrameHeaderTests.swift
//  PixelHandCoreTests
//
//  The framing reserved for the binary mirror stream (S5). Pinned now so
//  the mirror lane builds on a fixed, tested layout.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct BinaryFrameHeaderTests {

    private let sample = BinaryFrameHeader(
        kind: .hevcKeyFrame,
        flags: [.afterDrop, .formatChanged],
        seq: 0x0102_0304_0506_0708,
        presentationTimeMicros: 0x1112_1314_1516_1718,
        payloadLength: 0x0000_0A0B
    )

    @Test("The header is 28 big-endian bytes in the documented layout")
    func layoutIsPinned() {
        let bytes = [UInt8](sample.encoded())
        #expect(bytes.count == BinaryFrameHeader.byteCount)
        #expect(Array(bytes[0..<4]) == Array("PHBF".utf8))
        #expect(bytes[4] == 1)
        #expect(bytes[5] == BinaryFrameHeader.Kind.hevcKeyFrame.rawValue)
        #expect(Array(bytes[6..<8]) == [0x00, 0x03])
        #expect(Array(bytes[8..<16]) == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(Array(bytes[16..<24]) == [0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18])
        #expect(Array(bytes[24..<28]) == [0x00, 0x00, 0x0A, 0x0B])
    }

    @Test("Headers round-trip for every kind")
    func roundTrip() throws {
        for kind in BinaryFrameHeader.Kind.allCases {
            var header = sample
            header.kind = kind
            #expect(try BinaryFrameHeader.decode(header.encoded()) == header)
        }
    }

    @Test("A whole frame splits back into header and payload")
    func frameRoundTrip() throws {
        let payload = Data((0..<300).map { UInt8($0 % 256) })
        let frame = BinaryFrameHeader.frame(kind: .jpeg, seq: 9, presentationTimeMicros: 42, payload: payload)
        let (header, decodedPayload) = try BinaryFrameHeader.decodeFrame(frame)
        #expect(header.kind == .jpeg)
        #expect(header.seq == 9)
        #expect(header.presentationTimeMicros == 42)
        #expect(header.payloadLength == 300)
        #expect(decodedPayload == payload)
        // A slice that doesn't start at index 0 decodes the same.
        let shifted = (Data([0xEE]) + frame).dropFirst()
        #expect(try BinaryFrameHeader.decodeFrame(shifted).payload == payload)
    }

    @Test("Truncated headers and payloads are refused")
    func truncated() {
        let encoded = sample.encoded()
        #expect(throws: BinaryFrameHeader.DecodeError.truncated(needed: 28, available: 27)) {
            try BinaryFrameHeader.decode(encoded.prefix(27))
        }
        #expect(throws: BinaryFrameHeader.DecodeError.truncated(needed: 28, available: 0)) {
            try BinaryFrameHeader.decode(Data())
        }
        let frame = BinaryFrameHeader.frame(kind: .jpeg, seq: 1, presentationTimeMicros: 0, payload: Data(count: 10))
        #expect(throws: BinaryFrameHeader.DecodeError.truncated(needed: 38, available: 37)) {
            try BinaryFrameHeader.decodeFrame(frame.prefix(37))
        }
    }

    @Test("Wrong magic, version or kind is refused")
    func badHeaders() {
        var bytes = [UInt8](sample.encoded())
        bytes[0] = UInt8(ascii: "X")
        #expect(throws: BinaryFrameHeader.DecodeError.badMagic) { try BinaryFrameHeader.decode(Data(bytes)) }

        bytes = [UInt8](sample.encoded())
        bytes[4] = 2
        #expect(throws: BinaryFrameHeader.DecodeError.unsupportedVersion(2)) { try BinaryFrameHeader.decode(Data(bytes)) }

        bytes = [UInt8](sample.encoded())
        bytes[5] = 0
        #expect(throws: BinaryFrameHeader.DecodeError.unknownKind(0)) { try BinaryFrameHeader.decode(Data(bytes)) }
    }

    @Test("A payload length past the cap is refused before allocating")
    func oversizePayload() {
        var header = sample
        header.payloadLength = BinaryFrameHeader.maxPayloadLength + 1
        #expect(throws: BinaryFrameHeader.DecodeError.payloadTooLarge(BinaryFrameHeader.maxPayloadLength + 1)) {
            try BinaryFrameHeader.decode(header.encoded())
        }
    }

    @Test("The mirror stream has its own name, away from the control stream")
    func streamName() {
        #expect(!PixelHandStream.mirror.isEmpty)
        #expect(ProtocolFeature.allCases.contains(.binaryMirrorStream))
    }
}
