//
//  LockPolicyTests.swift
//  PixelHandCoreTests
//
//  S8: a locked Mac shows and does no more for a remote than for someone
//  standing at it. Any witness saying locked wins, an unlock only counts
//  once it has settled, and each request is judged against the state.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct LockPolicyTests {

    // MARK: Witnesses → reading

    @Test("No witness answered: unknown")
    func noAnswerIsUnknown() {
        #expect(LockPolicy.reading(LockWitnesses()) == nil)
    }

    @Test("Every witness unlocked: unlocked")
    func allUnlocked() {
        let w = LockWitnesses(sessionOnConsole: true, sessionScreenLocked: false, notifyScreenLocked: false, consoleUserIsThisUser: true)
        #expect(LockPolicy.reading(w) == .unlocked)
    }

    @Test("Any witness saying locked wins")
    func anyLockedWins() {
        let base = LockWitnesses(sessionOnConsole: true, sessionScreenLocked: false, notifyScreenLocked: false, consoleUserIsThisUser: true)
        var a = base; a.sessionScreenLocked = true
        var b = base; b.notifyScreenLocked = true
        var c = base; c.notificationHold = .screenLocked
        for w in [a, b, c] { #expect(LockPolicy.reading(w) == .screenLocked) }
    }

    @Test("Off console beats locked")
    func offConsoleBeatsLocked() {
        var w = LockWitnesses(sessionOnConsole: false, sessionScreenLocked: true)
        #expect(LockPolicy.reading(w) == .offConsole)
        w = LockWitnesses(sessionOnConsole: true, notifyScreenLocked: true, consoleUserIsThisUser: false)
        #expect(LockPolicy.reading(w) == .offConsole)
        w = LockWitnesses(sessionOnConsole: true, notificationHold: .offConsole)
        #expect(LockPolicy.reading(w) == .offConsole)
    }

    @Test("The public session dictionary alone is enough (undocumented key missing)")
    func publicFallbackAlone() {
        #expect(LockPolicy.reading(LockWitnesses(sessionOnConsole: true)) == .unlocked)
        #expect(LockPolicy.reading(LockWitnesses(sessionOnConsole: false)) == .offConsole)
    }

    // MARK: Reader: lock at once, unlock after settling

    @Test("The first reading is taken as it is")
    func firstReadingIsTaken() {
        var reader = LockReader()
        #expect(reader.effective == .offConsole, "most restrictive before anything is read")
        let s1 = reader.update(nil, at: Date(timeIntervalSince1970: 0))
        #expect(s1 == .offConsole)
        let s2 = reader.update(.unlocked, at: Date(timeIntervalSince1970: 1))
        #expect(s2 == .unlocked)
    }

    @Test("A lock acts at once; an unlock only after the settle time")
    func unlockSettles() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var reader = LockReader()
        reader.update(.unlocked, at: t0)
        let s3 = reader.update(.screenLocked, at: t0.addingTimeInterval(1))
        #expect(s3 == .screenLocked)
        let s4 = reader.update(.unlocked, at: t0.addingTimeInterval(2))
        #expect(s4 == .screenLocked)
        #expect(reader.settleDeadline == t0.addingTimeInterval(2 + LockPolicy.settle))
        let s5 = reader.update(.unlocked, at: t0.addingTimeInterval(3))
        #expect(s5 == .screenLocked)
        let s6 = reader.update(.unlocked, at: t0.addingTimeInterval(2 + LockPolicy.settle))
        #expect(s6 == .unlocked)
        #expect(reader.settleDeadline == nil)
    }

    @Test("The flap of a return to the console never opens the gate")
    func flapNeverUnlocks() {
        let t0 = Date(timeIntervalSince1970: 0)
        var reader = LockReader()
        reader.update(.offConsole, at: t0)
        // Back on the console and unlocked for 1.2 s, then macOS's own lock.
        reader.update(.unlocked, at: t0.addingTimeInterval(10))
        let s7 = reader.update(.unlocked, at: t0.addingTimeInterval(11.2))
        #expect(s7 == .offConsole)
        let s8 = reader.update(.screenLocked, at: t0.addingTimeInterval(11.3))
        #expect(s8 == .screenLocked)
        let s9 = reader.update(.unlocked, at: t0.addingTimeInterval(12))
        #expect(s9 == .screenLocked)
    }

    @Test("A change between the two locked readings acts at once")
    func lockedToOffConsole() {
        var reader = LockReader()
        reader.update(.screenLocked, at: Date(timeIntervalSince1970: 0))
        let s10 = reader.update(.offConsole, at: Date(timeIntervalSince1970: 0.1))
        #expect(s10 == .offConsole)
    }

    // MARK: Decisions

    static let input: [ControlMessage] = [
        .input(.mouseDelta(dx: 1, dy: 1)),
        .input(.mouseClick(button: .left)),
        .input(.keyboardShortcut(keys: ["return"])),
    ]

    @Test("Unlocked: everything goes")
    func unlockedAllowsEverything() {
        for sample in ProtocolContractTests.samples {
            #expect(LockPolicy.decide(sample.message, state: .unlocked) == .allow, "\(sample.name)")
        }
    }

    @Test("Liveness and approval keep working whatever the state")
    func sessionAndPairingAlwaysPass() {
        for state in MacLockState.allCases {
            #expect(LockPolicy.decide(.session(.ping(seq: 1)), state: state) == .allow)
            #expect(LockPolicy.decide(.pairing(.requestAuthorizationStatus), state: state) == .allow)
            #expect(LockPolicy.decide(.mirror(.stop), state: state) == .allow)
        }
    }

    @Test("Screen locked: the password can be typed and clicked, nothing else runs")
    func screenLockedAllowsInputOnly() {
        for message in Self.input {
            #expect(LockPolicy.decide(message, state: .screenLocked) == .allow)
        }
        #expect(LockPolicy.decide(.system(.run(action: .locateCursor)), state: .screenLocked) == .allow)
        let refused: [ControlMessage] = [
            .system(.run(action: .missionControl)),
            .system(.run(action: .showDesktop)),
            .system(.switchSpace(direction: .next, displayID: nil)),
            .apps(.launchApp(bundleID: "com.apple.Terminal")),
            .apps(.appShortcut(bundleID: "com.apple.Safari", keys: ["cmd", "t"])),
            .apps(.triggerContextAction(id: "x")),
            .deck(.requestAppMenuShortcuts(bundleID: "com.apple.Safari")),
        ]
        for message in refused {
            #expect(LockPolicy.decide(message, state: .screenLocked) == .refuse(reply: .none), "\(message)")
        }
        #expect(LockPolicy.decide(.apps(.requestAppList), state: .screenLocked) == .refuse(reply: .appListAfterUnlock))
    }

    @Test("Off console: nothing the remote sends reaches this session")
    func offConsoleRefusesInput() {
        for message in Self.input {
            #expect(LockPolicy.decide(message, state: .offConsole) == .refuse(reply: .none))
        }
        #expect(LockPolicy.decide(.system(.run(action: .locateCursor)), state: .offConsole) == .refuse(reply: .none))
        #expect(LockPolicy.decide(.mirror(.start(fps: 20, maxWidth: 640, displayID: nil, codec: .jpeg)), state: .offConsole) == .refuse(reply: .none))
    }

    @Test("Mirror: the lock screen may be shown, another session's desktop may not")
    func mirrorRules() {
        let start = ControlMessage.mirror(.start(fps: 20, maxWidth: 640, displayID: nil, codec: .jpeg))
        #expect(LockPolicy.decide(start, state: .screenLocked) == .allow)
        #expect(LockPolicy.decide(start, state: .offConsole) == .refuse(reply: .none))
        let move = ControlMessage.mirror(.moveCursor(displayID: 1))
        #expect(LockPolicy.decide(move, state: .screenLocked) == .allow)
        #expect(LockPolicy.decide(move, state: .offConsole) == .refuse(reply: .none))
        let stats = ControlMessage.diagnostics(.mirrorClientStats(stats: MirrorClientStats(receivedFPS: 20, displayedFPS: 20, droppedFrames: 0, decodeMilliseconds: 4, kilobitsPerSecond: 1_000)))
        #expect(LockPolicy.decide(stats, state: .screenLocked) == .allow)
        #expect(LockPolicy.decide(stats, state: .offConsole) == .allow)
    }

    @Test("Capture: the display may be shot at the lock screen, windows never")
    func captureRules() {
        let full = ControlMessage.capture(.requestScreenshot(requestID: "r1", mode: .fullScreen, quality: .standard))
        let window = ControlMessage.capture(.requestScreenshot(requestID: "r2", mode: .window(windowID: 7), quality: .standard))
        let list = ControlMessage.capture(.requestWindowList(requestID: "w1"))
        #expect(LockPolicy.decide(full, state: .screenLocked) == .allow)
        #expect(LockPolicy.decide(full, state: .offConsole) == .refuse(reply: .screenshotError(requestID: "r1")))
        #expect(LockPolicy.decide(window, state: .screenLocked) == .refuse(reply: .screenshotError(requestID: "r2")))
        #expect(LockPolicy.decide(list, state: .screenLocked) == .refuse(reply: .emptyWindowList(requestID: "w1")))
    }

    @Test("A tracked run is judged as its action and refused with a receipt")
    func runsAreJudgedAsTheirAction() {
        let typing = ControlMessage.deck(.run(requestID: "a", action: .shortcut(keys: ["return"])))
        let launch = ControlMessage.deck(.run(requestID: "b", action: .launchApp(bundleID: "com.apple.Terminal")))
        #expect(LockPolicy.decide(typing, state: .screenLocked) == .allow)
        #expect(LockPolicy.decide(launch, state: .screenLocked) == .refuse(reply: .receipt(requestID: "b")))
        #expect(LockPolicy.decide(typing, state: .offConsole) == .refuse(reply: .receipt(requestID: "a")))
    }

    @Test("Context is withheld while locked")
    func contextIsWithheld() {
        #expect(!LockPolicy.withholdsContext(.unlocked))
        #expect(LockPolicy.withholdsContext(.screenLocked))
        #expect(LockPolicy.withholdsContext(.offConsole))
    }

    @Test("Banner copy names the Mac and says what to do")
    func bannerCopy() {
        #expect(MacLockState.unlocked.bannerText(macName: "Studio") == nil)
        #expect(MacLockState.screenLocked.bannerText(macName: "Studio")?.contains("Studio is locked") == true)
        #expect(MacLockState.offConsole.bannerText(macName: "Studio")?.contains("Another user") == true)
    }
}

@Suite struct DisplayWakePolicyTests {
    @Test("Only what a person did counts")
    func personActions() {
        #expect(DisplayWakePolicy.isPersonAction(.input(.mouseDelta(dx: 1, dy: 0))))
        #expect(DisplayWakePolicy.isPersonAction(.system(.run(action: .missionControl))))
        #expect(DisplayWakePolicy.isPersonAction(.apps(.launchApp(bundleID: "x"))))
        #expect(DisplayWakePolicy.isPersonAction(.deck(.run(requestID: "r", action: .shortcut(keys: ["a"])))))
        #expect(DisplayWakePolicy.isPersonAction(.capture(.requestScreenshot(requestID: "r", mode: .fullScreen, quality: .standard))))
        #expect(!DisplayWakePolicy.isPersonAction(.session(.ping(seq: 1))))
        #expect(!DisplayWakePolicy.isPersonAction(.apps(.requestAppList)))
        #expect(!DisplayWakePolicy.isPersonAction(.mirror(.start(fps: 20, maxWidth: 640, displayID: nil, codec: .jpeg))))
        #expect(!DisplayWakePolicy.isPersonAction(.pairing(.requestAuthorizationStatus)))
    }

    @Test("Person actions declare at most once every five seconds; connections always")
    func throttle() {
        let t0 = Date(timeIntervalSince1970: 100)
        var throttle = DisplayWakeThrottle()
        let r1 = throttle.shouldDeclare(.personAction, lock: .unlocked, at: t0)
        #expect(r1)
        let r2 = throttle.shouldDeclare(.personAction, lock: .unlocked, at: t0.addingTimeInterval(1))
        #expect(!r2)
        let r3 = throttle.shouldDeclare(.connected, lock: .unlocked, at: t0.addingTimeInterval(2))
        #expect(r3)
        let r4 = throttle.shouldDeclare(.personAction, lock: .unlocked, at: t0.addingTimeInterval(6))
        #expect(!r4)
        let r5 = throttle.shouldDeclare(.personAction, lock: .unlocked, at: t0.addingTimeInterval(7))
        #expect(r5)
    }

    @Test("Locked: typing wakes the lock screen, a connection doesn't; off console never")
    func lockRules() {
        let t0 = Date(timeIntervalSince1970: 0)
        var throttle = DisplayWakeThrottle()
        let r6 = throttle.shouldDeclare(.connected, lock: .screenLocked, at: t0)
        #expect(!r6)
        let r7 = throttle.shouldDeclare(.personAction, lock: .screenLocked, at: t0)
        #expect(r7)
        var other = DisplayWakeThrottle()
        let r8 = other.shouldDeclare(.connected, lock: .offConsole, at: t0)
        #expect(!r8)
        let r9 = other.shouldDeclare(.personAction, lock: .offConsole, at: t0)
        #expect(!r9)
    }

    @Test("A clock that went backwards doesn't block declarations")
    func clockJump() {
        var throttle = DisplayWakeThrottle()
        let r10 = throttle.shouldDeclare(.personAction, lock: .unlocked, at: Date(timeIntervalSince1970: 100))
        #expect(r10)
        let r11 = throttle.shouldDeclare(.personAction, lock: .unlocked, at: Date(timeIntervalSince1970: 50))
        #expect(r11)
    }
}
