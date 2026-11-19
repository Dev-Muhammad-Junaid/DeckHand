//
//  MirrorCursor.swift
//  PixelHandCore
//
//  S3, the local cursor. The Mac captures the mirror without the pointer
//  (`SCStreamConfiguration.showsCursor = false`) and sends where the pointer
//  is and what it looks like on the binary mirror stream. The remote draws
//  the pointer itself, over the video, so it moves at the cursor's rate
//  rather than the video's and stays sharp at any mirror size.
//
//  Two payloads, both big-endian (see `BinaryFrame.swift` for the header):
//
//  `cursor` (`MirrorCursorState`, 18 bytes)
//
//      offset size field
//      0      4    x, Float32: 0…1 across the mirrored display
//      4      4    y, Float32: 0…1 down the mirrored display
//      8      4    shape id (0: no shape known yet)
//      12     4    display the pointer is on (CGDirectDisplayID, 0: unknown)
//      16     1    flags: bit 0 on the mirrored display, bit 1 hidden
//      17     1    reserved, 0
//
//  `cursorShape` (`MirrorCursorShape`, 20 bytes + PNG)
//
//      offset size field
//      0      4    shape id (never 0)
//      4      4    hot spot x, Float32 points from the left
//      8      4    hot spot y, Float32 points from the top
//      12     4    width, Float32 points
//      16     4    height, Float32 points
//      20     n    PNG image
//

import Foundation

/// Where the Mac's pointer is, relative to the mirrored display.
public struct MirrorCursorState: Equatable, Sendable {
    public static let byteCount = 18

    /// 0 at the left edge of the mirrored display, 1 at the right.
    public var x: Double
    /// 0 at the top edge of the mirrored display, 1 at the bottom.
    public var y: Double
    /// The shape to draw (`MirrorCursorShape.id`); 0 when none is known.
    public var shapeID: UInt32
    /// The display the pointer is on, which may not be the mirrored one.
    /// 0 when the Mac couldn't tell.
    public var displayID: UInt32
    /// The pointer is over the mirrored display.
    public var isOnMirroredDisplay: Bool
    /// An app hid the pointer (typing, a full-screen video).
    public var isHidden: Bool

    public init(x: Double, y: Double, shapeID: UInt32, displayID: UInt32, isOnMirroredDisplay: Bool, isHidden: Bool) {
        self.x = x
        self.y = y
        self.shapeID = shapeID
        self.displayID = displayID
        self.isOnMirroredDisplay = isOnMirroredDisplay
        self.isHidden = isHidden
    }

    /// Whether the remote should draw the pointer over the mirror.
    public var isVisibleInMirror: Bool { isOnMirroredDisplay && !isHidden }

    public func encoded() -> Data {
        var data = Data(capacity: Self.byteCount)
        MirrorBytes.append(Float32(x).bitPattern, to: &data)
        MirrorBytes.append(Float32(y).bitPattern, to: &data)
        MirrorBytes.append(shapeID, to: &data)
        MirrorBytes.append(displayID, to: &data)
        var flags: UInt8 = 0
        if isOnMirroredDisplay { flags |= 1 << 0 }
        if isHidden { flags |= 1 << 1 }
        data.append(flags)
        data.append(0)
        return data
    }

    /// Reads a state. Non-finite coordinates (a hostile or broken sender)
    /// read as hidden at the origin rather than failing the stream.
    public static func decode(_ data: Data) throws -> MirrorCursorState {
        let bytes = [UInt8](data)
        guard bytes.count >= byteCount else {
            throw MirrorPayloadError.truncated(needed: byteCount, available: bytes.count)
        }
        let x = Double(Float32(bitPattern: UInt32(MirrorBytes.read(bytes, at: 0, count: 4))))
        let y = Double(Float32(bitPattern: UInt32(MirrorBytes.read(bytes, at: 4, count: 4))))
        let flags = bytes[16]
        let finite = x.isFinite && y.isFinite
        return MirrorCursorState(
            x: finite ? x : 0,
            y: finite ? y : 0,
            shapeID: UInt32(MirrorBytes.read(bytes, at: 8, count: 4)),
            displayID: UInt32(MirrorBytes.read(bytes, at: 12, count: 4)),
            isOnMirroredDisplay: finite && flags & (1 << 0) != 0,
            isHidden: !finite || flags & (1 << 1) != 0
        )
    }
}

/// One pointer image, sent once per stream and cached by `id`.
public struct MirrorCursorShape: Equatable, Sendable {
    public static let headerByteCount = 20
    /// Largest PNG accepted. Real pointers are a few KB; a 256 pt pointer at
    /// 2× is well under this.
    public static let maxImageBytes = 256 * 1024

    public var id: UInt32
    /// The point of the image that is the pointer's tip, in points from the
    /// top-left corner.
    public var hotSpotX: Double
    public var hotSpotY: Double
    /// The image's size in points (the PNG may hold more pixels).
    public var width: Double
    public var height: Double
    public var png: Data

    public init(id: UInt32, hotSpotX: Double, hotSpotY: Double, width: Double, height: Double, png: Data) {
        self.id = id
        self.hotSpotX = hotSpotX
        self.hotSpotY = hotSpotY
        self.width = width
        self.height = height
        self.png = png
    }

    /// A stable id for a pointer image and hot spot: FNV-1a over both,
    /// never 0. The Mac compares ids to notice a shape change and the
    /// remote caches images by them.
    public static func makeID(png: Data, hotSpotX: Double, hotSpotY: Double) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        func mix(_ byte: UInt8) {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        for byte in png { mix(byte) }
        var spot = Data()
        MirrorBytes.append(Float32(hotSpotX).bitPattern, to: &spot)
        MirrorBytes.append(Float32(hotSpotY).bitPattern, to: &spot)
        for byte in spot { mix(byte) }
        return hash == 0 ? 1 : hash
    }

    public func encoded() -> Data {
        var data = Data(capacity: Self.headerByteCount + png.count)
        MirrorBytes.append(id, to: &data)
        MirrorBytes.append(Float32(hotSpotX).bitPattern, to: &data)
        MirrorBytes.append(Float32(hotSpotY).bitPattern, to: &data)
        MirrorBytes.append(Float32(width).bitPattern, to: &data)
        MirrorBytes.append(Float32(height).bitPattern, to: &data)
        data.append(png)
        return data
    }

    public static func decode(_ data: Data) throws -> MirrorCursorShape {
        let bytes = [UInt8](data)
        guard bytes.count >= headerByteCount else {
            throw MirrorPayloadError.truncated(needed: headerByteCount, available: bytes.count)
        }
        let imageBytes = bytes.count - headerByteCount
        guard imageBytes > 0 else { throw MirrorPayloadError.invalid("empty cursor image") }
        guard imageBytes <= maxImageBytes else { throw MirrorPayloadError.tooLarge(imageBytes) }
        func float(at offset: Int) -> Double {
            Double(Float32(bitPattern: UInt32(MirrorBytes.read(bytes, at: offset, count: 4))))
        }
        let id = UInt32(MirrorBytes.read(bytes, at: 0, count: 4))
        let shape = MirrorCursorShape(
            id: id,
            hotSpotX: float(at: 4),
            hotSpotY: float(at: 8),
            width: float(at: 12),
            height: float(at: 16),
            png: Data(bytes[headerByteCount...])
        )
        guard id != 0 else { throw MirrorPayloadError.invalid("cursor shape id 0") }
        let sizes = [shape.hotSpotX, shape.hotSpotY, shape.width, shape.height]
        guard sizes.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1024 }),
              shape.width > 0, shape.height > 0 else {
            throw MirrorPayloadError.invalid("cursor shape geometry")
        }
        return shape
    }
}

/// Why a mirror-stream payload couldn't be read.
public enum MirrorPayloadError: Error, Equatable, Sendable {
    case truncated(needed: Int, available: Int)
    case tooLarge(Int)
    case invalid(String)
}

/// A rectangle in points, top-left origin. Core has no CoreGraphics.
public struct MirrorRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The maths between the Mac's screen, the pointer image and the mirror on
/// the remote.
public enum MirrorCursorGeometry {
    /// Smallest scale a pointer is drawn at, relative to its size on the
    /// Mac. A 1512 pt display in a 200 pt thumbnail would otherwise shrink a
    /// 24 pt arrow to 3 pt.
    public static let minimumSpriteScale = 0.5
    /// Largest scale, so a near-full-screen mirror of a small display
    /// doesn't draw a giant arrow.
    public static let maximumSpriteScale = 1.5

    /// Where a point in global display coordinates (top-left origin, as
    /// `CGEvent.location` and `CGDisplayBounds` use) falls on `display`,
    /// as 0…1 fractions, and whether it is inside it. Right and bottom edges
    /// belong to the next display, as in CoreGraphics.
    public static func normalized(x: Double, y: Double, in display: MirrorRect) -> (x: Double, y: Double, inside: Bool) {
        guard display.width > 0, display.height > 0, x.isFinite, y.isFinite else {
            return (0, 0, false)
        }
        let nx = (x - display.x) / display.width
        let ny = (y - display.y) / display.height
        let inside = nx >= 0 && nx < 1 && ny >= 0 && ny < 1
        return (nx, ny, inside)
    }

    /// The display (by id) that contains a global point, if any.
    public static func display(containingX x: Double, y: Double, in displays: [(id: UInt32, bounds: MirrorRect)]) -> UInt32? {
        displays.first { normalized(x: x, y: y, in: $0.bounds).inside }?.id
    }

    /// The scale a pointer image is drawn at: the mirror's scale, kept
    /// inside `minimumSpriteScale…maximumSpriteScale`.
    public static func spriteScale(displayPointWidth: Double, viewWidth: Double) -> Double {
        guard displayPointWidth > 0, viewWidth > 0 else { return 1 }
        return min(max(viewWidth / displayPointWidth, minimumSpriteScale), maximumSpriteScale)
    }

    /// Where to draw `shape` in a mirror view of `viewWidth` × `viewHeight`
    /// so its hot spot sits on `state`'s position. `displayPointWidth` is the
    /// mirrored display's width in points.
    public static func spriteFrame(
        state: MirrorCursorState,
        shape: MirrorCursorShape,
        displayPointWidth: Double,
        viewWidth: Double,
        viewHeight: Double
    ) -> MirrorRect {
        let scale = spriteScale(displayPointWidth: displayPointWidth, viewWidth: viewWidth)
        let tipX = state.x * viewWidth
        let tipY = state.y * viewHeight
        return MirrorRect(
            x: tipX - shape.hotSpotX * scale,
            y: tipY - shape.hotSpotY * scale,
            width: shape.width * scale,
            height: shape.height * scale
        )
    }
}

/// Decides when the Mac sends a cursor update: at once when the shape,
/// display or visibility changes, for movement only past a small distance
/// and at most `maxRate` times a second, and otherwise a refresh every
/// `refreshInterval` so a lost update heals.
public struct MirrorCursorThrottle: Sendable {
    public static let maxRate = 60.0
    public static let refreshInterval = 1.0
    /// Movement below this fraction of the display isn't worth a packet
    /// (about a third of a point on a 1512 pt display).
    public static let minimumMove = 0.0002

    private var last: MirrorCursorState?
    private var lastSentAt: Double = -.infinity

    public init() {}

    /// Forget the last send (a new stream, a new subscriber).
    public mutating func reset() {
        last = nil
        lastSentAt = -.infinity
    }

    /// Whether to send `state` at time `now` (seconds, any monotonic
    /// clock). Records it as sent when it says yes.
    public mutating func shouldSend(_ state: MirrorCursorState, now: Double) -> Bool {
        let decision: Bool
        if let last {
            let structural = last.shapeID != state.shapeID
                || last.displayID != state.displayID
                || last.isOnMirroredDisplay != state.isOnMirroredDisplay
                || last.isHidden != state.isHidden
            let moved = abs(last.x - state.x) >= Self.minimumMove || abs(last.y - state.y) >= Self.minimumMove
            let elapsed = now - lastSentAt
            if structural {
                decision = true
            } else if moved {
                decision = elapsed >= 1 / Self.maxRate
            } else {
                decision = elapsed >= Self.refreshInterval
            }
        } else {
            decision = true
        }
        if decision {
            last = state
            lastSentAt = now
        }
        return decision
    }
}

/// Pointer images the remote has received, by id, keeping the most recent
/// `capacity`. Generic over the image type so it is tested here.
public struct MirrorCursorShapeCache<Image> {
    public let capacity: Int
    private var entries: [UInt32: (shape: MirrorCursorShape, image: Image)] = [:]
    private var order: [UInt32] = []

    public init(capacity: Int = 32) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { entries.count }

    public mutating func insert(_ shape: MirrorCursorShape, image: Image) {
        entries[shape.id] = (shape, image)
        order.removeAll { $0 == shape.id }
        order.append(shape.id)
        while order.count > capacity {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    public func entry(for id: UInt32) -> (shape: MirrorCursorShape, image: Image)? {
        entries[id]
    }

    public mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
    }
}

/// Big-endian helpers for the mirror payloads.
enum MirrorBytes {
    static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    static func read(_ bytes: [UInt8], at offset: Int, count: Int) -> UInt64 {
        var value: UInt64 = 0
        for byte in bytes[offset..<(offset + count)] {
            value = value << 8 | UInt64(byte)
        }
        return value
    }
}
