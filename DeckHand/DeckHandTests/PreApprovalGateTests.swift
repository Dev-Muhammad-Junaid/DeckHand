//
//  PreApprovalGateTests.swift
//  DeckHandTests
//
//  Input a device sent while its approval request was pending used to sit
//  in the connection and run all at once when the user clicked Allow. The
//  gate drops it instead; only a few authorization-status queries survive.
//

import XCTest

final class PreApprovalGateTests: XCTestCase {

    private func encode(_ message: ControlMessage) throws -> Data {
        try ControlMessageCoding.encoder.encode(message)
    }

    // MARK: - Filter

    func testPendingInputIsDropped() throws {
        var filter = PreApprovalFilter()
        let input: [ControlMessage] = [
            .mouseDelta(dx: 5, dy: 5),
            .mouseClick(button: .left),
            .keyboardShortcut(keys: ["cmd", "q"]),
            .launchApp(bundleID: "com.apple.Terminal"),
            .tracked(requestID: "t", command: .mouseClick(button: .left)),
            .ping(seq: 1),
        ]
        for message in input {
            XCTAssertFalse(filter.admit(try encode(message)), "\(message)")
        }
        XCTAssertFalse(filter.admit(Data("not json".utf8)))
        XCTAssertEqual(filter.droppedCount, input.count + 1)
    }

    func testStatusQueriesAreKeptUpToTheCap() throws {
        var filter = PreApprovalFilter()
        let query = try encode(.requestAuthorizationStatus)
        for _ in 0..<PreApprovalFilter.maxHeldStatusQueries {
            XCTAssertTrue(filter.admit(query))
        }
        XCTAssertFalse(filter.admit(query))
    }

    func testEverythingPassesOnceOpen() throws {
        var filter = PreApprovalFilter()
        XCTAssertFalse(filter.admit(try encode(.mouseClick(button: .left))))
        filter.open()
        XCTAssertTrue(filter.admit(try encode(.mouseClick(button: .left))))
        XCTAssertTrue(filter.admit(Data("anything".utf8)))
        XCTAssertEqual(filter.droppedCount, 1)
    }

    // MARK: - Gate

    func testGateDropsBacklogAndForwardsAfterOpen() async throws {
        let (source, sourceContinuation) = AsyncStream.makeStream(of: Data.self)
        let gate = PreApprovalGate(source: source)

        // Sent while pending: two clicks and a status query.
        let click = try encode(.mouseClick(button: .left))
        let query = try encode(.requestAuthorizationStatus)
        let afterAllow = try encode(.mouseDelta(dx: 1, dy: 2))
        sourceContinuation.yield(click)
        sourceContinuation.yield(query)
        sourceContinuation.yield(click)

        // Wait for the gate to read the backlog before the user "clicks Allow".
        let deadline = Date().addingTimeInterval(2)
        while gate.droppedCount < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(gate.droppedCount, 2)

        gate.open()
        sourceContinuation.yield(afterAllow)
        sourceContinuation.finish()

        var received: [Data] = []
        for await data in gate.messages {
            received.append(data)
        }
        XCTAssertEqual(received, [query, afterAllow])
    }

    func testGateFinishesWhenTheConnectionEnds() async {
        let (source, sourceContinuation) = AsyncStream.makeStream(of: Data.self)
        let gate = PreApprovalGate(source: source)
        sourceContinuation.finish()

        var count = 0
        for await _ in gate.messages { count += 1 }
        XCTAssertEqual(count, 0)
    }
}
