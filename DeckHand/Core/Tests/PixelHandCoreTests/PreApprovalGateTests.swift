//
//  PreApprovalGateTests.swift
//  PixelHandCoreTests
//
//  Input a device sent while its approval request was pending used to sit
//  in the connection and run all at once when the user clicked Allow. The
//  gate drops it instead; only a few authorization-status queries survive.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct PreApprovalGateTests {

    private func encode(_ message: ControlMessage) throws -> Data {
        try ControlMessageCoding.encoder.encode(message)
    }

    // MARK: - Filter

    @Test func pendingInputIsDropped() throws {
        var filter = PreApprovalFilter()
        let input: [ControlMessage] = [
            .input(.mouseDelta(dx: 5, dy: 5)),
            .input(.mouseClick(button: .left)),
            .input(.keyboardShortcut(keys: ["cmd", "q"])),
            .apps(.launchApp(bundleID: "com.apple.Terminal")),
            .deck(.run(requestID: "t", action: .shortcut(keys: ["cmd", "q"]))),
            .system(.run(action: .showDesktop)),
            .session(.ping(seq: 1)),
        ]
        for message in input {
            let admitted = filter.admit(try encode(message))
            #expect(!admitted, "\(message)")
        }
        let garbage = filter.admit(Data("not json".utf8))
        #expect(!garbage)
        #expect(filter.droppedCount == input.count + 1)
    }

    @Test func statusQueriesAreKeptUpToTheCap() throws {
        var filter = PreApprovalFilter()
        let query = try encode(.pairing(.requestAuthorizationStatus))
        for _ in 0..<PreApprovalFilter.maxHeldStatusQueries {
            let admitted = filter.admit(query)
            #expect(admitted)
        }
        let overCap = filter.admit(query)
        #expect(!overCap)
    }

    @Test func everythingPassesOnceOpen() throws {
        var filter = PreApprovalFilter()
        let beforeOpen = filter.admit(try encode(.input(.mouseClick(button: .left))))
        #expect(!beforeOpen)
        filter.open()
        let afterOpen = filter.admit(try encode(.input(.mouseClick(button: .left))))
        #expect(afterOpen)
        let anything = filter.admit(Data("anything".utf8))
        #expect(anything)
        #expect(filter.droppedCount == 1)
    }

    // MARK: - Gate

    @Test func gateDropsBacklogAndForwardsAfterOpen() async throws {
        let (source, sourceContinuation) = AsyncStream.makeStream(of: Data.self)
        let gate = PreApprovalGate(source: source)

        // Sent while pending: two clicks and a status query.
        let click = try encode(.input(.mouseClick(button: .left)))
        let query = try encode(.pairing(.requestAuthorizationStatus))
        let afterAllow = try encode(.input(.mouseDelta(dx: 1, dy: 2)))
        sourceContinuation.yield(click)
        sourceContinuation.yield(query)
        sourceContinuation.yield(click)

        // Wait for the gate to read the backlog before the user "clicks Allow".
        let deadline = Date().addingTimeInterval(2)
        while gate.droppedCount < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(gate.droppedCount == 2)

        gate.open()
        sourceContinuation.yield(afterAllow)
        sourceContinuation.finish()

        var received: [Data] = []
        for await data in gate.messages {
            received.append(data)
        }
        #expect(received == [query, afterAllow])
    }

    @Test func gateFinishesWhenTheConnectionEnds() async {
        let (source, sourceContinuation) = AsyncStream.makeStream(of: Data.self)
        let gate = PreApprovalGate(source: source)
        sourceContinuation.finish()

        var count = 0
        for await _ in gate.messages { count += 1 }
        #expect(count == 0)
    }
}
