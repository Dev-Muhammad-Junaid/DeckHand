//
//  TrustListTests.swift
//  PixelHandCoreTests
//
//  Paired devices keyed on the Loom identity key (S4), the Mac's
//  per-connection admission, and the remote's book of paired Macs.
//

import Foundation
import PixelHandCore
import Testing

private func key(_ seed: String) -> String {
    String(repeating: seed, count: 64 / seed.count)
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func candidate(_ keySeed: String, device: UUID = UUID(), name: String = "Junaid’s iPad", kind: PairedDeviceKind = .iPad) -> TrustCandidate {
    TrustCandidate(identityKeyID: key(keySeed), deviceID: device, name: name, kind: kind)
}

@Suite struct TrustListTests {

    @Test("Trust is decided by the identity key alone")
    func keyedOnIdentityKey() throws {
        var list = TrustList()
        let device = UUID()
        try list.trust(candidate("a1", device: device), method: .code, at: t0)
        #expect(list.isTrusted(identityKeyID: key("a1")))
        // Same device ID, different key: a stranger.
        #expect(!list.isTrusted(identityKeyID: key("b2")))
        #expect(!list.isTrusted(identityKeyID: nil))
        #expect(!list.isTrusted(identityKeyID: ""))
        #expect(list.device(identityKeyID: key("a1"))?.deviceID == device)
    }

    @Test("Pairing again with a new key replaces the device's old record")
    func newKeyReplacesOld() throws {
        var list = TrustList()
        let device = UUID()
        try list.trust(candidate("a1", device: device), method: .code, at: t0)
        try list.trust(candidate("b2", device: device), method: .code, at: t0 + 10)
        #expect(!list.isTrusted(identityKeyID: key("a1")))
        #expect(list.isTrusted(identityKeyID: key("b2")))
        #expect(list.devices.count == 1)
    }

    @Test("Pairing a known key again refreshes it and keeps its first pairing")
    func repairRefreshes() throws {
        var list = TrustList()
        let first = UUID()
        try list.trust(candidate("a1", device: first, name: "Old"), method: .code, at: t0)
        let second = UUID()
        let record = try list.trust(candidate("a1", device: second, name: "New"), method: .approval, at: t0 + 50)
        #expect(record.pairedAt == t0)
        #expect(record.method == .code)
        #expect(record.lastSeenAt == t0 + 50)
        #expect(record.name == "New")
        #expect(record.deviceID == second)
        #expect(list.devices.count == 1)
    }

    @Test("A malformed key ID can't be trusted")
    func invalidKeysRefused() {
        var list = TrustList()
        for bad in ["", "short", String(repeating: "a", count: 129), key("a1") + " ", "ключ" + key("a1")] {
            #expect(throws: TrustList.TrustError.invalidIdentityKeyID) {
                try list.trust(TrustCandidate(identityKeyID: bad, deviceID: UUID(), name: "x", kind: .iPad), method: .code, at: t0)
            }
        }
        #expect(list.isEmpty)
    }

    @Test("Forgetting removes the record; forgetting twice does nothing")
    func revoke() throws {
        var list = TrustList()
        try list.trust(candidate("a1"), method: .code, at: t0)
        try list.trust(candidate("b2"), method: .code, at: t0)
        let r1 = list.revoke(identityKeyID: key("a1"))?.identityKeyID
        #expect(r1 == key("a1"))
        #expect(!list.isTrusted(identityKeyID: key("a1")))
        #expect(list.isTrusted(identityKeyID: key("b2")))
        let r2 = list.revoke(identityKeyID: key("a1"))
        #expect(r2 == nil)
    }

    @Test("Loom's revoke-by-device-ID hook removes that device's records")
    func revokeByDevice() throws {
        var list = TrustList()
        let device = UUID()
        try list.trust(candidate("a1", device: device), method: .code, at: t0)
        try list.trust(candidate("b2"), method: .code, at: t0)
        let r3 = list.revokeAll(deviceID: device).count
        #expect(r3 == 1)
        #expect(!list.isTrusted(identityKeyID: key("a1")))
        #expect(list.isTrusted(identityKeyID: key("b2")))
    }

    @Test("Seeing a device stamps it and takes its new name; unknown keys are ignored")
    func noteSeen() throws {
        var list = TrustList()
        try list.trust(candidate("a1", name: "iPad"), method: .code, at: t0)
        let r4 = list.noteSeen(identityKeyID: key("a1"), name: "Studio iPad", at: t0 + 99)
        #expect(r4)
        #expect(list.device(identityKeyID: key("a1"))?.lastSeenAt == t0 + 99)
        #expect(list.device(identityKeyID: key("a1"))?.name == "Studio iPad")
        let r5 = list.noteSeen(identityKeyID: key("b2"), name: "x", at: t0)
        #expect(!r5)
    }

    @Test("Past capacity, the device seen least recently is dropped")
    func capacity() throws {
        var list = TrustList()
        for index in 0..<TrustList.capacity {
            let id = String(format: "%064x", index + 1)
            try list.trust(TrustCandidate(identityKeyID: id, deviceID: UUID(), name: "d\(index)", kind: .iPad), method: .code, at: t0 + Double(index))
        }
        // The very first device was used recently, so the second goes.
        list.noteSeen(identityKeyID: String(format: "%064x", 1), name: nil, at: t0 + 1_000)
        try list.trust(candidate("ff"), method: .code, at: t0 + 2_000)
        #expect(list.devices.count == TrustList.capacity)
        #expect(list.isTrusted(identityKeyID: String(format: "%064x", 1)))
        #expect(!list.isTrusted(identityKeyID: String(format: "%064x", 2)))
        #expect(list.isTrusted(identityKeyID: key("ff")))
    }

    @Test("Names from peers are cleaned")
    func namesAreCleaned() {
        #expect(TrustList.cleanName("  iPad\n") == "iPad")
        #expect(TrustList.cleanName("i\u{0}P\u{202E}ad\u{7}") == "iPad")
        #expect(TrustList.cleanName("\u{200B}\n ") == "Unnamed device")
        #expect(TrustList.cleanName(String(repeating: "x", count: 500)).count == TrustList.maxNameLength)
        #expect(TrustList.cleanName("Junaid’s iPad 🖐️") == "Junaid’s iPad 🖐️")
    }

    @Test("The list survives storage, and a bad record doesn't lose the rest")
    func storage() throws {
        var list = TrustList()
        try list.trust(candidate("a1", name: "iPad"), method: .code, at: t0)
        try list.trust(candidate("b2", name: "iPhone", kind: .iPhone), method: .approval, at: t0 + 1)
        let data = try list.encoded()
        #expect(try TrustList(storage: data) == list)

        var json = try #require(String(data: data, encoding: .utf8))
        // Corrupt one record's key and give one an unknown kind.
        json = json.replacingOccurrences(of: key("a1"), with: "bad key")
        json = json.replacingOccurrences(of: "\"iPhone\"", with: "\"watch\"")
        let read = try TrustList(storage: Data(json.utf8))
        #expect(read.devices.count == 1)
        #expect(read.device(identityKeyID: key("b2"))?.kind == .other)
    }

    @Test("A newer or broken store is refused, not misread")
    func storageVersion() {
        #expect(throws: (any Error).self) {
            try TrustList(storage: Data(#"{"version":2,"devices":[]}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try TrustList(storage: Data("not json".utf8))
        }
    }
}

@Suite struct PairingAdmissionTests {

    @Test("Paired keys connect without a prompt, proven strangers are asked, the unproven are refused")
    func decide() throws {
        var list = TrustList()
        try list.trust(candidate("a1"), method: .code, at: t0)
        let paired = try #require(list.device(identityKeyID: key("a1")))

        #expect(PairingAdmission.decide(identityKeyID: key("a1"), isIdentityAuthenticated: true, trustList: list) == .autoGrant(paired))
        #expect(PairingAdmission.decide(identityKeyID: key("b2"), isIdentityAuthenticated: true, trustList: list) == .askUser(identityKeyID: key("b2")))
        // A paired key the handshake didn't verify is not trusted.
        #expect(PairingAdmission.decide(identityKeyID: key("a1"), isIdentityAuthenticated: false, trustList: list) == .refuse)
        #expect(PairingAdmission.decide(identityKeyID: nil, isIdentityAuthenticated: true, trustList: list) == .refuse)
        #expect(PairingAdmission.decide(identityKeyID: "short", isIdentityAuthenticated: true, trustList: list) == .refuse)
    }

    @Test("A forgotten device is asked again")
    func revokedIsAsked() throws {
        var list = TrustList()
        try list.trust(candidate("a1"), method: .code, at: t0)
        list.revoke(identityKeyID: key("a1"))
        #expect(PairingAdmission.decide(identityKeyID: key("a1"), isIdentityAuthenticated: true, trustList: list) == .askUser(identityKeyID: key("a1")))
    }
}

@Suite struct RemotePairingBookTests {

    private let mac = candidate("c3", name: "Studio Mac", kind: .mac)

    @Test("The Mac's report records and removes it")
    func followsTheMac() {
        var book = RemotePairingBook()
        let r6 = book.macReported(paired: true, mac: mac, at: t0)
        #expect(r6 == .recorded)
        #expect(book.macs.isTrusted(identityKeyID: mac.identityKeyID))
        let r7 = book.macReported(paired: true, mac: mac, at: t0 + 1)
        #expect(r7 == .recorded)
        let r8 = book.macReported(paired: false, mac: mac, at: t0 + 2)
        #expect(r8 == .removed)
        let r9 = book.macReported(paired: false, mac: mac, at: t0 + 3)
        #expect(r9 == .none)
        #expect(book.macs.isEmpty)
    }

    @Test("Forgetting a connected Mac holds nothing back")
    func forgetConnected() {
        var book = RemotePairingBook()
        _ = book.macReported(paired: true, mac: mac, at: t0)
        let r10 = book.forget(identityKeyID: mac.identityKeyID, isConnected: true)
        #expect(r10 != nil)
        #expect(book.pendingForgets.isEmpty)
        #expect(book.macs.isEmpty)
    }

    @Test("Forgetting a Mac that's away is sent the next time it says it's paired")
    func forgetAway() {
        var book = RemotePairingBook()
        _ = book.macReported(paired: true, mac: mac, at: t0)
        book.forget(identityKeyID: mac.identityKeyID, isConnected: false)
        #expect(book.pendingForgets == [mac.identityKeyID])
        let r11 = book.macReported(paired: true, mac: mac, at: t0 + 1)
        #expect(r11 == .sendForget)
        #expect(book.pendingForgets.isEmpty)
        #expect(book.macs.isEmpty) // not recorded again
        // Next time it reports normally.
        let r12 = book.macReported(paired: true, mac: mac, at: t0 + 2)
        #expect(r12 == .recorded)
    }

    @Test("A held forget is dropped if the Mac already forgot this device")
    func forgetAlreadyDone() {
        var book = RemotePairingBook()
        book.forget(identityKeyID: mac.identityKeyID, isConnected: false)
        let r13 = book.macReported(paired: false, mac: mac, at: t0)
        #expect(r13 == .none)
        #expect(book.pendingForgets.isEmpty)
    }

    @Test("Held forgets are capped and survive storage")
    func capAndStorage() throws {
        var book = RemotePairingBook()
        for index in 0..<(RemotePairingBook.maxPendingForgets + 5) {
            book.forget(identityKeyID: String(format: "%064x", index), isConnected: false)
        }
        #expect(book.pendingForgets.count == RemotePairingBook.maxPendingForgets)
        #expect(book.pendingForgets.first == String(format: "%064x", 5))
        book.forget(identityKeyID: "bad", isConnected: false)
        #expect(!book.pendingForgets.contains("bad"))
        _ = book.macReported(paired: true, mac: mac, at: t0)
        #expect(try RemotePairingBook(storage: book.encoded()) == book)
    }
}
