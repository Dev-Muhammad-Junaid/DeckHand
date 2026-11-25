//
//  LastLANBookTests.swift
//  PixelHandCoreTests
//
//  VQ-069: the paired Mac's last LAN address, probed while Bonjour is
//  quiet, and when the picker looks again.
//
//  `#expect` can't wrap a mutating call, so results are bound first.
//

import Foundation
import PixelHandCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let studioKey = String(repeating: "a1", count: 32)
private let studioID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
private let studio = PairedDeviceRef(identityKeyID: studioKey, deviceID: studioID)

private func paired() throws -> TrustList {
    var list = TrustList()
    try list.trust(
        TrustCandidate(identityKeyID: studioKey, deviceID: studioID, name: "Studio", kind: .mac),
        method: .code,
        at: t0
    )
    return list
}

@Suite struct LastLANBookTests {
    @Test("A session on Wi-Fi or Ethernet records the Mac's private address")
    func recordsLAN() throws {
        let list = try paired()
        var book = LastLANBook()
        let wifi = book.sessionRan(overHost: "192.168.1.20", link: .wifi, mac: studio, pairedMacs: list, at: t0)
        #expect(wifi)
        #expect(book.address(for: studio)?.host.value == "192.168.1.20")
        let ethernet = book.sessionRan(overHost: "10.0.0.5", link: .ethernet, mac: studio, pairedMacs: list, at: t0 + 10)
        #expect(ethernet)
        #expect(book.seeds(pairedMacs: list, now: t0 + 10).map(\.value) == ["10.0.0.5"])
    }

    @Test("Cable, VPN, cellular, loopback and public addresses aren't kept", arguments: [
        ("169.254.10.2", LinkKind.wired),
        ("100.101.102.103", LinkKind.tunnel),
        ("192.168.1.20", LinkKind.cellular),
        ("127.0.0.1", LinkKind.loopback),
        ("192.168.1.20", LinkKind.unknown),
        ("17.253.144.10", LinkKind.wifi),
        ("studio.local", LinkKind.wifi),
        ("fe80::1%en0", LinkKind.wifi),
    ])
    func ignoresNonLAN(host: String, link: LinkKind) throws {
        var book = LastLANBook()
        let changed = book.sessionRan(overHost: host, link: link, mac: studio, pairedMacs: try paired(), at: t0)
        #expect(!changed)
        #expect(book.address(for: studio) == nil)
    }

    @Test("A unique-local IPv6 address is kept without its zone")
    func uniqueLocalIPv6() throws {
        var book = LastLANBook()
        let changed = book.sessionRan(overHost: "fd12:3456:789a::1", link: .wifi, mac: studio, pairedMacs: try paired(), at: t0)
        #expect(changed)
    }

    @Test("Only paired Macs get an address, and forgetting drops it")
    func pairedOnly() throws {
        var book = LastLANBook()
        let stranger = book.sessionRan(overHost: "192.168.1.20", link: .wifi, mac: studio, pairedMacs: TrustList(), at: t0)
        #expect(!stranger)
        _ = book.sessionRan(overHost: "192.168.1.20", link: .wifi, mac: studio, pairedMacs: try paired(), at: t0)
        #expect(book.seeds(pairedMacs: TrustList(), now: t0).isEmpty)
        let pruned = book.prune(pairedMacs: TrustList())
        #expect(pruned)
        #expect(book.address(for: studio) == nil)
    }

    @Test("The same address within a day doesn't rewrite the file")
    func sameAddressQuiet() throws {
        let list = try paired()
        var book = LastLANBook()
        _ = book.sessionRan(overHost: "192.168.1.20", link: .wifi, mac: studio, pairedMacs: list, at: t0)
        let again = book.sessionRan(overHost: "192.168.1.20", link: .wifi, mac: studio, pairedMacs: list, at: t0 + 60)
        #expect(!again)
        let nextDay = book.sessionRan(overHost: "192.168.1.20", link: .wifi, mac: studio, pairedMacs: list, at: t0 + 90_000)
        #expect(nextDay)
    }

    @Test("Addresses older than 30 days are not probed")
    func stale() throws {
        let list = try paired()
        var book = LastLANBook()
        _ = book.sessionRan(overHost: "192.168.1.20", link: .wifi, mac: studio, pairedMacs: list, at: t0)
        #expect(book.seeds(pairedMacs: list, now: t0 + LastLANBook.maxAge - 1).count == 1)
        #expect(book.seeds(pairedMacs: list, now: t0 + LastLANBook.maxAge + 1).isEmpty)
    }

    @Test("The book round-trips through storage and fails closed")
    func storage() throws {
        let list = try paired()
        var book = LastLANBook()
        _ = book.sessionRan(overHost: "192.168.1.20", link: .wifi, mac: studio, pairedMacs: list, at: t0)
        let decoded = try LastLANBook(storage: try book.encoded())
        #expect(decoded == book)
        let future = Data(#"{"version":99,"macs":[]}"#.utf8)
        #expect(throws: LastLANBook.StorageError.unsupportedVersion(99)) { try LastLANBook(storage: future) }
    }

    @Test("The picker looks again on a schedule while no Mac is listed")
    func refreshPlan() {
        #expect(LANFallbackPlan.refreshTimes == LANFallbackPlan.refreshTimes.sorted())
        #expect(LANFallbackPlan.refreshTimes.first! < LANFallbackPlan.checksDelay)
        #expect(LANFallbackPlan.refreshGaps.reduce(0, +) == LANFallbackPlan.refreshTimes.last!)
        #expect(LANFallbackPlan.refreshGaps.allSatisfy { $0 > 0 })
        #expect(LANFallbackPlan.shouldRefresh(peersListed: false, discoveryRunning: true))
        #expect(!LANFallbackPlan.shouldRefresh(peersListed: true, discoveryRunning: true))
        #expect(!LANFallbackPlan.shouldRefresh(peersListed: false, discoveryRunning: false))
    }
}
