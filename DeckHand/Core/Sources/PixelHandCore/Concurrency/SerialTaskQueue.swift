//
//  SerialTaskQueue.swift
//  PixelHandCore
//
//  Runs async operations one at a time, in the order they were submitted.
//  A `@MainActor` method that awaits is re-entrant: a second call can start
//  while the first is suspended. That let two `startMirror` messages both
//  see "no stream" and both build an `SCStream`, orphaning one. Lifecycle
//  work submitted here can't interleave.
//

import Foundation

@MainActor
public final class SerialTaskQueue {
    private var tail: Task<Void, Never>?

    public init() {}

    /// Runs `operation` after every previously submitted operation has
    /// finished, and returns when it has finished too.
    public func run(_ operation: @escaping @MainActor @Sendable () async -> Void) async {
        await enqueue(operation).value
    }

    /// Queues `operation` behind everything already submitted and returns
    /// at once. Its place in the order is fixed when this is called.
    @discardableResult
    public func enqueue(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tail = task
        return task
    }
}
