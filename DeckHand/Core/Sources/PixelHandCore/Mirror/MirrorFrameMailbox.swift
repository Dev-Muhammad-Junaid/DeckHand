//
//  MirrorFrameMailbox.swift
//  PixelHandCore
//
//  Newest-frame-wins hand-off between the thread that reads the mirror
//  stream and the one that decodes. Reading never waits for decoding: a
//  frame that arrives while the decoder is busy replaces the one waiting,
//  so a slow decoder shows fewer frames instead of older ones.
//

import Foundation

public final class MirrorFrameMailbox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var slot: Value?
    private var replaced = 0

    public init() {}

    /// Leaves `value` for the next `take`. Returns `true` when it replaced
    /// a value nobody had taken yet (that one is dropped).
    @discardableResult
    public func put(_ value: Value) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let dropped = slot != nil
        if dropped { replaced += 1 }
        slot = value
        return dropped
    }

    /// The waiting value, if any, emptying the slot.
    public func take() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        let value = slot
        slot = nil
        return value
    }

    /// Values replaced before they were taken since the last call.
    public func takeReplacedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let count = replaced
        replaced = 0
        return count
    }

    public func clear() {
        lock.lock()
        slot = nil
        lock.unlock()
    }
}
