//
//  RemoteAccessTests.swift
//  PixelHandCoreTests
//
//  S15: remote access over a VPN. Host validation, the saved-host book,
//  dial pinning and unpaired refusal on the remote, remote-path admission
//  on the Mac, the Mac's reportable addresses, and "away" mirror quality.
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
private let macID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
private let otherMacID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!

private func paired(_ keySeed: String, device: UUID = macID, at date: Date = t0) -> PairedDevice {
    PairedDevice(
        identityKeyID: key(keySeed), deviceID: device, name: "Studio Mac", kind: .mac,
        method: .remoteRecord, pairedAt: date, lastSeenAt: date
    )
}

private func host(_ s: String) -> RemoteHost {
    RemoteHost(s)!
}

private func rejection(_ s: String) -> RemoteHost.Rejection? {
    if case let .failure(r) = RemoteHost.parse(s) { return r }
    return nil
}

// MARK: - Host validation

@Suite("RemoteHost: endpoint validation")
struct RemoteHostTests {

    @Test("Tailscale IPv4, IPv6 and MagicDNS names are accepted and classified as overlay")
    func tailscaleKinds() {
        #expect(host("100.101.102.103").kind == .tailscaleIPv4)
        #expect(host("100.64.0.1").kind == .tailscaleIPv4)
        #expect(host("100.127.255.254").kind == .tailscaleIPv4)
        #expect(host("fd7a:115c:a1e0::1").kind == .tailscaleIPv6)
        #expect(host("studio-mac.tail1234.ts.net").kind == .magicDNS)
        #expect(host("100.101.102.103").kind.isOverlay)
        #expect(host("studio-mac.tail1234.ts.net").kind.isOverlay)
    }

    @Test("Addresses just outside Tailscale's ranges are not overlay")
    func tailscaleBoundaries() {
        #expect(host("100.63.255.255").kind == .publicIP)
        #expect(host("100.128.0.1").kind == .publicIP)
        #expect(host("fd7a:115c:a1e1::1").kind == .uniqueLocalIPv6)
        #expect(!RemoteHost.isOverlayAddress("100.128.0.1"))
        #expect(RemoteHost.isOverlayAddress("100.100.100.100"))
        #expect(RemoteHost.isOverlayAddress("::ffff:100.100.100.100"))
        #expect(RemoteHost.isOverlayAddress("fd7a:115c:a1e0:ab12::5%utun4"))
        #expect(!RemoteHost.isOverlayAddress("192.168.1.2"))
        #expect(!RemoteHost.isOverlayAddress(nil))
        #expect(!RemoteHost.isOverlayAddress("studio.local"))
    }

    @Test("Private, ULA, public and plain host names are classified")
    func otherKinds() {
        #expect(host("10.0.0.5").kind == .privateIPv4)
        #expect(host("172.16.0.1").kind == .privateIPv4)
        #expect(host("172.31.255.1").kind == .privateIPv4)
        #expect(host("172.32.0.1").kind == .publicIP)
        #expect(host("192.168.50.2").kind == .privateIPv4)
        #expect(host("fd12:3456::1").kind == .uniqueLocalIPv6)
        #expect(host("2001:db8::1").kind == .publicIP)
        #expect(host("8.8.8.8").kind == .publicIP)
        #expect(host("mac.example.com").kind == .hostname)
        #expect(host("studio").kind == .hostname)
    }

    @Test("Input is normalised: spaces, case, brackets, trailing dot, IPv6 zero runs")
    func normalisation() {
        #expect(host("  Studio-Mac.Tail1234.TS.NET.  ").value == "studio-mac.tail1234.ts.net")
        #expect(host("[FD7A:115C:A1E0:0:0:0:0:1]").value == "fd7a:115c:a1e0::1")
        #expect(host("2001:0db8:0000:0000:0001:0000:0000:0001").value == "2001:db8::1:0:0:1")
        #expect(host("::ffff:10.0.0.1").kind == .privateIPv4)
        #expect(host("100.101.102.103") == host(" 100.101.102.103 "))
    }

    @Test("URLs, ports, paths, users, zones and spaces are refused as not-a-host")
    func notAHost() {
        for input in [
            "http://100.101.102.103", "ssh://mac", "100.101.102.103:4242", "mac.ts.net:22",
            "mac/path", "user@mac", "fe80::1%en0", "mac name", "mac?x=1", "mac#frag",
            "[fd7a::1]:80", "a,b", "mac;rm",
        ] {
            #expect(rejection(input) == .notAHost, "\(input)")
        }
    }

    @Test("Malformed names and literals are refused")
    func malformed() {
        for input in [
            "256.1.1.1", "1.2.3", "1.2.3.4.5", "01.2.3.4", "-mac", "mac-", "mac..ts.net",
            String(repeating: "a", count: 64) + ".com", "mäc.local", "1:2:3:4:5:6:7:8:9",
            "fd7a::1::2", "12345::1", "gggg::1", "_mac.local", "123",
        ] {
            #expect(rejection(input) == .malformed, "\(input)")
        }
    }

    @Test("Loopback, link-local, multicast, broadcast and unspecified are refused")
    func unroutable() {
        #expect(rejection("127.0.0.1") == .loopback)
        #expect(rejection("::1") == .loopback)
        #expect(rejection("localhost") == .loopback)
        #expect(rejection("mac.localhost") == .loopback)
        #expect(rejection("::ffff:127.0.0.1") == .loopback)
        #expect(rejection("169.254.10.20") == .linkLocal)
        #expect(rejection("fe80::1") == .linkLocal)
        #expect(rejection("febf::1") == .linkLocal)
        #expect(rejection("0.0.0.0") == .unusable)
        #expect(rejection("::") == .unusable)
        #expect(rejection("224.0.0.251") == .unusable)
        #expect(rejection("255.255.255.255") == .unusable)
        #expect(rejection("ff02::fb") == .unusable)
    }

    @Test("Empty and over-long input is refused")
    func emptyAndLong() {
        #expect(rejection("") == .empty)
        #expect(rejection("   ") == .empty)
        #expect(rejection(".") == .empty)
        let long = Array(repeating: String(repeating: "a", count: 60), count: 5).joined(separator: ".")
        #expect(rejection(long) == .tooLong)
        let fits = Array(repeating: String(repeating: "a", count: 62), count: 4).joined(separator: ".")
        #expect(fits.count == 251)
        #expect(RemoteHost(fits) != nil)
    }

    @Test("Every rejection has a message for Settings")
    func messages() {
        for r: RemoteHost.Rejection in [.empty, .tooLong, .notAHost, .malformed, .loopback, .linkLocal, .unusable] {
            #expect(!r.message.isEmpty)
        }
    }

    @Test("Decoding re-validates: a stored host parse would refuse fails to decode")
    func decodeRevalidates() throws {
        let good = try JSONDecoder().decode([RemoteHost].self, from: Data(#"["100.101.102.103"]"#.utf8))
        #expect(good == [host("100.101.102.103")])
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode([RemoteHost].self, from: Data(#"["http://evil"]"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode([RemoteHost].self, from: Data(#"["127.0.0.1"]"#.utf8))
        }
    }
}

// MARK: - Saved hosts

@Suite("RemoteHostBook: saved hosts per paired Mac")
struct RemoteHostBookTests {
    let mac = paired("a")
    var pairedMacs: TrustList { TrustList(devices: [mac]) }

    @Test("A host can be saved for a paired Mac and becomes a seed")
    func addForPaired() {
        var book = RemoteHostBook()
        let result = book.add("studio.tail1.ts.net", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        #expect(result == .success(host("studio.tail1.ts.net")))
        #expect(book.hosts(for: mac.ref).map(\.source) == [.user])
        #expect(book.seeds(pairedMacs: pairedMacs) == [host("studio.tail1.ts.net")])
    }

    @Test("Saving a host for a Mac that isn't paired is refused")
    func addForUnpaired() {
        var book = RemoteHostBook()
        let stranger = paired("b", device: otherMacID)
        let result = book.add("100.100.1.1", for: stranger.ref, pairedMacs: pairedMacs, at: t0)
        #expect(result == .failure(.notPaired))
        #expect(book.entries.isEmpty)
    }

    @Test("Same device ID with another key is not paired")
    func addForChangedKey() {
        var book = RemoteHostBook()
        let rekeyed = PairedDeviceRef(identityKeyID: key("c"), deviceID: macID)
        let result = book.add("100.100.1.1", for: rekeyed, pairedMacs: pairedMacs, at: t0)
        #expect(result == .failure(.notPaired))
    }

    @Test("Invalid hosts, duplicates and a full list are refused")
    func addRefusals() {
        var book = RemoteHostBook()
        let bad = book.add("http://x", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        #expect(bad == .failure(.invalid(.notAHost)))
        _ = book.add("100.100.1.1", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        let dup = book.add(" 100.100.1.1 ", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        #expect(dup == .failure(.duplicate))
        for i in 2...RemoteHostBook.maxUserHostsPerMac {
            _ = book.add("100.100.1.\(i)", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        }
        let full = book.add("100.100.2.1", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        #expect(full == .failure(.full))
        #expect(book.hosts(for: mac.ref).count == RemoteHostBook.maxUserHostsPerMac)
    }

    @Test("A Mac's report keeps only valid hosts, at most four, and replaces the last report")
    func macReport() {
        var book = RemoteHostBook()
        let changed = book.macReported(
            ["100.64.1.1", "http://bad", "127.0.0.1", "100.64.1.1", "fd7a:115c:a1e0::2", "10.8.0.2", "10.8.0.3", "10.8.0.4"],
            mac: mac.ref, pairedMacs: pairedMacs, at: t0
        )
        #expect(changed)
        #expect(book.hosts(for: mac.ref).map(\.host.value) == ["100.64.1.1", "fd7a:115c:a1e0::2", "10.8.0.2", "10.8.0.3"])
        #expect(book.hosts(for: mac.ref).allSatisfy { $0.source == .mac })

        let again = book.macReported(["100.64.1.1", "fd7a:115c:a1e0::2", "10.8.0.2", "10.8.0.3"], mac: mac.ref, pairedMacs: pairedMacs, at: t0.addingTimeInterval(60))
        #expect(!again)
        #expect(book.hosts(for: mac.ref).first?.addedAt == t0)

        let cleared = book.macReported([], mac: mac.ref, pairedMacs: pairedMacs, at: t0)
        #expect(cleared)
        #expect(book.entries.isEmpty)
    }

    @Test("A report never removes or duplicates a host the user saved")
    func reportKeepsUserHosts() {
        var book = RemoteHostBook()
        _ = book.add("studio.tail1.ts.net", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        _ = book.add("100.64.1.1", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        book.macReported(["100.64.1.1", "100.64.1.2"], mac: mac.ref, pairedMacs: pairedMacs, at: t0)
        #expect(book.hosts(for: mac.ref).map(\.host.value) == ["studio.tail1.ts.net", "100.64.1.1", "100.64.1.2"])
        #expect(book.hosts(for: mac.ref).map(\.source) == [.user, .user, .mac])
        book.macReported([], mac: mac.ref, pairedMacs: pairedMacs, at: t0)
        #expect(book.hosts(for: mac.ref).map(\.source) == [.user, .user])
    }

    @Test("Saving a host the Mac reported turns it into a user host")
    func adoptReported() {
        var book = RemoteHostBook()
        book.macReported(["100.64.1.1"], mac: mac.ref, pairedMacs: pairedMacs, at: t0)
        let result = book.add("100.64.1.1", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        #expect(result == .success(host("100.64.1.1")))
        #expect(book.hosts(for: mac.ref).map(\.source) == [.user])
    }

    @Test("Reports from a Mac that isn't paired are ignored")
    func reportFromUnpaired() {
        var book = RemoteHostBook()
        let stranger = PairedDeviceRef(identityKeyID: key("b"), deviceID: otherMacID)
        let changed = book.macReported(["100.64.1.1"], mac: stranger, pairedMacs: pairedMacs, at: t0)
        #expect(!changed)
        #expect(book.entries.isEmpty)
    }

    @Test("Forgetting a Mac removes its hosts from the seeds at once, and prune drops them")
    func forgottenMacsAreNotSeeds() {
        var book = RemoteHostBook()
        let second = paired("b", device: otherMacID)
        let both = TrustList(devices: [mac, second])
        _ = book.add("100.64.1.1", for: mac.ref, pairedMacs: both, at: t0)
        _ = book.add("100.64.1.2", for: second.ref, pairedMacs: both, at: t0)
        #expect(Set(book.seeds(pairedMacs: both)) == [host("100.64.1.1"), host("100.64.1.2")])

        let onlySecond = TrustList(devices: [second])
        #expect(book.seeds(pairedMacs: onlySecond) == [host("100.64.1.2")])
        #expect(book.seeds(pairedMacs: TrustList()).isEmpty)
        let pruned = book.prune(pairedMacs: onlySecond)
        #expect(pruned)
        #expect(book.entries.keys.map(\.deviceID) == [otherMacID])
    }

    @Test("Seeds list each host once, user hosts first")
    func seedOrder() {
        var book = RemoteHostBook()
        book.macReported(["100.64.1.9"], mac: mac.ref, pairedMacs: pairedMacs, at: t0)
        _ = book.add("studio.tail1.ts.net", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        #expect(book.seeds(pairedMacs: pairedMacs) == [host("studio.tail1.ts.net"), host("100.64.1.9")])
    }

    @Test("Storage round-trips; tampered or foreign data fails to load")
    func storage() throws {
        var book = RemoteHostBook()
        _ = book.add("studio.tail1.ts.net", for: mac.ref, pairedMacs: pairedMacs, at: t0)
        book.macReported(["100.64.1.9"], mac: mac.ref, pairedMacs: pairedMacs, at: t0)
        let data = try book.encoded()
        #expect(try RemoteHostBook(storage: data) == book)

        let tampered = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "100.64.1.9", with: "127.0.0.1")
        #expect(throws: (any Error).self) { _ = try RemoteHostBook(storage: Data(tampered.utf8)) }
        let wrongVersion = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"version\":1", with: "\"version\":99")
        #expect(throws: (any Error).self) { _ = try RemoteHostBook(storage: Data(wrongVersion.utf8)) }
        #expect(throws: (any Error).self) { _ = try RemoteHostBook(storage: Data("nope".utf8)) }
    }
}

// MARK: - Dialling: pinning and unpaired refusal

@Suite("RemoteAccessPolicy: dialling a Mac off the local network")
struct RemoteDialTests {
    let mac = paired("a")

    @Test("A Mac Bonjour sees is dialled as before, paired or not")
    func nearbyIsLocal() {
        let reach = RemoteAccessPolicy.PeerReach(deviceID: otherMacID, isNearby: true, advertisedIdentityKeyID: key("z"))
        #expect(RemoteAccessPolicy.dialPlan(for: reach, pairedMacs: TrustList()) == .local)
    }

    @Test("A remote Mac that isn't paired is refused before dialling")
    func unpairedRemoteRefused() {
        let reach = RemoteAccessPolicy.PeerReach(deviceID: otherMacID, isNearby: false, advertisedIdentityKeyID: key("b"))
        #expect(RemoteAccessPolicy.dialPlan(for: reach, pairedMacs: TrustList(devices: [mac])) == .refuse(.notPaired))
        #expect(RemoteAccessPolicy.dialPlan(for: reach, pairedMacs: TrustList()) == .refuse(.notPaired))
    }

    @Test("A paired remote Mac is dialled pinned to the stored key")
    func pairedRemotePinned() {
        let reach = RemoteAccessPolicy.PeerReach(deviceID: macID, isNearby: false, advertisedIdentityKeyID: key("a"))
        #expect(RemoteAccessPolicy.dialPlan(for: reach, pairedMacs: TrustList(devices: [mac])) == .remote(pinned: mac.ref))
    }

    @Test("Without an advertised key the pin still comes from the store")
    func pinWithoutAdvertisement() {
        let reach = RemoteAccessPolicy.PeerReach(deviceID: macID, isNearby: false, advertisedIdentityKeyID: nil)
        #expect(RemoteAccessPolicy.dialPlan(for: reach, pairedMacs: TrustList(devices: [mac])) == .remote(pinned: mac.ref))
    }

    @Test("A paired device ID advertising another key is refused, never pinned to the advertised key")
    func advertisedKeyMismatch() {
        let reach = RemoteAccessPolicy.PeerReach(deviceID: macID, isNearby: false, advertisedIdentityKeyID: key("e"))
        let plan = RemoteAccessPolicy.dialPlan(for: reach, pairedMacs: TrustList(devices: [mac]))
        #expect(plan == .refuse(.keyChanged))
        #expect(!RemoteAccessPolicy.DialRefusal.keyChanged.message.isEmpty)
        #expect(!RemoteAccessPolicy.DialRefusal.notPaired.message.isEmpty)
    }

    @Test("A pairing record for another Mac with the same key doesn't pin this device ID")
    func sharedKeyOtherDevice() {
        // iCloud Keychain: one owner's two Macs can share a key.
        let reach = RemoteAccessPolicy.PeerReach(deviceID: otherMacID, isNearby: false, advertisedIdentityKeyID: key("a"))
        #expect(RemoteAccessPolicy.dialPlan(for: reach, pairedMacs: TrustList(devices: [mac])) == .refuse(.notPaired))
    }

    @Test("After the handshake, key and device ID must both match the pin")
    func verify() {
        #expect(RemoteAccessPolicy.verify(provenIdentityKeyID: key("a"), provenDeviceID: macID, pinned: mac.ref))
        #expect(!RemoteAccessPolicy.verify(provenIdentityKeyID: key("b"), provenDeviceID: macID, pinned: mac.ref))
        #expect(!RemoteAccessPolicy.verify(provenIdentityKeyID: key("a"), provenDeviceID: otherMacID, pinned: mac.ref))
        #expect(!RemoteAccessPolicy.verify(provenIdentityKeyID: nil, provenDeviceID: macID, pinned: mac.ref))
        #expect(!RemoteAccessPolicy.verify(provenIdentityKeyID: key("a"), provenDeviceID: nil, pinned: mac.ref))
    }
}

// MARK: - Testing a saved host

@Suite("RemoteAccessPolicy: testing a saved host")
struct ProbeVerdictTests {
    let mac = paired("a").ref

    @Test("The paired Mac answering with its stored key is reachable")
    func reachable() {
        #expect(RemoteAccessPolicy.probeVerdict(answers: [(macID, key("a"))], mac: mac) == .reachable)
    }

    @Test("Another Mac, or the same device ID with another key, is a different Mac")
    func different() {
        #expect(RemoteAccessPolicy.probeVerdict(answers: [(otherMacID, key("a"))], mac: mac) == .differentMac)
        #expect(RemoteAccessPolicy.probeVerdict(answers: [(macID, key("b"))], mac: mac) == .differentMac)
        #expect(RemoteAccessPolicy.probeVerdict(answers: [(macID, nil)], mac: mac) == .differentMac)
    }

    @Test("No answer is no answer")
    func none() {
        #expect(RemoteAccessPolicy.probeVerdict(answers: [], mac: mac) == .noAnswer)
        for v: RemoteAccessPolicy.ProbeVerdict in [.reachable, .differentMac, .noAnswer] {
            #expect(!v.message.isEmpty)
        }
    }
}

// MARK: - Mac admission over a remote path

@Suite("RemoteAccessPolicy: Mac admission over a remote path")
struct RemoteAdmissionTests {
    let device = PairedDevice(
        identityKeyID: key("d"), deviceID: macID, name: "iPad", kind: .iPad,
        method: .code, pairedAt: t0, lastSeenAt: t0
    )

    @Test("Tunnels, overlay addresses, cellular and loopback are remote paths")
    func remotePaths() {
        #expect(RemoteAccessPolicy.isRemotePath(link: .tunnel, remoteHost: "10.8.0.2"))
        #expect(RemoteAccessPolicy.isRemotePath(link: .wifi, remoteHost: "100.101.1.2"))
        #expect(RemoteAccessPolicy.isRemotePath(link: .unknown, remoteHost: "fd7a:115c:a1e0::9"))
        #expect(RemoteAccessPolicy.isRemotePath(link: .cellular, remoteHost: nil))
        #expect(RemoteAccessPolicy.isRemotePath(link: .loopback, remoteHost: "127.0.0.1"))
        #expect(RemoteAccessPolicy.isRemotePath(link: .unknown, remoteHost: "::1"))
        #expect(RemoteAccessPolicy.isRemotePath(link: .unknown, remoteHost: "127.0.0.1"))
    }

    @Test("LAN links are not remote paths")
    func localPaths() {
        for link: LinkKind in [.wired, .ethernet, .wifi, .peerToPeer, .other, .unknown] {
            #expect(!RemoteAccessPolicy.isRemotePath(link: link, remoteHost: "192.168.1.20"), "\(link)")
        }
        #expect(!RemoteAccessPolicy.isRemotePath(link: .wifi, remoteHost: "fe80::1%en0"))
        #expect(!RemoteAccessPolicy.isRemotePath(link: .wifi, remoteHost: "2001:db8::5"))
    }

    @Test("Over a remote path only a paired device is admitted; no prompt, no code")
    func remoteAdmission() {
        let ask = PairingAdmission.askUser(device.ref)
        #expect(RemoteAccessPolicy.admission(.autoGrant(device), isRemotePath: true) == .autoGrant(device))
        #expect(RemoteAccessPolicy.admission(ask, isRemotePath: true) == .refuse)
        #expect(RemoteAccessPolicy.admission(.refuse, isRemotePath: true) == .refuse)
    }

    @Test("On a local path the pairing decision stands")
    func localAdmission() {
        let ask = PairingAdmission.askUser(device.ref)
        #expect(RemoteAccessPolicy.admission(ask, isRemotePath: false) == ask)
        #expect(RemoteAccessPolicy.admission(.autoGrant(device), isRemotePath: false) == .autoGrant(device))
        #expect(RemoteAccessPolicy.admission(.refuse, isRemotePath: false) == .refuse)
    }

    @Test("End to end: an unknown key over Tailscale is refused, a paired one admitted")
    func endToEnd() {
        let list = TrustList(devices: [device])
        let strangerDecision = PairingAdmission.decide(identityKeyID: key("f"), deviceID: otherMacID, isIdentityAuthenticated: true, trustList: list)
        let pairedDecision = PairingAdmission.decide(identityKeyID: key("d"), deviceID: macID, isIdentityAuthenticated: true, trustList: list)
        let remote = RemoteAccessPolicy.isRemotePath(link: .wifi, remoteHost: "100.90.1.1")
        #expect(RemoteAccessPolicy.admission(strangerDecision, isRemotePath: remote) == .refuse)
        #expect(RemoteAccessPolicy.admission(pairedDecision, isRemotePath: remote) == .autoGrant(device))
    }
}

// MARK: - The Mac's reportable addresses

@Suite("RemoteAccessPolicy: the Mac's VPN addresses")
struct ReportableHostsTests {

    @Test("Tunnel and Tailscale addresses are reported; LAN, link-local and loopback are not")
    func filter() {
        let owners = [
            "192.168.1.20": "en0",
            "fe80::1%en0": "en0",
            "fe80::abcd%utun3": "utun3",
            "100.101.102.103": "utun4",
            "fd7a:115c:a1e0::abcd": "utun4",
            "10.8.0.2": "utun5",
            "127.0.0.1": "lo0",
            "2001:db8::5": "en0",
        ]
        #expect(RemoteAccessPolicy.reportableHosts(addressOwners: owners) == ["100.101.102.103", "10.8.0.2", "fd7a:115c:a1e0::abcd"])
    }

    @Test("A Tailscale address counts on any interface name")
    func overlayOnOddInterface() {
        #expect(RemoteAccessPolicy.reportableHosts(addressOwners: ["100.70.0.1": "en9"]) == ["100.70.0.1"])
    }

    @Test("At most four addresses, Tailscale IPv4 first")
    func capAndOrder() {
        var owners: [String: String] = [:]
        for i in 1...6 { owners["10.9.0.\(i)"] = "wg0" }
        owners["100.64.0.7"] = "utun2"
        let hosts = RemoteAccessPolicy.reportableHosts(addressOwners: owners)
        #expect(hosts.count == RemoteAccessPolicy.maxReportedHosts)
        #expect(hosts.first == "100.64.0.7")
    }

    @Test("Nothing on a Mac without a VPN")
    func none() {
        #expect(RemoteAccessPolicy.reportableHosts(addressOwners: ["192.168.1.20": "en0", "fe80::1%en0": "en0"]).isEmpty)
    }
}

// MARK: - Link judging with overlay addresses

@Suite("LinkJudge: overlay peers")
struct OverlayLinkTests {

    @Test("A Tailscale peer address is a tunnel even when the interface doesn't say so")
    func overlayAddressIsTunnel() {
        let o = LinkObservation(interfaceName: "en0", usesWiFi: true, remoteHost: "100.101.102.103")
        #expect(LinkJudge.judge(o) == .tunnel)
        #expect(LinkKind.tunnel.displayName == "VPN")
    }

    @Test("A LAN peer on Wi-Fi is still Wi-Fi")
    func lanStaysWiFi() {
        let o = LinkObservation(interfaceName: "en0", usesWiFi: true, remoteHost: "192.168.1.5")
        #expect(LinkJudge.judge(o) == .wifi)
    }
}

// MARK: - Away quality

@Suite("AwayQualityPolicy and RoundTripEstimator")
struct AwayQualityTests {
    let request = MirrorRequestShape(fps: 30, maxWidth: 1_920, codec: .jpeg)

    @Test("At home the request passes unchanged")
    func home() {
        var policy = AwayQualityPolicy()
        policy.setLink(.wifi)
        #expect(!policy.isAway)
        #expect(policy.adjust(request, hevcAvailable: true) == request)
    }

    @Test("Over a VPN: 15 fps, HEVC preferred, width capped for the codec")
    func tunnel() {
        var policy = AwayQualityPolicy()
        let changed = policy.setLink(.tunnel)
        #expect(changed)
        #expect(policy.isAway)
        #expect(policy.adjust(request, hevcAvailable: true) == MirrorRequestShape(fps: 15, maxWidth: 1_280, codec: .hevc))
        #expect(policy.adjust(request, hevcAvailable: false) == MirrorRequestShape(fps: 15, maxWidth: 960, codec: .jpeg))
    }

    @Test("Away never raises settings that are already lower")
    func neverRaises() {
        var policy = AwayQualityPolicy()
        policy.setLink(.cellular)
        let low = MirrorRequestShape(fps: 10, maxWidth: 640, codec: .hevc)
        #expect(policy.adjust(low, hevcAvailable: true) == low)
    }

    @Test("A long round trip is away, with hysteresis on the way back")
    func roundTripHysteresis() {
        var policy = AwayQualityPolicy()
        policy.setLink(.wifi)
        let a = policy.noteRoundTrip(0.100)
        #expect(!a && !policy.isAway)
        let b = policy.noteRoundTrip(0.130)
        #expect(b && policy.isAway)
        let c = policy.noteRoundTrip(0.090)
        #expect(!c && policy.isAway)
        let d = policy.noteRoundTrip(0.060)
        #expect(d && !policy.isAway)
        let e = policy.noteRoundTrip(nil)
        #expect(!e)
    }

    @Test("A slow round trip on a tunnel doesn't report a change")
    func noDoubleChange() {
        var policy = AwayQualityPolicy()
        policy.setLink(.tunnel)
        let changed = policy.noteRoundTrip(0.300)
        #expect(!changed)
        #expect(policy.isAway)
        let backToWiFi = policy.setLink(.wifi)
        #expect(!backToWiFi) // still away by round trip
    }

    @Test("Round trips are matched by sequence and smoothed")
    func estimator() {
        var rtt = RoundTripEstimator()
        rtt.pingSent(seq: 1, at: 10.0)
        let first = rtt.pongReceived(seq: 1, at: 10.1)
        #expect(abs((first ?? 0) - 0.1) < 1e-9)
        rtt.pingSent(seq: 2, at: 12.0)
        let second = rtt.pongReceived(seq: 2, at: 12.9)
        #expect(abs((second ?? 0) - 0.2) < 1e-9) // 0.1 + (0.9 - 0.1) / 8
        #expect(abs((rtt.latest ?? 0) - 0.9) < 1e-9)
        let unknown = rtt.pongReceived(seq: 99, at: 13)
        #expect(unknown == nil)
        let repeated = rtt.pongReceived(seq: 2, at: 13)
        #expect(repeated == nil)
    }

    @Test("Older unanswered pings are dropped and the table stays bounded")
    func estimatorBounds() {
        var rtt = RoundTripEstimator()
        for seq in 1...40 { rtt.pingSent(seq: UInt64(seq), at: Double(seq)) }
        let old = rtt.pongReceived(seq: 1, at: 41)
        #expect(old == nil)
        let fresh = rtt.pongReceived(seq: 40, at: 40.05)
        #expect(fresh != nil)
        let stale = rtt.pongReceived(seq: 39, at: 40.1)
        #expect(stale == nil)
        rtt.reset()
        #expect(rtt.smoothed == nil)
    }
}
