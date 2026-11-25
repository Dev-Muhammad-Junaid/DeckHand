//
//  MacPanelDesignTests.swift
//  PixelHandCoreTests
//
//  The Mac's menu-bar hand states and the "Pair a device" window's code,
//  countdown and QR plan (`06-Pixel-Identity.md` §4 and §8).
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("Menu-bar hand")
struct MenuBarHandTests {
    @Test("The hand rows match the canvas: 17 wide, 18 tall, two rows of headroom")
    func canvas() {
        #expect(MenuBarHand.handRows.count == 18)
        #expect(MenuBarHand.handRows.allSatisfy { $0.count == MenuBarHand.width })
        #expect(MenuBarHand.height == 20)
    }

    @Test("States resolve most urgent first")
    func resolution() {
        typealias S = MenuBarHandState
        #expect(S.resolve(.init(isRunning: false)) == .notReady)
        #expect(S.resolve(.init(isRunning: true, failedToStart: true, pendingRequests: 1)) == .notReady)
        #expect(S.resolve(.init(isRunning: true)) == .ready)
        #expect(S.resolve(.init(isRunning: true, pendingRequests: 1, liveConnections: 1, isLocked: true)) == .asking)
        #expect(S.resolve(.init(isRunning: true, liveConnections: 1)) == .connected)
        #expect(S.resolve(.init(isRunning: true, liveConnections: 1, isLocked: true, secondsSinceInput: 0)) == .locked)
        #expect(S.resolve(.init(isRunning: true, liveConnections: 1, secondsSinceInput: 0.5, secondsSinceReceive: 0.2)) == .receiving)
        #expect(S.resolve(.init(isRunning: true, liveConnections: 1, secondsSinceInput: 0.5)) == .active)
        #expect(S.resolve(.init(isRunning: true, liveConnections: 1, secondsSinceInput: 5)) == .connected)
        // Locked with nobody connected says nothing: the hand is just ready.
        #expect(S.resolve(.init(isRunning: true, isLocked: true)) == .ready)
    }

    @Test("Every state lights dots inside the canvas, each once")
    func dotsInCanvas() {
        for state in MenuBarHandState.allCases {
            for frame in 0..<12 {
                let dots = MenuBarHand.dots(for: state, frame: frame)
                #expect(!dots.isEmpty)
                #expect(dots.allSatisfy { (0..<MenuBarHand.width).contains($0.x) && (0..<MenuBarHand.height).contains($0.y) })
                #expect(dots.allSatisfy { $0.alpha > 0 && $0.alpha <= 1 })
                #expect(Set(dots.map { GlyphPoint(x: $0.x, y: $0.y) }).count == dots.count)
            }
        }
    }

    @Test("Each state looks different from the others")
    func statesDistinct() {
        let looks = MenuBarHandState.allCases.map { MenuBarHand.dots(for: $0, frame: 0) }
        #expect(Set(looks).count == MenuBarHandState.allCases.count)
    }

    @Test("Not ready is the ready outline at half strength")
    func notReadyDims() {
        let ready = MenuBarHand.dots(for: .ready)
        let dim = MenuBarHand.dots(for: .notReady)
        #expect(ready.map { [$0.x, $0.y] } == dim.map { [$0.x, $0.y] })
        #expect(dim.allSatisfy { $0.alpha == MenuBarHand.dimAlpha })
    }

    @Test("The fingertip blinks at 1 Hz (two frames a second) and holds on frame 0")
    func fingertipBlinks() {
        let on = Set(MenuBarHand.dots(for: .asking, frame: 0).map { GlyphPoint(x: $0.x, y: $0.y) })
        let off = Set(MenuBarHand.dots(for: .asking, frame: 1).map { GlyphPoint(x: $0.x, y: $0.y) })
        #expect(on.isSuperset(of: MenuBarHand.fingertip))
        #expect(off.isDisjoint(with: MenuBarHand.fingertip))
    }

    @Test("Rays only while being controlled")
    func rays() {
        for state in MenuBarHandState.allCases {
            let lit = Set(MenuBarHand.dots(for: state).map { GlyphPoint(x: $0.x, y: $0.y) })
            #expect(lit.isSuperset(of: MenuBarHand.rays) == (state == .active))
        }
    }

    @Test("The padlock sits on palm fill, clear of the outline")
    func padlockInPalm() {
        for point in MenuBarHand.padlock {
            #expect(MenuBarHand.cell(point.x, point.y) == .fill)
        }
    }

    @Test("The receive beam moves along the cuff with three bright dots")
    func beam() {
        for frame in 0..<MenuBarHand.beamFrames {
            let bright = MenuBarHand.dots(for: .receiving, frame: frame)
                .filter { $0.y == MenuBarHand.cuffRow && $0.alpha == 1 }
            #expect(bright.count == MenuBarHand.beamLength)
        }
        #expect(MenuBarHand.dots(for: .receiving, frame: 0) != MenuBarHand.dots(for: .receiving, frame: 1))
    }
}

@Suite("Pair a device window")
struct PairingCodeDisplayTests {
    @Test("Two groups of four; the check digit ends the last group")
    func groups() throws {
        let code = try #require(PairingCode(Self.validCode()))
        let groups = PairingCodeDisplay.groups(code)
        #expect(groups.map(\.text).joined() == code.digits)
        #expect(groups.count == 2)
        #expect(groups.last?.isCheck == true)
        #expect(groups.allSatisfy { $0.text.count == 4 })
        #expect(PairingCodeDisplay.spoken(code).hasSuffix(code.digits.map(String.init).joined(separator: " ")))
    }

    @Test("The beam counts down the 5-minute window and empties only at expiry")
    func beam() {
        let life = PairingCodeWindow.lifetime
        #expect(PairingCodeDisplay.beamLitCells(remaining: life) == PairingCodeDisplay.beamCells)
        #expect(PairingCodeDisplay.beamLitCells(remaining: life / 2) == 5)
        #expect(PairingCodeDisplay.beamLitCells(remaining: 1) == 1)
        #expect(PairingCodeDisplay.beamLitCells(remaining: 0) == 0)
        #expect(PairingCodeDisplay.beamLitCells(remaining: life * 2) == PairingCodeDisplay.beamCells)
    }

    @Test("Countdown text rounds up and pads seconds")
    func countdown() {
        #expect(PairingCodeDisplay.countdown(remaining: 300) == "5:00")
        #expect(PairingCodeDisplay.countdown(remaining: 220.2) == "3:41")
        #expect(PairingCodeDisplay.countdown(remaining: 0.1) == "0:01")
        #expect(PairingCodeDisplay.countdown(remaining: -3) == "0:00")
        #expect(PairingCodeDisplay.spokenCountdown(remaining: 221) == "3 minutes 41 seconds left")
        #expect(PairingCodeDisplay.spokenCountdown(remaining: 60) == "1 minute left")
        #expect(PairingCodeDisplay.spokenCountdown(remaining: 9) == "9 seconds left")
    }

    @Test("QR plan keeps finders square and clears a small odd centre")
    func qrPlan() {
        for n in stride(from: 21, through: 57, by: 4) {
            let side = QRDotPlan.clearedSide(modules: n)
            #expect(side % 2 == 1)
            #expect(Double(side * side) / Double(n * n) <= 0.07)
            // The centre never touches a finder.
            for y in 0..<n {
                for x in 0..<n where QRDotPlan.isCleared(x: x, y: y, modules: n) {
                    #expect(!QRDotPlan.isFinder(x: x, y: y, modules: n))
                }
            }
            #expect(QRDotPlan.module(x: 0, y: 0, modules: n, dark: true) == .finder)
            #expect(QRDotPlan.module(x: n - 1, y: 0, modules: n, dark: true) == .finder)
            #expect(QRDotPlan.module(x: 0, y: n - 1, modules: n, dark: true) == .finder)
            #expect(QRDotPlan.module(x: n - 1, y: n - 1, modules: n, dark: true) == .dot)
            #expect(QRDotPlan.module(x: n / 2, y: n / 2, modules: n, dark: true) == .cleared)
        }
    }

    /// Seven digits plus a valid Damm check digit.
    static func validCode() -> String {
        for check in 0...9 {
            let candidate = "4821093\(check)"
            if PairingCode(candidate) != nil { return candidate }
        }
        return ""
    }
}

@Suite("Mac panel copy")
struct MacPanelCopyTests {
    @Test("The header line says what the Mac is doing, plainly")
    func header() {
        func line(running: Bool = true, failed: Bool = false, connected: Int = 0, pending: Int = 0, locked: Bool = false) -> String {
            MacPanelCopy.headerStatus(isRunning: running, failedToStart: failed, connected: connected, pending: pending, isLocked: locked)
        }
        #expect(line(running: false) == "Starting…")
        #expect(line(running: false, failed: true) == "Failed to start")
        #expect(line() == "Ready for a device")
        #expect(line(connected: 1) == "1 device connected · ready")
        #expect(line(connected: 2) == "2 devices connected · ready")
        #expect(line(connected: 1, pending: 1) == "1 device asking · 1 device connected")
        #expect(line(pending: 2) == "2 devices asking")
        #expect(line(connected: 1, locked: true) == "1 device connected · locked")
        #expect(line(locked: true) == "Locked")
    }
}

@Suite("Mac panel: who is asking, who was turned away (VQ-023, VQ-043)")
struct MacPanelRequestCopyTests {
    @Test("One request names the device")
    func namesTheAskingDevice() {
        #expect(MacPanelCopy.headerStatus(isRunning: true, failedToStart: false, connected: 0, pending: 1, isLocked: false, pendingName: "iPad Pro") == "iPad Pro is asking to connect")
        // With others connected the count reads better.
        #expect(MacPanelCopy.headerStatus(isRunning: true, failedToStart: false, connected: 1, pending: 1, isLocked: false, pendingName: "iPad Pro") == "1 device asking · 1 device connected")
    }

    @Test("Right after a refusal the header doesn't say Ready")
    func turnedAwayHeader() {
        #expect(MacPanelCopy.headerStatus(isRunning: true, failedToStart: false, connected: 0, pending: 0, isLocked: false, turnedAwayName: "iPhone 17 Pro") == "iPhone 17 Pro couldn’t connect")
    }

    @Test("Rules and timeouts get a line and a button; a person's Deny doesn't")
    func turnedAwayLines() {
        let remote = MacPanelCopy.turnedAway(name: "iPhone 17 Pro", reason: .notPairedRemote)
        #expect(remote?.line.contains("another network") == true)
        #expect(remote?.action == "Pair a device")
        #expect(MacPanelCopy.turnedAway(name: "iPad", reason: .timedOut)?.action == "Pair a device")
        #expect(MacPanelCopy.turnedAway(name: "iPad", reason: .declined) == nil)
        #expect(MacPanelCopy.turnedAway(name: "iPad", reason: .replaced) == nil)
        for reason in AuthRefusal.allCases {
            #expect(MacPanelCopy.turnedAway(name: "iPad", reason: reason)?.action.hasSuffix("…") != true)
        }
    }

    @Test("Device class from a name")
    func deviceClass() {
        #expect(MacPanelCopy.deviceClass(fromName: "iPad Pro 11-inch (M5)") == .iPad)
        #expect(MacPanelCopy.deviceClass(fromName: "Muhammad’s iPhone") == .iPhone)
        #expect(MacPanelCopy.deviceClass(fromName: "Studio") == nil)
        #expect(MacPanelCopy.deviceClass(fromName: "MacBook Air") == .mac)
    }
}
