//
//  PairingGateAndCopyTests.swift
//  PixelHandCoreTests
//
//  Pairing codes sent while a request is pending (S4), the remote's copy
//  for code results and the "forgotten" state, and the validation rule
//  for `submitCode`.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct PairingPreApprovalTests {

    private func encode(_ message: ControlMessage) throws -> Data {
        try ControlMessageCoding.encoder.encode(message)
    }

    @Test("A code sent while pending goes to the pairing logic, not the loop")
    func codeWhilePending() throws {
        var filter = PreApprovalFilter()
        let submit = try encode(.pairing(.submitCode(code: "572-4125")))
        let r1 = filter.take(submit)
        #expect(r1 == .pairingCode("572-4125"))
        let r2 = filter.admit(submit)
        #expect(!r2) // never reaches the message loop
        #expect(filter.droppedCount == 0)
    }

    @Test("Codes from one pending connection are capped")
    func codesAreCapped() throws {
        var filter = PreApprovalFilter()
        let submit = try encode(.pairing(.submitCode(code: "1")))
        for _ in 0..<PreApprovalFilter.maxPairingCodesWhilePending {
            let r3 = filter.take(submit)
            #expect(r3 == .pairingCode("1"))
        }
        let r4 = filter.take(submit)
        #expect(r4 == .drop)
        #expect(filter.droppedCount == 1)
    }

    @Test("An oversize code and other pairing messages are dropped while pending")
    func otherPairingDropped() throws {
        var filter = PreApprovalFilter()
        let long = try encode(.pairing(.submitCode(code: String(repeating: "1", count: PairingCode.maxInputLength + 1))))
        let r5 = filter.take(long)
        #expect(r5 == .drop)
        let r6 = filter.take(try encode(.pairing(.forget)))
        #expect(r6 == .drop)
        let r7 = filter.take(try encode(.pairing(.pairedStatus(paired: true))))
        #expect(r7 == .drop)
    }

    @Test("Once open, a code is an ordinary message for the loop")
    func codeAfterOpen() throws {
        var filter = PreApprovalFilter()
        filter.open()
        let r8 = filter.take(try encode(.pairing(.submitCode(code: "5724125"))))
        #expect(r8 == .pass)
    }

    @Test("The gate hands pending codes to its callback and still forwards after Allow")
    func gateCallback() async throws {
        let (source, continuation) = AsyncStream.makeStream(of: Data.self)
        let codes = CodeBox()
        let gate = PreApprovalGate(source: source) { code in codes.append(code) }

        continuation.yield(try encode(.input(.mouseClick(button: .left))))
        continuation.yield(try encode(.pairing(.submitCode(code: "5724125"))))
        let deadline = Date().addingTimeInterval(2)
        while codes.values.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(codes.values == ["5724125"])
        #expect(gate.droppedCount == 1)

        gate.open()
        let after = try encode(.pairing(.submitCode(code: "1111111")))
        continuation.yield(after)
        continuation.finish()
        var received: [Data] = []
        for await data in gate.messages { received.append(data) }
        #expect(received == [after])
        #expect(codes.values == ["5724125"])
    }

    private final class CodeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        func append(_ code: String) { lock.lock(); stored.append(code); lock.unlock() }
        var values: [String] { lock.lock(); defer { lock.unlock() }; return stored }
    }
}

@Suite struct PairingCopyTests {

    @Test("Forgotten is a final, terminal state with its own copy")
    func forgotten() {
        let status = ApprovalStatusCopy.forgottenStatus
        #expect(ApprovalStatusCopy.isTerminal(status))
        #expect(ApprovalStatusCopy.isFinalVerdict(status))
        #expect(ApprovalStatusCopy.headerSubtitle(status: status, activeAppName: "Xcode") == "Forgotten")
        let copy = ApprovalStatusCopy.overlay(status: status, peerName: "Studio")
        #expect(copy.title == "Device Forgotten")
        #expect(copy.message.contains("Studio"))
        #expect(!ApprovalStatusCopy.showsLiveIndicator(status: status))
    }

    @Test("Waiting mentions the pairing code")
    func pendingMentionsCode() {
        #expect(ApprovalStatusCopy.overlay(status: "pending", peerName: "Studio").message.contains("code"))
    }

    @Test("Each code result has its own line")
    func codeResults() {
        #expect(ApprovalStatusCopy.codeResult(.accepted, peerName: "Studio") == nil)
        #expect(ApprovalStatusCopy.codeResult(.wrongCode(attemptsLeft: 3), peerName: "Studio") == "That code didn’t match. 3 tries left.")
        #expect(ApprovalStatusCopy.codeResult(.wrongCode(attemptsLeft: 1), peerName: "Studio")?.contains("One try left") == true)
        #expect(ApprovalStatusCopy.codeResult(.lockedOut(retryAfter: 60), peerName: "Studio")?.contains("1 minute") == true)
        #expect(ApprovalStatusCopy.codeResult(.expired, peerName: "Studio")?.contains("expired") == true)
        #expect(ApprovalStatusCopy.codeResult(.noActiveCode, peerName: "Studio")?.contains("Pair a Device") == true)
    }

    @Test("Typing feedback only speaks up for real mistakes")
    func entryHints() {
        #expect(ApprovalStatusCopy.codeEntryHint(PairingCode.parse("572")) == nil)
        #expect(ApprovalStatusCopy.codeEntryHint(PairingCode.parse("5724125")) == nil)
        #expect(ApprovalStatusCopy.codeEntryHint(PairingCode.parse("5724124")) != nil)
        #expect(ApprovalStatusCopy.codeEntryHint(PairingCode.parse("57x")) != nil)
    }

    @Test func durations() {
        #expect(ApprovalStatusCopy.durationText(seconds: 1) == "1 second")
        #expect(ApprovalStatusCopy.durationText(seconds: 45) == "45 seconds")
        #expect(ApprovalStatusCopy.durationText(seconds: 60) == "1 minute")
        #expect(ApprovalStatusCopy.durationText(seconds: 61) == "2 minutes")
    }
}

@Suite struct PairingValidationTests {

    @Test("A code longer than any code is dropped before the Mac reads it")
    func oversizeCodeDropped() {
        let ok = ControlMessage.pairing(.submitCode(code: "572-4125"))
        #expect(RemoteInputValidation.sanitize(ok) == ok)
        let long = ControlMessage.pairing(.submitCode(code: String(repeating: "9", count: PairingCode.maxInputLength + 1)))
        #expect(RemoteInputValidation.sanitize(long) == nil)
    }

    @Test("The locked-Mac gate lets pairing through")
    func lockPolicyAllowsPairing() {
        for message: PairingMessage in [.submitCode(code: "5724125"), .forget] {
            #expect(LockPolicy.decide(.pairing(message), state: .screenLocked) == .allow)
        }
    }
}
