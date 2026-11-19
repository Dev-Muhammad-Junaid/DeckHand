//
//  TrustListTests.swift
//  PixelHandCoreTests
//
//  Paired devices anchored on the Loom identity key (S4), the Mac's
//  per-connection admission, and the remote's book of paired Macs.
//
//  `#expect` can't wrap a mutating call, so results are bound first.
//

import Foundation
import PixelHandCore
import Testing

private func key(_ seed: String) -> String {
    String(repeating: seed, count: 64 / seed.count)
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let ipadID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let phoneID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

private func candidate(
    _ keySeed: String,
    device: UUID = UUID(),
    name: String = "Junaid’s iPad",
    kind: PairedDeviceKind = .iPad
) -> TrustCandidate {
    TrustCandidate(identityKeyID: key(keySeed), deviceID: device, name: name, kind: kind)
}

@Suite struct TrustListTests {

    @Test("A record matches only the key it was paired with, on the device that key signed")
    func keyAndDevice() throws {
        var list = TrustList()
        try list.trust(candidate("a1", device: ipadID), method: .code, at: t0)
        #expect(list.isTrusted(identityKeyID: key("a1"), deviceID: ipadID))
        // Same device ID, different key: a stranger.
        #expect(!list.isTrusted(identityKeyID: key("b2"), deviceID: ipadID))
        // Missing pieces never match.
        #expect(!list.isTrusted(identityKeyID: nil, deviceID: ipadID))
        #expect(!list.isTrusted(identityKeyID: "", deviceID: ipadID))
        #expect(!list.isTrusted(identityKeyID: key("a1"), deviceID: nil))
    }

    @Test("Devices sharing a synced key are paired and forgotten one at a time")
    func sharedKeyIsPerDevice() throws {
        var list = TrustList()
        try list.trust(candidate("a1", device: ipadID), method: .code, at: t0)
        // The owner's iPhone presents the same iCloud Keychain key: not paired.
        #expect(!list.isTrusted(identityKeyID: key("a1"), deviceID: phoneID))
        try list.trust(candidate("a1", device: phoneID, kind: .iPhone), method: .code, at: t0 + 1)
        #expect(list.devices(identityKeyID: key("a1")).count == 2)

        let removed = list.revoke(PairedDeviceRef(identityKeyID: key("a1"), deviceID: ipadID))
        #expect(removed?.deviceID == ipadID)
        #expect(!list.isTrusted(identityKeyID: key("a1"), deviceID: ipadID))
        #expect(list.isTrusted(identityKeyID: key("a1"), deviceID: phoneID))

        let all = list.revokeAll(identityKeyID: key("a1"))
        #expect(all.count == 1)
        #expect(list.isEmpty)
    }

    @Test("Pairing a device again with a new key replaces its old record")
    func newKeyReplacesOld() throws {
        var list = TrustList()
        try list.trust(candidate("a1", device: ipadID), method: .code, at: t0)
        try list.trust(candidate("b2", device: ipadID), method: .code, at: t0 + 10)
        #expect(!list.isTrusted(identityKeyID: key("a1"), deviceID: ipadID))
        #expect(list.isTrusted(identityKeyID: key("b2"), deviceID: ipadID))
        #expect(list.devices.count == 1)
    }

    @Test("Pairing a paired device again refreshes it and keeps its first pairing")
    func repairRefreshes() throws {
        var list = TrustList()
        try list.trust(candidate("a1", device: ipadID, name: "Old"), method: .code, at: t0)
        let record = try list.trust(candidate("a1", device: ipadID, name: "New"), method: .approval, at: t0 + 50)
        #expect(record.pairedAt == t0)
        #expect(record.method == .code)
        #expect(record.lastSeenAt == t0 + 50)
        #expect(record.name == "New")
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
        let a = candidate("a1")
        let b = candidate("b2")
        try list.trust(a, method: .code, at: t0)
        try list.trust(b, method: .code, at: t0)
        let first = list.revoke(a.ref)
        #expect(first?.ref == a.ref)
        #expect(!list.isTrusted(identityKeyID: a.identityKeyID, deviceID: a.deviceID))
        #expect(list.isTrusted(identityKeyID: b.identityKeyID, deviceID: b.deviceID))
        let second = list.revoke(a.ref)
        #expect(second == nil)
    }

    @Test("Loom's revoke-by-device-ID hook removes that device's record")
    func revokeByDevice() throws {
        var list = TrustList()
        try list.trust(candidate("a1", device: ipadID), method: .code, at: t0)
        let other = candidate("b2")
        try list.trust(other, method: .code, at: t0)
        let removed = list.revokeAll(deviceID: ipadID)
        #expect(removed.count == 1)
        #expect(!list.isTrusted(identityKeyID: key("a1"), deviceID: ipadID))
        #expect(list.isTrusted(identityKeyID: other.identityKeyID, deviceID: other.deviceID))
    }

    @Test("Seeing a device stamps it and takes its new name; unknown devices are ignored")
    func noteSeen() throws {
        var list = TrustList()
        let a = candidate("a1", name: "iPad")
        try list.trust(a, method: .code, at: t0)
        let seen = list.noteSeen(a.ref, name: "Studio iPad", at: t0 + 99)
        #expect(seen)
        #expect(list.device(a.ref)?.lastSeenAt == t0 + 99)
        #expect(list.device(a.ref)?.name == "Studio iPad")
        let unknown = list.noteSeen(PairedDeviceRef(identityKeyID: key("a1"), deviceID: UUID()), name: "x", at: t0)
        #expect(!unknown)
    }

    @Test("Past capacity, the device seen least recently is dropped")
    func capacity() throws {
        var list = TrustList()
        var refs: [PairedDeviceRef] = []
        for index in 0..<TrustList.capacity {
            let c = TrustCandidate(identityKeyID: String(format: "%064x", index + 1), deviceID: UUID(), name: "d\(index)", kind: .iPad)
            refs.append(c.ref)
            try list.trust(c, method: .code, at: t0 + Double(index))
        }
        // The very first device was used recently, so the second goes.
        list.noteSeen(refs[0], name: nil, at: t0 + 1_000)
        let newcomer = candidate("ff")
        try list.trust(newcomer, method: .code, at: t0 + 2_000)
        #expect(list.devices.count == TrustList.capacity)
        #expect(list.device(refs[0]) != nil)
        #expect(list.device(refs[1]) == nil)
        #expect(list.device(newcomer.ref) != nil)
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
        let phone = candidate("b2", name: "Phone", kind: .iPhone)
        try list.trust(phone, method: .approval, at: t0 + 1)
        let data = try list.encoded()
        #expect(try TrustList(storage: data) == list)

        var json = try #require(String(data: data, encoding: .utf8))
        // Corrupt one record's key and give the other an unknown kind.
        json = json.replacingOccurrences(of: key("a1"), with: "bad key")
        json = json.replacingOccurrences(of: "\"iPhone\"", with: "\"watch\"")
        let read = try TrustList(storage: Data(json.utf8))
        #expect(read.devices.count == 1)
        #expect(read.device(phone.ref)?.kind == .other)
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

    @Test("Paired devices connect without a prompt, proven strangers are asked, the unproven are refused")
    func decide() throws {
        var list = TrustList()
        try list.trust(candidate("a1", device: ipadID), method: .code, at: t0)
        let paired = try #require(list.device(identityKeyID: key("a1"), deviceID: ipadID))

        #expect(PairingAdmission.decide(identityKeyID: key("a1"), deviceID: ipadID, isIdentityAuthenticated: true, trustList: list) == .autoGrant(paired))
        #expect(PairingAdmission.decide(identityKeyID: key("b2"), deviceID: ipadID, isIdentityAuthenticated: true, trustList: list)
            == .askUser(PairedDeviceRef(identityKeyID: key("b2"), deviceID: ipadID)))
        // The same key on another device (a synced key) is asked.
        #expect(PairingAdmission.decide(identityKeyID: key("a1"), deviceID: phoneID, isIdentityAuthenticated: true, trustList: list)
            == .askUser(PairedDeviceRef(identityKeyID: key("a1"), deviceID: phoneID)))
        // A paired key the handshake didn't verify is not trusted.
        #expect(PairingAdmission.decide(identityKeyID: key("a1"), deviceID: ipadID, isIdentityAuthenticated: false, trustList: list) == .refuse)
        #expect(PairingAdmission.decide(identityKeyID: nil, deviceID: ipadID, isIdentityAuthenticated: true, trustList: list) == .refuse)
        #expect(PairingAdmission.decide(identityKeyID: key("a1"), deviceID: nil, isIdentityAuthenticated: true, trustList: list) == .refuse)
        #expect(PairingAdmission.decide(identityKeyID: "short", deviceID: ipadID, isIdentityAuthenticated: true, trustList: list) == .refuse)
    }

    @Test("A forgotten device is asked again")
    func revokedIsAsked() throws {
        var list = TrustList()
        let a = candidate("a1", device: ipadID)
        try list.trust(a, method: .code, at: t0)
        list.revoke(a.ref)
        #expect(PairingAdmission.decide(identityKeyID: a.identityKeyID, deviceID: ipadID, isIdentityAuthenticated: true, trustList: list) == .askUser(a.ref))
    }
}

@Suite struct RemotePairingBookTests {

    private let mac = candidate("c3", name: "Studio Mac", kind: .mac)

    @Test("The Mac's report records and removes it")
    func followsTheMac() {
        var book = RemotePairingBook()
        let recorded = book.macReported(paired: true, mac: mac, at: t0)
        #expect(recorded == .recorded)
        #expect(book.macs.device(mac.ref) != nil)
        let again = book.macReported(paired: true, mac: mac, at: t0 + 1)
        #expect(again == .recorded)
        let removed = book.macReported(paired: false, mac: mac, at: t0 + 2)
        #expect(removed == .removed)
        let nothing = book.macReported(paired: false, mac: mac, at: t0 + 3)
        #expect(nothing == .none)
        #expect(book.macs.isEmpty)
    }

    @Test("Forgetting a connected Mac holds nothing back")
    func forgetConnected() {
        var book = RemotePairingBook()
        _ = book.macReported(paired: true, mac: mac, at: t0)
        let removed = book.forget(mac.ref, isConnected: true)
        #expect(removed != nil)
        #expect(book.pendingForgets.isEmpty)
        #expect(book.macs.isEmpty)
    }

    @Test("Forgetting a Mac that's away is sent the next time it says it's paired")
    func forgetAway() {
        var book = RemotePairingBook()
        _ = book.macReported(paired: true, mac: mac, at: t0)
        book.forget(mac.ref, isConnected: false)
        #expect(book.pendingForgets == [mac.ref])
        let action = book.macReported(paired: true, mac: mac, at: t0 + 1)
        #expect(action == .sendForget)
        #expect(book.pendingForgets.isEmpty)
        #expect(book.macs.isEmpty) // not recorded again
        // Next time it reports normally.
        let next = book.macReported(paired: true, mac: mac, at: t0 + 2)
        #expect(next == .recorded)
    }

    @Test("A held forget is dropped if the Mac already forgot this device")
    func forgetAlreadyDone() {
        var book = RemotePairingBook()
        book.forget(mac.ref, isConnected: false)
        let action = book.macReported(paired: false, mac: mac, at: t0)
        #expect(action == .none)
        #expect(book.pendingForgets.isEmpty)
    }

    @Test("Held forgets are capped and survive storage")
    func capAndStorage() throws {
        var book = RemotePairingBook()
        var refs: [PairedDeviceRef] = []
        for index in 0..<(RemotePairingBook.maxPendingForgets + 5) {
            let ref = PairedDeviceRef(identityKeyID: String(format: "%064x", index), deviceID: UUID())
            refs.append(ref)
            book.forget(ref, isConnected: false)
        }
        #expect(book.pendingForgets.count == RemotePairingBook.maxPendingForgets)
        #expect(book.pendingForgets.first == refs[5])
        book.forget(PairedDeviceRef(identityKeyID: "bad", deviceID: UUID()), isConnected: false)
        #expect(!book.pendingForgets.contains { $0.identityKeyID == "bad" })
        _ = book.macReported(paired: true, mac: mac, at: t0)
        #expect(try RemotePairingBook(storage: book.encoded()) == book)
    }
}
