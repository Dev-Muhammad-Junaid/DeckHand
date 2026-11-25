//
//  NetworkStartGateTests.swift
//  PixelHandCoreTests
//
//  Build 22 (P2): Try again during a slow first start must join the start
//  in flight, never start a second one beside it.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct NetworkStartGateTests {
    @Test("The first request starts attempt 1")
    func firstStart() {
        var gate = NetworkStartGate()
        #expect(gate.phase == .idle)
        #expect(gate.request() == .start(attempt: 1))
        #expect(gate.isStarting)
        #expect(!gate.isRunning)
        #expect(gate.failureMessage == nil)
    }

    @Test("Try again while the first start is pending joins it (the build 22 case)")
    func tryAgainJoins() {
        var gate = NetworkStartGate()
        #expect(gate.request() == .start(attempt: 1))
        // The account check is slow; the picker offers Try again, tapped twice.
        #expect(gate.request() == .join(attempt: 1))
        #expect(gate.request() == .join(attempt: 1))
        #expect(gate.attempt == 1)
        #expect(gate.phase == .starting(attempt: 1))
        // The one start finishes: running, no error shown.
        let ended1 = gate.finished(attempt: 1, error: nil)
        #expect(ended1)
        #expect(gate.isRunning)
        #expect(gate.failureMessage == nil)
    }

    @Test("Try again once running refreshes discovery instead of starting again")
    func tryAgainRefreshes() {
        var gate = NetworkStartGate()
        _ = gate.request()
        gate.finished(attempt: 1, error: nil)
        #expect(gate.request() == .refresh)
        #expect(gate.request() == .refresh)
        #expect(gate.attempt == 1)
        #expect(gate.isRunning)
    }

    @Test("A failed start shows its message; Try again starts a new attempt")
    func failureThenRetry() {
        var gate = NetworkStartGate()
        _ = gate.request()
        let ended2 = gate.finished(attempt: 1, error: "No network")
        #expect(ended2)
        #expect(gate.failureMessage == "No network")
        #expect(!gate.isStarting)
        #expect(gate.request() == .start(attempt: 2))
        #expect(gate.failureMessage == nil)
        let ended3 = gate.finished(attempt: 2, error: nil)
        #expect(ended3)
        #expect(gate.isRunning)
    }

    @Test("A result for an attempt that isn't in flight is ignored")
    func staleResultIgnored() {
        var gate = NetworkStartGate()
        _ = gate.request()
        gate.finished(attempt: 1, error: "Failed")
        _ = gate.request() // attempt 2
        // A late report from attempt 1 can't fail attempt 2.
        let ended4 = gate.finished(attempt: 1, error: "CancellationError")
        #expect(!ended4)
        #expect(gate.phase == .starting(attempt: 2))
        // Nor can a duplicate report after attempt 2 ended.
        let ended5 = gate.finished(attempt: 2, error: nil)
        #expect(ended5)
        let ended6 = gate.finished(attempt: 2, error: "Already advertising service")
        #expect(!ended6)
        #expect(gate.isRunning)
    }

    @Test("Nothing finishes while idle")
    func idleIgnoresResults() {
        var gate = NetworkStartGate()
        let ended7 = gate.finished(attempt: 0, error: nil)
        #expect(!ended7)
        let ended8 = gate.finished(attempt: 1, error: "x")
        #expect(!ended8)
        #expect(gate.phase == .idle)
    }

    @Test("After a stop the next request starts again")
    func stopThenStart() {
        var gate = NetworkStartGate()
        _ = gate.request()
        gate.finished(attempt: 1, error: nil)
        gate.stopped()
        #expect(gate.phase == .idle)
        #expect(gate.request() == .start(attempt: 2))
    }

    @Test("Never two starts in flight, whatever the order of taps and results")
    func singleFlightSweep() {
        // Every sequence of 6 events from {request, finish ok, finish error}.
        for code in 0..<729 {
            var gate = NetworkStartGate()
            var inFlight = 0
            var c = code
            for _ in 0..<6 {
                let event = c % 3
                c /= 3
                switch event {
                case 0:
                    if case .start = gate.request() { inFlight += 1 }
                default:
                    if gate.finished(attempt: gate.attempt, error: event == 1 ? nil : "e") { inFlight -= 1 }
                }
                #expect(inFlight <= 1)
                #expect(inFlight == (gate.isStarting ? 1 : 0))
            }
        }
    }
}
