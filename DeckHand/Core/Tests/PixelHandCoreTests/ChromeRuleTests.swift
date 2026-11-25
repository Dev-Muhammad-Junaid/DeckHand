//
//  ChromeRuleTests.swift
//  PixelHandCoreTests
//
//  The owner's rule for glyphs, dots and loaders (owner review of the build
//  18 visual QA): fades not slides, the loader only for real waiting,
//  buttons without a trailing "…", selection by colour and fill. Also
//  OR-05 (the sidebar button stays put) and a lint over the iOS app's
//  sources so the dots and slides don't creep back.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct ChromeRuleTests {
    // MARK: Motion

    @Test("Panels and status rows fade in 150–200 ms, ease-out")
    func panelFade() {
        let timing = ChromeRule.panelFade(reduceMotion: false)
        #expect(timing.effect == .fade)
        #expect(timing.curve == .easeOut)
        #expect((0.15...0.2).contains(timing.duration))
    }

    @Test("Reduce Motion changes panels at once")
    func panelFadeReduceMotion() {
        let timing = ChromeRule.panelFade(reduceMotion: true)
        #expect(timing.effect == .instant)
        #expect(timing.duration == 0)
    }

    // MARK: Loader

    @Test("The dot-matrix loader is only for real waiting")
    func loaderOnlyForWaiting() {
        for occasion in [LoaderOccasion.askPlanRunning, .waitingOnMac, .slowStep, .connecting, .systemResource] {
            #expect(ChromeRule.showsLoader(for: occasion))
        }
        for occasion in [LoaderOccasion.runShortcut, .switchTab, .openApp] {
            #expect(!ChromeRule.showsLoader(for: occasion))
        }
    }

    @Test("Running a chip leaves no mark unless the Mac refused it")
    func pressFeedback() {
        #expect(ChromeRule.pressFeedback(delivered: true) == .pressAndHaptic)
        #expect(ChromeRule.pressFeedback(delivered: false) == .pressHapticAndFailureTint)
    }

    // MARK: Button titles

    @Test("Button titles lose a trailing ellipsis", arguments: [
        ("Forget…", "Forget"),
        ("Pair a device…", "Pair a device"),
        ("Revoke...", "Revoke"),
        ("Window …", "Window"),
        ("Pair", "Pair"),
        ("Share", "Share"),
    ])
    func buttonTitles(input: String, expected: String) {
        #expect(ChromeRule.buttonTitle(input) == expected)
        #expect(ChromeRule.isCleanButtonTitle(expected))
    }

    @Test("A mid-title ellipsis is left alone")
    func midEllipsis() {
        #expect(ChromeRule.buttonTitle("Wait… then go") == "Wait… then go")
        #expect(!ChromeRule.isCleanButtonTitle("Forget…"))
    }

    // MARK: OR-05

    @Test("The sidebar button sits in the same spot shown or hidden (OR-05)", arguments: [0.0, 76.0])
    func sidebarToggleStays(windowControlsInset: Double) {
        let wideMargin = LayoutMetrics(width: 1194, height: 834).margin
        let shown = SidebarTogglePlacement.leadingX(sidebarShown: true, margin: wideMargin, windowControlsInset: windowControlsInset)
        let hidden = SidebarTogglePlacement.leadingX(sidebarShown: false, margin: wideMargin, windowControlsInset: windowControlsInset)
        #expect(shown == hidden)
        #expect(SidebarTogglePlacement.buttonSide >= 44)
        #expect(SidebarTogglePlacement.centreY == SidebarTogglePlacement.rowHeight / 2)
    }

    @Test("The sidebar button's label says what it does")
    func sidebarToggleLabel() {
        #expect(SidebarTogglePlacement.label(sidebarShown: true) == "Hide the Macs sidebar")
        #expect(SidebarTogglePlacement.label(sidebarShown: false) == "Show the Macs sidebar")
    }
}

// MARK: - Lint over the iOS app

/// Reads the iOS app's Swift sources next to this package. Skipped when the
/// package is checked out alone.
private enum IOSSources {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PixelHandCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Core
        .deletingLastPathComponent() // DeckHand
        .appendingPathComponent("DeckHandiOS", isDirectory: true)

    static func files() -> [(name: String, text: String)] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var result: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            result.append((url.path.replacingOccurrences(of: root.path + "/", with: ""), text))
        }
        return result.sorted { $0.0 < $1.0 }
    }

    /// Lines that aren't comments.
    static func codeLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}

@Suite struct ChromeRuleLintTests {
    @Test("Nothing in the iOS app slides in from the bottom")
    func noBottomSlides() {
        var offenders: [String] = []
        for file in IOSSources.files() {
            for (index, line) in IOSSources.codeLines(file.text).enumerated()
            where line.contains(".move(edge: .bottom)") {
                offenders.append("\(file.name):\(index + 1)")
            }
        }
        #expect(offenders.isEmpty, "Slides from the bottom: \(offenders)")
    }

    @Test("No dot row under tabs, chips or keys (OR-01, OR-02)")
    func noSelectionDots() {
        var offenders: [String] = []
        for file in IOSSources.files() {
            let code = IOSSources.codeLines(file.text).joined(separator: "\n")
            for marker in ["TabDot(", "DeliveryStrip(", ".deliveryDots(", "runningDot"] where code.contains(marker) {
                offenders.append("\(file.name): \(marker)")
            }
        }
        #expect(offenders.isEmpty, "Selection or delivery dots: \(offenders)")
    }

    @Test("Buttons and menu items have no trailing ellipsis (OR-12)")
    func noButtonEllipses() throws {
        let pattern = try NSRegularExpression(pattern: #"(Button|Label)\(\s*"([^"]*)""#)
        var offenders: [String] = []
        for file in IOSSources.files() {
            for (index, line) in IOSSources.codeLines(file.text).enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                for match in pattern.matches(in: line, range: range) {
                    guard let titleRange = Range(match.range(at: 2), in: line) else { continue }
                    let title = String(line[titleRange])
                    // A quote inside an interpolation ends the match early;
                    // such a title is cut off, not finished, so skip it.
                    let opened = title.filter { $0 == "(" }.count
                    let closed = title.filter { $0 == ")" }.count
                    guard opened == closed else { continue }
                    if !ChromeRule.isCleanButtonTitle(title) {
                        offenders.append("\(file.name):\(index + 1) \(title)")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "Button titles ending in an ellipsis: \(offenders)")
    }

    @Test("The pairing hints name the Mac's button as it reads now")
    func pairingHints() {
        let files = IOSSources.files().filter { $0.name.hasPrefix("Pairing/") }
        guard !files.isEmpty else { return }
        let text = files.map(\.text).joined(separator: "\n")
        #expect(!text.contains("Pair a Device"))
        #expect(!text.contains("Pair a device…"))
        #expect(text.contains("Pair a device"))
    }
}

// MARK: - VQ-079

@Suite struct SurfaceArrangementTests {
    @Test("Trackpad opens the Pointer arrangement from any other (VQ-079)")
    func trackpadToPointer() {
        #expect(RemoteSurface.trackpad.arrangement(from: .split) == .pointer)
        #expect(RemoteSurface.trackpad.arrangement(from: .screen) == .pointer)
        #expect(RemoteSurface.trackpad.arrangement(from: .pointer) == nil)
    }

    @Test("Screen brings the picture back only when it is a floating tile")
    func screen() {
        #expect(RemoteSurface.screen.arrangement(from: .pointer) == .split)
        #expect(RemoteSurface.screen.arrangement(from: .split) == nil)
        #expect(RemoteSurface.screen.arrangement(from: .screen) == nil)
    }

    @Test("Deck leaves the arrangement alone")
    func deck() {
        for preset in LayoutPreset.allCases {
            #expect(RemoteSurface.deck.arrangement(from: preset) == nil)
        }
    }
}
