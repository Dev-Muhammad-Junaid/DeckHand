//
//  MirrorCursorTests.swift
//  PixelHandCoreTests
//
//  S3: the cursor payloads on the binary mirror stream, the geometry that
//  places the pointer over the mirror, and the Mac's send throttle.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct MirrorCursorStateTests {
    @Test("The cursor payload is 18 big-endian bytes in the documented layout")
    func layoutIsPinned() {
        let state = MirrorCursorState(x: 0.5, y: 0.25, shapeID: 0x0102_0304, displayID: 0x0A0B_0C0D, isOnMirroredDisplay: true, isHidden: true)
        let bytes = [UInt8](state.encoded())
        #expect(bytes.count == MirrorCursorState.byteCount)
        #expect(Array(bytes[0..<4]) == [0x3F, 0x00, 0x00, 0x00]) // 0.5
        #expect(Array(bytes[4..<8]) == [0x3E, 0x80, 0x00, 0x00]) // 0.25
        #expect(Array(bytes[8..<12]) == [1, 2, 3, 4])
        #expect(Array(bytes[12..<16]) == [0x0A, 0x0B, 0x0C, 0x0D])
        #expect(bytes[16] == 0b11)
        #expect(bytes[17] == 0)
    }

    @Test("States round-trip, including off-display and hidden ones")
    func roundTrip() throws {
        let states = [
            MirrorCursorState(x: 0.125, y: 0.875, shapeID: 7, displayID: 1, isOnMirroredDisplay: true, isHidden: false),
            MirrorCursorState(x: -0.5, y: 1.5, shapeID: 0, displayID: 2, isOnMirroredDisplay: false, isHidden: false),
            MirrorCursorState(x: 0, y: 0, shapeID: 9, displayID: 0, isOnMirroredDisplay: true, isHidden: true),
        ]
        for state in states {
            #expect(try MirrorCursorState.decode(state.encoded()) == state)
        }
        #expect(states[0].isVisibleInMirror)
        #expect(!states[1].isVisibleInMirror)
        #expect(!states[2].isVisibleInMirror)
    }

    @Test("A short payload is refused; a non-finite position reads as hidden")
    func hostileInput() throws {
        let state = MirrorCursorState(x: 0.5, y: 0.5, shapeID: 1, displayID: 1, isOnMirroredDisplay: true, isHidden: false)
        #expect(throws: MirrorPayloadError.truncated(needed: 18, available: 17)) {
            try MirrorCursorState.decode(state.encoded().prefix(17))
        }
        var bytes = [UInt8](state.encoded())
        bytes[0..<4] = [0x7F, 0xC0, 0x00, 0x00] // NaN
        let decoded = try MirrorCursorState.decode(Data(bytes))
        #expect(decoded.x == 0 && decoded.y == 0)
        #expect(!decoded.isVisibleInMirror)
    }
}

@Suite struct MirrorCursorShapeTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    @Test("Shapes round-trip with their image")
    func roundTrip() throws {
        let shape = MirrorCursorShape(id: 42, hotSpotX: 4, hotSpotY: 4.5, width: 17, height: 23, png: png)
        let encoded = shape.encoded()
        #expect(encoded.count == MirrorCursorShape.headerByteCount + png.count)
        #expect(try MirrorCursorShape.decode(encoded) == shape)
        // A slice that doesn't start at index 0 decodes the same.
        #expect(try MirrorCursorShape.decode((Data([0xEE]) + encoded).dropFirst()) == shape)
    }

    @Test("Ids are stable, never 0, and change with the image or the hot spot")
    func ids() {
        let a = MirrorCursorShape.makeID(png: png, hotSpotX: 4, hotSpotY: 4)
        #expect(a == MirrorCursorShape.makeID(png: png, hotSpotX: 4, hotSpotY: 4))
        #expect(a != 0)
        #expect(a != MirrorCursorShape.makeID(png: png + Data([0]), hotSpotX: 4, hotSpotY: 4))
        #expect(a != MirrorCursorShape.makeID(png: png, hotSpotX: 5, hotSpotY: 4))
        #expect(MirrorCursorShape.makeID(png: Data(), hotSpotX: 0, hotSpotY: 0) != 0)
    }

    @Test("Empty, oversize, zero-id and nonsense shapes are refused")
    func hostileInput() {
        func encoded(id: UInt32 = 1, w: Double = 16, h: Double = 16, png: Data? = nil) -> Data {
            MirrorCursorShape(id: id, hotSpotX: 1, hotSpotY: 1, width: w, height: h, png: png ?? self.png).encoded()
        }
        #expect(throws: MirrorPayloadError.truncated(needed: 20, available: 19)) {
            try MirrorCursorShape.decode(encoded().prefix(19))
        }
        #expect(throws: MirrorPayloadError.invalid("empty cursor image")) {
            try MirrorCursorShape.decode(encoded(png: Data()))
        }
        let big = Data(count: MirrorCursorShape.maxImageBytes + 1)
        #expect(throws: MirrorPayloadError.tooLarge(big.count)) {
            try MirrorCursorShape.decode(encoded(png: big))
        }
        #expect(throws: MirrorPayloadError.invalid("cursor shape id 0")) {
            try MirrorCursorShape.decode(encoded(id: 0))
        }
        #expect(throws: MirrorPayloadError.invalid("cursor shape geometry")) {
            try MirrorCursorShape.decode(encoded(w: 0))
        }
        #expect(throws: MirrorPayloadError.invalid("cursor shape geometry")) {
            try MirrorCursorShape.decode(encoded(h: .infinity))
        }
        #expect(throws: MirrorPayloadError.invalid("cursor shape geometry")) {
            try MirrorCursorShape.decode(encoded(w: 5_000))
        }
    }

    @Test("The cache keeps the most recent shapes")
    func cache() {
        var cache = MirrorCursorShapeCache<String>(capacity: 2)
        func shape(_ id: UInt32) -> MirrorCursorShape {
            MirrorCursorShape(id: id, hotSpotX: 0, hotSpotY: 0, width: 1, height: 1, png: png)
        }
        cache.insert(shape(1), image: "one")
        cache.insert(shape(2), image: "two")
        cache.insert(shape(1), image: "one again") // refreshes 1
        cache.insert(shape(3), image: "three")     // evicts 2
        #expect(cache.count == 2)
        #expect(cache.entry(for: 1)?.image == "one again")
        #expect(cache.entry(for: 2) == nil)
        #expect(cache.entry(for: 3)?.image == "three")
        cache.removeAll()
        #expect(cache.count == 0)
    }
}

@Suite struct MirrorCursorGeometryTests {
    private let main = MirrorRect(x: 0, y: 0, width: 1512, height: 982)
    /// A second display to the left of the main one, top-aligned.
    private let left = MirrorRect(x: -1920, y: 0, width: 1920, height: 1080)

    @Test("Global points map to 0…1 on their display; the far edges belong to the next display")
    func normalize() {
        let centre = MirrorCursorGeometry.normalized(x: 756, y: 491, in: main)
        #expect(centre.x == 0.5 && centre.y == 0.5 && centre.inside)

        let onLeft = MirrorCursorGeometry.normalized(x: -960, y: 540, in: left)
        #expect(onLeft.x == 0.5 && onLeft.y == 0.5 && onLeft.inside)

        #expect(MirrorCursorGeometry.normalized(x: 0, y: 0, in: main).inside)
        #expect(!MirrorCursorGeometry.normalized(x: 1512, y: 10, in: main).inside)
        #expect(!MirrorCursorGeometry.normalized(x: -1, y: 10, in: main).inside)
        #expect(!MirrorCursorGeometry.normalized(x: .nan, y: 10, in: main).inside)
        #expect(!MirrorCursorGeometry.normalized(x: 1, y: 1, in: MirrorRect(x: 0, y: 0, width: 0, height: 0)).inside)
    }

    @Test("The display under a point is found among several")
    func displayUnderPoint() {
        let displays: [(id: UInt32, bounds: MirrorRect)] = [(1, main), (2, left)]
        #expect(MirrorCursorGeometry.display(containingX: 100, y: 100, in: displays) == 1)
        #expect(MirrorCursorGeometry.display(containingX: -100, y: 100, in: displays) == 2)
        #expect(MirrorCursorGeometry.display(containingX: -100, y: 2_000, in: displays) == nil)
    }

    @Test("The pointer scales with the mirror, within limits")
    func scale() {
        #expect(MirrorCursorGeometry.spriteScale(displayPointWidth: 1000, viewWidth: 800) == 0.8)
        #expect(MirrorCursorGeometry.spriteScale(displayPointWidth: 1512, viewWidth: 200) == MirrorCursorGeometry.minimumSpriteScale)
        #expect(MirrorCursorGeometry.spriteScale(displayPointWidth: 800, viewWidth: 2400) == MirrorCursorGeometry.maximumSpriteScale)
        #expect(MirrorCursorGeometry.spriteScale(displayPointWidth: 0, viewWidth: 100) == 1)
    }

    @Test("The hot spot lands on the pointer's position")
    func spriteFrame() {
        let state = MirrorCursorState(x: 0.5, y: 0.25, shapeID: 1, displayID: 1, isOnMirroredDisplay: true, isHidden: false)
        let shape = MirrorCursorShape(id: 1, hotSpotX: 4, hotSpotY: 6, width: 20, height: 30, png: Data([1]))
        let frame = MirrorCursorGeometry.spriteFrame(state: state, shape: shape, displayPointWidth: 1000, viewWidth: 800, viewHeight: 500)
        // Scale 0.8: hot spot (3.2, 4.8) sits on (400, 125).
        #expect(abs(frame.x - (400 - 3.2)) < 1e-9)
        #expect(abs(frame.y - (125 - 4.8)) < 1e-9)
        #expect(abs(frame.width - 16) < 1e-9)
        #expect(abs(frame.height - 24) < 1e-9)
    }
}

@Suite struct MirrorCursorThrottleTests {
    private func state(x: Double = 0.5, shape: UInt32 = 1, display: UInt32 = 1, on: Bool = true) -> MirrorCursorState {
        MirrorCursorState(x: x, y: 0.5, shapeID: shape, displayID: display, isOnMirroredDisplay: on, isHidden: false)
    }

    @Test("The first state always goes; a still pointer refreshes once a second")
    func stillPointer() {
        var throttle = MirrorCursorThrottle()
        do { let r = throttle.shouldSend(state(), now: 0); #expect(r) }
        do { let r = throttle.shouldSend(state(), now: 0.5); #expect(!r) }
        do { let r = throttle.shouldSend(state(), now: 1.0); #expect(r) }
    }

    @Test("Movement is capped at 60 a second; tiny jitter waits for the refresh")
    func movement() {
        var throttle = MirrorCursorThrottle()
        do { let r = throttle.shouldSend(state(x: 0.1), now: 0); #expect(r) }
        do { let r = throttle.shouldSend(state(x: 0.2), now: 0.005); #expect(!r) }
        do { let r = throttle.shouldSend(state(x: 0.2), now: 0.02); #expect(r) }
        do { let r = throttle.shouldSend(state(x: 0.20001), now: 0.1); #expect(!r) }
    }

    @Test("Shape, display and visibility changes go at once")
    func structuralChanges() {
        var throttle = MirrorCursorThrottle()
        do { let r = throttle.shouldSend(state(), now: 0); #expect(r) }
        do { let r = throttle.shouldSend(state(shape: 2), now: 0.001); #expect(r) }
        do { let r = throttle.shouldSend(state(shape: 2, display: 2, on: false), now: 0.002); #expect(r) }
        throttle.reset()
        do { let r = throttle.shouldSend(state(shape: 2, display: 2, on: false), now: 0.003); #expect(r) }
    }
}
