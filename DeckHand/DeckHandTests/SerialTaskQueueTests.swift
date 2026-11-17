//
//  SerialTaskQueueTests.swift
//  DeckHandTests
//
//  The mirror's start/stop lifecycle runs through `SerialTaskQueue`. Before,
//  two `startMirror` messages interleaved at their `await`s, both saw "no
//  stream" and both built an `SCStream`. These tests pin that queued
//  operations never overlap and run in submission order.
//

import XCTest

/// Main-actor state the queued operations share. A class so `@Sendable`
/// closures can capture it.
@MainActor
private final class Probe {
    var inFlight = 0
    var maxInFlight = 0
    var started = 0
    var order: [Int] = []
    var hasStream = false
    var streamsCreated = 0
}

@MainActor
final class SerialTaskQueueTests: XCTestCase {

    func testOperationsNeverOverlap() async {
        let queue = SerialTaskQueue()
        let probe = Probe()

        // Main-actor tasks rather than a task group: Swift 6.4's region
        // checker can't analyse `group.addTask { @MainActor in }` here.
        let callers = (0..<8).map { _ in
            Task { @MainActor in
                await queue.run {
                    probe.inFlight += 1
                    probe.started += 1
                    probe.maxInFlight = max(probe.maxInFlight, probe.inFlight)
                    // Suspend mid-operation, the way `startStream` awaits
                    // ScreenCaptureKit; a re-entrant caller would get in here.
                    try? await Task.sleep(for: .milliseconds(5))
                    await Task.yield()
                    probe.inFlight -= 1
                }
            }
        }
        for caller in callers { await caller.value }

        XCTAssertEqual(probe.started, 8)
        XCTAssertEqual(probe.maxInFlight, 1)
    }

    func testOperationsRunInSubmissionOrder() async {
        let queue = SerialTaskQueue()
        let probe = Probe()

        // `enqueue` fixes the order at call time, even though the first
        // operation is the slowest.
        queue.enqueue {
            try? await Task.sleep(for: .milliseconds(20))
            probe.order.append(1)
        }
        queue.enqueue { probe.order.append(2) }
        await queue.run { probe.order.append(3) }

        XCTAssertEqual(probe.order, [1, 2, 3])
    }

    /// The bug in miniature: a "start" that checks for a stream, awaits,
    /// then creates one. Two concurrent starts create exactly one.
    func testCheckThenCreateIsNotRacy() async {
        let queue = SerialTaskQueue()
        let probe = Probe()

        let callers = (0..<2).map { _ in
            Task { @MainActor in
                await queue.run {
                    guard !probe.hasStream else { return }
                    try? await Task.sleep(for: .milliseconds(5))
                    probe.streamsCreated += 1
                    probe.hasStream = true
                }
            }
        }
        for caller in callers { await caller.value }

        XCTAssertEqual(probe.streamsCreated, 1)
    }
}
