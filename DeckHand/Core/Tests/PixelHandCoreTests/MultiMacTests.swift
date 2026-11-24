//
//  MultiMacTests.swift
//  PixelHandCoreTests
//
//  Multi-Mac (UX-030, backlog M1/M2): the Mac list's order and shortcut
//  slots, per-Mac memory, the switch state machine, the one-Mac rule in
//  front of a switch, and quick reconnect.
//

import Foundation
import PixelHandCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func mac(_ n: Int) -> UUID { UUID(uuidString: String(format: "BBBBBBBB-0000-0000-0000-%012d", n))! }
private let studio = mac(1)
private let laptop = mac(2)
private let mini = mac(3)
private let office = mac(4)
private let spare = mac(5)

@Suite("Multi-Mac roster")
struct MacRosterTests {
    @Test("Used Macs come first by first use, then paired, then others in reach")
    func order() {
        var memory = MacMemoryBook()
        memory.activated(deviceID: laptop, name: "Laptop", at: t0)
        memory.activated(deviceID: studio, name: "Studio", at: t0.addingTimeInterval(60))
        let listings = MacRoster.listings(
            discovered: [
                MacCandidate(deviceID: office, name: "Office"),
                MacCandidate(deviceID: spare, name: "Alpha", isOwnICloud: false),
                MacCandidate(deviceID: mini, name: "Zed mini", isOwnICloud: true),
                MacCandidate(deviceID: studio, name: "Studio"),
            ],
            paired: [MacPairing(deviceID: office, name: "Office", pairedAt: t0)],
            memory: memory,
            activeDeviceID: studio
        )
        #expect(listings.map(\.deviceID) == [laptop, studio, office, mini, spare])
        #expect(listings.map(\.slot) == [1, 2, 3, 4, nil])
        #expect(listings[1].isActive)
        #expect(listings[0].isReachable == false)
        #expect(listings[2].isPaired)
    }

    @Test("Switching doesn't reorder the list, so ⌘ slots keep naming the same Macs")
    func stableSlots() {
        var memory = MacMemoryBook()
        memory.activated(deviceID: studio, name: "Studio", at: t0)
        memory.activated(deviceID: laptop, name: "Laptop", at: t0.addingTimeInterval(10))
        memory.activated(deviceID: studio, name: "Studio", at: t0.addingTimeInterval(20))
        let found = [MacCandidate(deviceID: studio, name: "Studio"), MacCandidate(deviceID: laptop, name: "Laptop")]
        let listings = MacRoster.listings(discovered: found, paired: [], memory: memory, activeDeviceID: studio)
        #expect(MacRoster.mac(inSlot: 1, of: listings)?.deviceID == studio)
        #expect(MacRoster.mac(inSlot: 2, of: listings)?.deviceID == laptop)
        #expect(MacRoster.mac(inSlot: 3, of: listings) == nil)
    }

    @Test("Discovery's name wins over a remembered one")
    func renamed() {
        var memory = MacMemoryBook()
        memory.activated(deviceID: studio, name: "Old name", at: t0)
        let listings = MacRoster.listings(discovered: [MacCandidate(deviceID: studio, name: "Studio")], paired: [], memory: memory, activeDeviceID: nil)
        #expect(listings.first?.name == "Studio")
    }

    @Test("Next and previous step through reachable Macs and wrap")
    func neighbors() {
        let listings = [
            MacListing(deviceID: studio, name: "Studio", isActive: true, isReachable: true),
            MacListing(deviceID: laptop, name: "Laptop", isReachable: false),
            MacListing(deviceID: mini, name: "Mini", isReachable: true),
            MacListing(deviceID: office, name: "Office", isReachable: true),
        ]
        #expect(MacRoster.neighbor(of: studio, step: 1, in: listings)?.deviceID == mini)
        #expect(MacRoster.neighbor(of: studio, step: -1, in: listings)?.deviceID == office)
        #expect(MacRoster.neighbor(of: office, step: 1, in: listings)?.deviceID == studio)
        #expect(MacRoster.neighbor(of: nil, step: 1, in: listings)?.deviceID == studio)
        let alone = [MacListing(deviceID: studio, name: "Studio", isActive: true, isReachable: true)]
        #expect(MacRoster.neighbor(of: studio, step: 1, in: alone) == nil)
    }

    @Test("The slide follows the list: later is forward, earlier is backward")
    func direction() {
        let listings = [MacListing(deviceID: studio, name: "A"), MacListing(deviceID: laptop, name: "B")]
        #expect(MacRoster.direction(from: studio, to: laptop, in: listings) == .forward)
        #expect(MacRoster.direction(from: laptop, to: studio, in: listings) == .backward)
        #expect(MacRoster.direction(from: nil, to: studio, in: listings) == .forward)
    }

    @Test("Three fingers switch Macs only when on and another Mac is in reach")
    func threeFingerRule() {
        let one = [MacListing(deviceID: studio, name: "A", isActive: true, isReachable: true)]
        let two = one + [MacListing(deviceID: laptop, name: "B", isReachable: true)]
        let twoButAway = one + [MacListing(deviceID: laptop, name: "B", isReachable: false)]
        #expect(MacRoster.swipeSwitchesMacs(settingOn: true, listings: two))
        #expect(!MacRoster.swipeSwitchesMacs(settingOn: false, listings: two))
        #expect(!MacRoster.swipeSwitchesMacs(settingOn: true, listings: one))
        #expect(!MacRoster.swipeSwitchesMacs(settingOn: true, listings: twoButAway))
    }

    @Test("Glance lines: live for the focused Mac, remembered for others")
    func glanceCopy() {
        let now = t0.addingTimeInterval(3 * 3600)
        var active = MacListing(deviceID: studio, name: "Studio", isActive: true, isReachable: true)
        active.glance = MacGlance(frontApp: "Xcode", lockState: .unlocked, updatedAt: now)
        #expect(MacGlanceCopy.statusLine(for: active, now: now) == "Xcode")
        active.glance?.lockState = .screenLocked
        #expect(MacGlanceCopy.statusLine(for: active, now: now) == "Locked")

        var other = MacListing(deviceID: laptop, name: "Laptop", isReachable: true, isNearby: true)
        other.glance = MacGlance(frontApp: "Safari", updatedAt: t0)
        #expect(MacGlanceCopy.statusLine(for: other, now: now) == "Nearby · last in Safari")
        other.isReachable = false
        #expect(MacGlanceCopy.statusLine(for: other, now: now) == "Not found · seen 3 h ago")
        other.isConnecting = true
        other.isReachable = true
        #expect(MacGlanceCopy.statusLine(for: other, now: now) == "Connecting…")
    }
}

@Suite("Multi-Mac memory")
struct MacMemoryTests {
    @Test("Activating records first use once and moves last use")
    func activation() {
        var book = MacMemoryBook()
        book.activated(deviceID: studio, name: "Studio", at: t0)
        book.activated(deviceID: studio, name: "Studio", at: t0.addingTimeInterval(100))
        #expect(book.macs.count == 1)
        #expect(book.macs[0].firstUsedAt == t0)
        #expect(book.macs[0].lastUsedAt == t0.addingTimeInterval(100))
        #expect(book.lastActiveDeviceID == studio)
    }

    @Test("Per-Mac surface, deck page and mirror survive a round trip")
    func roundTrip() {
        var book = MacMemoryBook()
        book.activated(deviceID: studio, name: "Studio", at: t0)
        book.activated(deviceID: laptop, name: "Laptop", at: t0)
        book.update(studio) {
            $0.surface = "screen"
            $0.deckPageID = "page-xcode"
            $0.mirror = MacMirrorMemory(sharpness: "sharp", frameRate: 30)
            $0.glance = MacGlance(frontApp: "Xcode", lockState: .unlocked, link: .wired, updatedAt: t0)
        }
        book.update(laptop) { $0.surface = "deck" }
        let decoded = MacMemoryBook(storage: book.encoded())
        #expect(decoded == book)
        #expect(decoded.memory(for: studio)?.surface == "screen")
        #expect(decoded.memory(for: studio)?.mirror?.frameRate == 30)
        #expect(decoded.memory(for: laptop)?.surface == "deck")
        #expect(decoded.memory(for: laptop)?.mirror == nil)
    }

    @Test("Updating a Mac never used is ignored")
    func unknownUpdate() {
        var book = MacMemoryBook()
        book.update(studio) { $0.surface = "deck" }
        #expect(book.macs.isEmpty)
    }

    @Test("Unreadable storage starts empty")
    func garbage() {
        #expect(MacMemoryBook(storage: Data("nope".utf8)) == MacMemoryBook())
        #expect(MacMemoryBook(storage: nil) == MacMemoryBook())
    }

    @Test("Past capacity the least recently used Mac goes, never the last one")
    func capacity() {
        var book = MacMemoryBook()
        for n in 0 ..< MacMemoryBook.capacity + 3 {
            book.activated(deviceID: mac(100 + n), name: "Mac \(n)", at: t0.addingTimeInterval(Double(n)))
        }
        #expect(book.macs.count == MacMemoryBook.capacity)
        #expect(book.memory(for: mac(100)) == nil)
        #expect(book.memory(for: mac(100 + MacMemoryBook.capacity + 2)) != nil)
        #expect(book.lastActiveDeviceID == mac(100 + MacMemoryBook.capacity + 2))
    }

    @Test("Names are trimmed and capped")
    func names() {
        var book = MacMemoryBook()
        book.activated(deviceID: studio, name: "  Studio\n", at: t0)
        book.activated(deviceID: laptop, name: String(repeating: "x", count: 500), at: t0)
        #expect(book.memory(for: studio)?.name == "Studio")
        #expect(book.memory(for: laptop)?.name.count == MacMemoryBook.maximumNameLength)
    }

    @Test("Forget and Disconnect clear the reconnect target")
    func forget() {
        var book = MacMemoryBook()
        book.activated(deviceID: studio, name: "Studio", at: t0)
        book.clearLastActive()
        #expect(book.lastActiveDeviceID == nil)
        #expect(book.memory(for: studio) != nil)
        book.activated(deviceID: studio, name: "Studio", at: t0)
        book.forget(studio)
        #expect(book.lastActiveDeviceID == nil)
        #expect(book.macs.isEmpty)
    }
}

@Suite("Multi-Mac switch")
struct MacSwitchMachineTests {
    @Test("From no Mac, a request dials and success makes it active")
    func firstConnect() {
        var machine = MacSwitchMachine()
        let outcome = machine.request(studio, isReachable: true, admission: .allowed)
        #expect(outcome == .dial(target: studio, attempt: 1))
        #expect(machine.focusedDeviceID == nil)
        let r1 = machine.dialSucceeded(studio, attempt: 1)
        #expect(r1 == .adopt(studio, release: nil))
        #expect(machine.phase == .active(studio))
    }

    @Test("Switching keeps the old Mac focused until the new one connects, then releases it")
    func switchKeepsOld() {
        var machine = MacSwitchMachine()
        machine.adopted(studio)
        guard case let .dial(_, attempt) = machine.request(laptop, isReachable: true, admission: .allowed) else {
            Issue.record("expected a dial"); return
        }
        #expect(machine.focusedDeviceID == studio)
        #expect(machine.dialingDeviceID == laptop)
        let r2 = machine.dialSucceeded(laptop, attempt: attempt)
        #expect(r2 == .adopt(laptop, release: studio))
        #expect(machine.focusedDeviceID == laptop)
    }

    @Test("A failed dial leaves the old Mac in use")
    func failureStays() {
        var machine = MacSwitchMachine()
        machine.adopted(studio)
        guard case let .dial(_, attempt) = machine.request(laptop, isReachable: true, admission: .allowed) else {
            Issue.record("expected a dial"); return
        }
        let r3 = machine.dialFailed(laptop, attempt: attempt)
        #expect(r3)
        #expect(machine.phase == .active(studio))
    }

    @Test("A newer request supersedes a dial; the late connection is discarded")
    func supersede() {
        var machine = MacSwitchMachine()
        machine.adopted(studio)
        guard case let .dial(_, first) = machine.request(laptop, isReachable: true, admission: .allowed),
              case let .dial(_, second) = machine.request(mini, isReachable: true, admission: .allowed)
        else { Issue.record("expected dials"); return }
        let r4 = machine.dialSucceeded(laptop, attempt: first)
        #expect(r4 == .discard)
        let r5 = machine.dialFailed(laptop, attempt: first)
        #expect(!r5)
        let r6 = machine.dialSucceeded(mini, attempt: second)
        #expect(r6 == .adopt(mini, release: studio))
    }

    @Test("Going back to the Mac on screen cancels a dial in flight")
    func cancelBack() {
        var machine = MacSwitchMachine()
        machine.adopted(studio)
        guard case let .dial(_, attempt) = machine.request(laptop, isReachable: true, admission: .allowed) else {
            Issue.record("expected a dial"); return
        }
        let r7 = machine.request(studio, isReachable: true, admission: .allowed)
        #expect(r7 == .alreadyActive)
        let r8 = machine.dialSucceeded(laptop, attempt: attempt)
        #expect(r8 == .discard)
        #expect(machine.phase == .active(studio))
    }

    @Test("The focused Mac and a repeated request do nothing")
    func idempotent() {
        var machine = MacSwitchMachine()
        machine.adopted(studio)
        let r9 = machine.request(studio, isReachable: true, admission: .allowed)
        #expect(r9 == .alreadyActive)
        _ = machine.request(laptop, isReachable: true, admission: .allowed)
        let r10 = machine.request(laptop, isReachable: true, admission: .allowed)
        #expect(r10 == .alreadyActive)
    }

    @Test("A Mac out of reach isn't dialled")
    func unreachable() {
        var machine = MacSwitchMachine()
        machine.adopted(studio)
        let r11 = machine.request(laptop, isReachable: false, admission: .allowed)
        #expect(r11 == .unreachable)
        #expect(machine.phase == .active(studio))
    }

    @Test("The focused Mac dropping during a dial leaves the dial running from no Mac")
    func endedDuringDial() {
        var machine = MacSwitchMachine()
        machine.adopted(studio)
        guard case let .dial(_, attempt) = machine.request(laptop, isReachable: true, admission: .allowed) else {
            Issue.record("expected a dial"); return
        }
        machine.ended(studio)
        #expect(machine.focusedDeviceID == nil)
        let r12 = machine.dialSucceeded(laptop, attempt: attempt)
        #expect(r12 == .adopt(laptop, release: nil))
        machine.ended(laptop)
        #expect(machine.phase == .idle)
    }
}

@Suite("Multi-Mac free plan")
struct MacSwitchFreePlanTests {
    @Test("Without Pro, picking a second Mac opens the paywall and dials nothing")
    func secondMacNeedsPro() {
        let free = FreeMacChoice(deviceID: studio, name: "Studio")
        var machine = MacSwitchMachine()
        machine.adopted(studio)
        let admission = FreeMacPolicy.admit(deviceID: laptop, name: "Laptop", isPro: false, choice: free, now: t0)
        let r13 = machine.request(laptop, isReachable: true, admission: .init(admission))
        #expect(r13 == .paywall)
        #expect(machine.phase == .active(studio))
    }

    @Test("With Pro any Mac switches; the free Mac stays allowed without it")
    func proAndFreeMac() {
        let free = FreeMacChoice(deviceID: studio, name: "Studio")
        var machine = MacSwitchMachine()
        let pro = FreeMacPolicy.admit(deviceID: laptop, name: "Laptop", isPro: true, choice: free, now: t0)
        let r14 = machine.request(laptop, isReachable: true, admission: .init(pro))
        #expect(r14 == .dial(target: laptop, attempt: 1))
        var other = MacSwitchMachine()
        other.adopted(laptop)
        let back = FreeMacPolicy.admit(deviceID: studio, name: "Studio", isPro: false, choice: free, now: t0)
        let r15 = other.request(studio, isReachable: true, admission: .init(back))
        #expect(r15 == .dial(target: studio, attempt: 2))
    }

    @Test("Launch reconnect skips a Mac the free plan locks")
    func launchLocked() {
        let listings = [MacListing(deviceID: laptop, name: "Laptop", isReachable: true, isPaired: true)]
        let target = MacReconnectPolicy.launchTarget(
            isEnabled: true, hasCompletedOnboarding: true, alreadyTried: false, hasSession: false,
            lastActiveDeviceID: laptop, listings: listings, isLockedByFreePlan: { $0 == laptop }
        )
        #expect(target == nil)
    }
}

@Suite("Multi-Mac reconnect")
struct MacReconnectTests {
    private let listings = [
        MacListing(deviceID: studio, name: "Studio", isReachable: true, isPaired: true),
        MacListing(deviceID: laptop, name: "Laptop", isReachable: true),
        MacListing(deviceID: mini, name: "Mini", isReachable: false, isPaired: true),
    ]

    private func target(_ last: UUID?, enabled: Bool = true, onboarded: Bool = true, tried: Bool = false, session: Bool = false) -> UUID? {
        MacReconnectPolicy.launchTarget(
            isEnabled: enabled, hasCompletedOnboarding: onboarded, alreadyTried: tried, hasSession: session,
            lastActiveDeviceID: last, listings: listings, isLockedByFreePlan: { _ in false }
        )
    }

    @Test("At launch, the last Mac reconnects when it's paired and in reach")
    func launch() {
        #expect(target(studio) == studio)
        #expect(target(laptop) == nil) // would ask for approval
        #expect(target(mini) == nil) // not in reach
        #expect(target(nil) == nil)
        #expect(target(studio, enabled: false) == nil)
        #expect(target(studio, onboarded: false) == nil)
        #expect(target(studio, tried: true) == nil)
        #expect(target(studio, session: true) == nil)
    }

    @Test("Own iCloud Macs reconnect at launch without pairing")
    func iCloud() {
        let own = [MacListing(deviceID: laptop, name: "Laptop", isReachable: true, isOwnICloud: true)]
        let result = MacReconnectPolicy.launchTarget(
            isEnabled: true, hasCompletedOnboarding: true, alreadyTried: false, hasSession: false,
            lastActiveDeviceID: laptop, listings: own, isLockedByFreePlan: { _ in false }
        )
        #expect(result == laptop)
    }

    @Test("A drop redials with backoff, then stops; verdicts and Disconnect never redial")
    func redial() {
        let delays = (0 ..< 6).map { MacReconnectPolicy.redialDelay(isEnabled: true, attempt: $0, endedByVerdict: false, endedByUser: false) }
        #expect(delays == [1, 2, 4, 8, nil, nil])
        #expect(MacReconnectPolicy.redialDelay(isEnabled: true, attempt: 0, endedByVerdict: true, endedByUser: false) == nil)
        #expect(MacReconnectPolicy.redialDelay(isEnabled: true, attempt: 0, endedByVerdict: false, endedByUser: true) == nil)
        #expect(MacReconnectPolicy.redialDelay(isEnabled: false, attempt: 0, endedByVerdict: false, endedByUser: false) == nil)
    }
}
