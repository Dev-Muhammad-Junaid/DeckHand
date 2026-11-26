//
//  PixelHandUITests.swift
//  PixelHandUITests
//
//  Visual QA walk-through (build 18 onward). Each test drives one area of
//  the iOS app through its `ph.<area>.<name>` accessibility identifiers and
//  takes a screenshot at every step, so a later run can re-check the same
//  screens after a round of fixes.
//
//  These are capture tests, not assertions about layout: a missing control
//  is recorded as a screenshot named `…-missing-<id>` and the walk carries
//  on. Most screens need a live Mac (the Pixel Hand host on the same
//  network) that allows this simulator; the Mac's Allow click is outside
//  the test (the QA script clicks it, or a person does).
//
//  Run:
//    xcodebuild test -project DeckHand.xcodeproj -scheme DeckHandiOS \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
//      -only-testing:PixelHandUITests
//
//  With PH_QA_OUT set (via TEST_RUNNER_PH_QA_OUT), each screenshot is
//  also written there as `<device>[-tag]/<test>/<NN>-<name>.png`;
//  otherwise use the attachments in the .xcresult bundle.
//
//  Optional runner environment (prefix with TEST_RUNNER_ on xcodebuild):
//    PH_QA_FREE=1      run with "Unlock Pro for testing" off (free plan).
//    PH_QA_TAG=<tag>   suffix for the output folder (e.g. "dark", "ax3").
//    PH_QA_PAIRCODE_FILE=<path>  a file the QA script fills with the Mac's
//                      pairing code (from its "Pair a device" window). An
//                      unpaired simulator pairs with it from the picker's
//                      Pair sheet, and when the approval card offers "Enter
//                      pairing code" the walk uses it there too, so later
//                      runs connect without asking.
//    PH_QA_MAC_NAME=<name>  the start of the Mac's name: the walks use only
//                      that Mac (VQ-096).
//    PH_QA_ALLOW_PROMPT=1  tap an unpaired Mac anyway and wait for someone
//                      to click Allow. Without it, and without a code file,
//                      the connect walks on an unpaired simulator are
//                      skipped (`skipped-unpaired`), and no request reaches
//                      the Mac (VQ-103).
//
//  Pass these as environment variables of xcodebuild itself, e.g.
//  `TEST_RUNNER_PH_QA_OUT=/tmp/shots xcodebuild test-without-building …`;
//  as build-setting arguments they don't reach the runner.
//

import XCTest

@MainActor
final class PixelHandUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shot = 0

    override func setUp() async throws {
        continueAfterFailure = true
        shot = 0
    }

    // MARK: - Onboarding

    func test01_Onboarding() {
        launch(onboarded: false)
        snap("welcome")
        for _ in 0..<8 {
            let next = element("ph.onboarding.continue")
            guard next.waitForExistence(timeout: 4) else { snap("missing-continue"); break }
            let label = next.label
            next.tap()
            sleep(1)
            snap("after-\(slug(label))")
            if label == "Find my Mac" { break }
        }
        sleep(3)
        snap("picker-after-onboarding")
    }

    func test02_OnboardingLandscape() {
        useFullScreenAppsIfAsked()
        XCUIDevice.shared.orientation = .landscapeLeft
        launch(onboarded: false)
        sleep(1)
        snap("welcome-landscape")
        for _ in 0..<5 {
            let next = element("ph.onboarding.continue")
            guard next.waitForExistence(timeout: 4) else { break }
            if next.label == "Find my Mac" { break }
            next.tap()
            sleep(1)
            snap("page-landscape")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Connect

    func test03_Picker() {
        launch()
        sleep(1)
        snap("picker-early")
        sleep(4)
        snap("picker-settled")
        if tapIfExists("ph.connect.pair") {
            sleep(2)
            snap("pairing-sheet")
            dismissSheet()
        }
        if tapIfExists("ph.connect.settings") {
            sleep(1)
            snap("settings-from-picker")
            dismissSheet()
        }
    }

    // MARK: - Shell and surfaces

    func test04_ConnectAndPointer() {
        launch()
        guard connect() else { return }
        snap("pointer")
        checkBannerBelowHeader()
        tapIfExists("ph.trackpad.click")
        snap("after-click-strip")
        if tapIfExists("ph.dock.keyboard") || tapIfExists("ph.trackpad.keyboard") {
            sleep(1)
            snap("keyboard")
            if app.keyboards.count > 0 {
                app.typeText("hello")
                sleep(1)
                snap("keyboard-typed")
            }
        }
        if tapIfExists("ph.header.more") {
            sleep(1)
            snap("more-menu")
            dismissMenu()
        }
        if tapIfExists("ph.header.layout") {
            sleep(1)
            snap("layout-presets")
            dismissMenu()
        }
        if tapIfExists("ph.strip.actions") {
            sleep(1)
            snap("strip-actions")
            dismissSheet()
        }
    }

    func test05_Deck() {
        launch()
        guard connect() else { return }
        guard tapIfExists("ph.tab.deck") else { return }
        sleep(1)
        snap("deck")
        if tapIfExists("ph.deck.pageMenu") {
            sleep(1)
            snap("page-menu")
            dismissMenu()
        }
        if tapIfExists("ph.deck.suggestions") {
            sleep(3)
            snap("suggestions")
            dismissSheet()
        }
        if tapIfExists("ph.deck.edit") {
            sleep(1)
            snap("edit-mode")
            let add = app.buttons["Add key"].firstMatch
            if add.waitForExistence(timeout: 2), add.isHittable {
                add.tap()
                sleep(1)
                snap("add-key")
                dismissSheet()
            }
            let key = element("ph.deck.key")
            if key.exists, key.isHittable {
                key.tap()
                sleep(1)
                snap("key-inspector")
                dismissSheet()
            }
            // Edit mode ends with Done (its own identifier since build 18 QA).
            tapIfExists("ph.deck.done")
        }
        let key = element("ph.deck.key")
        if key.exists, key.isHittable {
            key.tap()
            sleep(1)
            snap("after-running-key")
        }
    }

    func test06_Screen() {
        launch()
        guard connect() else { return }
        guard tapIfExists("ph.tab.screen") else { return }
        // Choosing Screen starts the mirror (VQ-046); "Show screen" only
        // shows after it was stopped, or in the free plan.
        snap("screen-starting")
        let show = app.buttons["Show screen"].firstMatch
        if show.waitForExistence(timeout: 1), show.isHittable { show.tap() }
        snap("screen-0s")
        sleep(1)
        snap("screen-1s")
        sleep(3)
        snap("screen-4s")
        if tapIfExists("ph.mirror.displayPicker") {
            sleep(1)
            snap("display-picker")
            dismissSheet()
        }
        if tapIfExists("ph.mirror.sound") {
            sleep(1)
            snap("sound-toggled")
            tapIfExists("ph.mirror.sound")
        }
        // Picture in Picture: start it, go Home, come back.
        if tapIfExists("ph.mirror.pictureInPicture") {
            sleep(2)
            // iPhone simulators report no PiP: the button explains (VQ-060).
            let unavailable = app.alerts["Picture in Picture isn’t available"].firstMatch
            if unavailable.exists {
                snap("pip-unavailable")
                unavailable.buttons["OK"].tap()
                sleep(1)
            }
            snap("pip-started")
            XCUIDevice.shared.press(.home)
            sleep(3)
            snap("pip-on-home-screen")
            app.activate()
            sleep(2)
            snap("pip-returned")
        }
        tapIfExists("ph.mirror.close")
        sleep(1)
        snap("mirror-closed")
    }

    func test07_Ask() {
        launch()
        guard connect() else { return }
        guard openAsk() else { return }
        sleep(1)
        snap("ask-empty")
        let field = element("ph.ask.field")
        if field.waitForExistence(timeout: 3) {
            field.tap()
            field.typeText("Open Safari and go to apple.com")
            snap("ask-typed")
            tapIfExists("ph.ask.submit")
            snap("ask-planning")
            sleep(4)
            snap("ask-plan")
            sleep(6)
            snap("ask-plan-10s")
        } else if tapIfExists("ph.ask.example") {
            sleep(5)
            snap("ask-example-plan")
        }
        closeAsk()
    }

    func test08_Capture() {
        launch()
        guard connect() else { return }
        guard tapIfExists("ph.header.capture") else { return }
        sleep(2)
        snap("capture")
        dismissSheet()
    }

    func test09_Settings() {
        launch()
        guard openSettings() else { return }
        snap("settings-top")
        let list = app.collectionViews.firstMatch
        for i in 0..<14 {
            list.swipeUp()
            sleep(1)
            snap("settings-scroll-\(i)")
        }
        dismissSheet()
    }

    func test10_MyMacs() {
        launch()
        guard connect() else { return }
        guard tapIfExists("ph.header.macPill") else { return }
        sleep(1)
        snap("my-macs")
        dismissSheet()
    }

    func test11_Landscape() {
        useFullScreenAppsIfAsked()
        launch()
        guard connect() else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        snap("pointer-landscape")
        if tapIfExists("ph.tab.deck") { sleep(1); snap("deck-landscape") }
        if tapIfExists("ph.tab.screen") { sleep(3); snap("screen-landscape") }
        if tapIfExists("ph.tab.pointer") { sleep(1); snap("pointer-landscape-again") }
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    func test12_FreePlanAndPaywall() {
        launch(free: true)
        guard connect() else { return }
        snap("free-pointer")
        if tapIfExists("ph.tab.deck") { sleep(1); snap("free-deck") }
        if tapIfExists("ph.tab.screen") { sleep(2); snap("free-screen") }
        // OR-03: no upsell card; the field carries the small Pro lock.
        if openAsk() { sleep(1); snap("free-ask"); closeAsk() }
        if tapIfExists("ph.header.capture") { sleep(1); snap("free-capture"); dismissSheet() }
        guard openSettings() else { return }
        let subscribe = element("ph.settings.subscribe")
        let list = app.collectionViews.firstMatch
        for _ in 0..<14 where !(subscribe.exists && subscribe.isHittable) { list.swipeUp() }
        snap("subscription-section-free")
        if subscribe.exists, subscribe.isHittable {
            subscribe.tap()
            sleep(3)
            snap("paywall")
            app.swipeUp()
            sleep(1)
            snap("paywall-scrolled")
            tapIfExists("ph.paywall.close")
        }
        dismissSheet()
    }

    /// OR-06: the right column on iPad (landscape, then portrait):
    /// collapse to the edge handle, bring it back, and switch Deck | Ask.
    func test13_RightColumn() {
        launch()
        guard connect() else { return }
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            let tag = orientation == .portrait ? "portrait" : "landscape"
            guard element("ph.column.deck").waitForExistence(timeout: 3) else {
                snap("\(tag)-no-column")
                continue
            }
            snap("\(tag)-column-deck")
            if tapIfExists("ph.column.ask") { sleep(1); snap("\(tag)-column-ask") }
            if tapIfExists("ph.column.collapse") { sleep(1); snap("\(tag)-column-collapsed") }
            if tapIfExists("ph.column.expand") { sleep(1); snap("\(tag)-column-expanded") }
            tapIfExists("ph.column.deck")
        }
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    // MARK: - Build 19 fixes

    /// Bug 2 (build 19): on iPhone the floating screen tile covered the
    /// deck header, and `ph.deck.edit` wasn't hittable. Starts the mirror
    /// from the Screen tab, goes to Deck, and records whether the header's
    /// pin and Edit can be tapped (`not-hittable-…` screenshots if not).
    func test14_DeckWithMirror() {
        launch()
        guard connect() else { return }
        guard tapIfExists("ph.tab.screen") else { return }
        let show = app.buttons["Show screen"].firstMatch
        if show.waitForExistence(timeout: 1), show.isHittable { show.tap() }
        sleep(3)
        snap("mirror-running")
        guard tapIfExists("ph.tab.deck") else { return }
        sleep(2)
        snap("deck-with-tile")
        for id in ["ph.deck.pin", "ph.deck.edit"] {
            let el = element(id)
            if el.waitForExistence(timeout: 2), !el.isHittable { snap("not-hittable-\(id)") }
        }
        if tapIfExists("ph.deck.edit") {
            sleep(1)
            snap("deck-edit-with-tile")
            tapIfExists("ph.deck.done")
        }
    }

    /// VQ-001 (build 19): an unpaired simulator pairs by code instead of
    /// being refused as "remote path (loopback)". Needs PH_QA_PAIRCODE_FILE
    /// and a simulator the Mac doesn't know (Forget it in the Mac panel, or
    /// erase the simulator). Records `refused` if the Mac still refuses.
    func test15_PairUnpairedSimulatorByCode() {
        guard pairingCode() != nil else {
            snap("skipped-no-PH_QA_PAIRCODE_FILE")
            return
        }
        launch()
        let refused = element("ph.authorization.dismiss")
        if connect() {
            snap("paired-and-connected")
        } else if refused.exists {
            snap("refused")
        }
    }

    /// OR-16: pointer control on the picture. The screen-only arrangement
    /// (iPad: the "Screen focus" preset; iPhone: the Screen tab in
    /// landscape, where the pad doesn't fit), toggle on, drive a little,
    /// pinch, toggle off. Captures both states.
    func test16_PicturePointer() {
        launch()
        guard connect() else { return }
        let screenFocus = app.buttons["Screen focus"].firstMatch
        let usesPreset = screenFocus.waitForExistence(timeout: 3) && screenFocus.isHittable
        if usesPreset {
            screenFocus.tap()
        } else {
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(2)
            guard tapIfExists("ph.tab.screen") else {
                XCUIDevice.shared.orientation = .portrait
                return
            }
        }
        sleep(4)
        snap("screen-only")
        revealMirrorToolbar()
        if tapIfExists("ph.mirror.pointerControl") {
            sleep(1)
            snap("pointer-control-on")
            // VQ-093: the picture's input layer carries this ID while
            // pointer control is on (`MirrorPicturePointerLayer`).
            let surface = element("ph.mirror.pointerSurface")
            if surface.waitForExistence(timeout: 2) {
                // A finger anywhere moves the pointer relative to where it is.
                surface.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
                    .press(forDuration: 0.05, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45)))
                sleep(1)
                snap("pointer-control-moved")
                // Pinch still zooms the picture.
                surface.pinch(withScale: 2, velocity: 1)
                sleep(1)
                snap("pointer-control-zoomed")
            } else {
                snap("missing-ph.mirror.pointerSurface")
            }
            revealMirrorToolbar()
            if tapIfExists("ph.mirror.pointerControl") {
                sleep(1)
                snap("pointer-control-off")
            }
        }
        // Leave the arrangement as the other walks expect it.
        if usesPreset {
            let split = app.buttons["Split: screen over trackpad"].firstMatch
            if split.exists, split.isHittable { split.tap() }
        } else {
            XCUIDevice.shared.orientation = .portrait
        }
        sleep(1)
    }

    /// Build 22 (P2): Try again while the first start is still pending
    /// (no iCloud account: the account check takes about 45 s) must not
    /// break discovery. Taps Try again on the "Can’t find your Mac?" card,
    /// twice, then expects the Mac in the list. Records `stuck-searching`
    /// if it never shows. Best on a fresh simulator with no iCloud account.
    func test17_TryAgainDuringSlowStart() {
        launch()
        let pill = element("ph.header.macPill")
        if pill.waitForExistence(timeout: 6) {
            // Reconnected to a paired Mac by itself: the picker never showed.
            snap("skipped-already-connected")
            return
        }
        acceptSystemAlerts(timeout: 1)
        let checks = element("ph.connect.checks")
        let row = element("ph.connect.macRow")
        if checks.waitForExistence(timeout: 20) {
            snap("checks")
            tapIfExists("ph.connect.tryAgain")
            sleep(1)
            snap("after-try-again")
            // A second Try again, if the card came back, joins the same start.
            if checks.waitForExistence(timeout: 15) { tapIfExists("ph.connect.tryAgain") }
        }
        if row.waitForExistence(timeout: 75) {
            snap("mac-listed")
        } else {
            snap(element("ph.connect.retry").exists ? "start-failed" : "stuck-searching")
        }
    }

    // MARK: - Owner testing, build 24

    /// OT-2 (P1): in iPad landscape the dock's keyboard button opened the
    /// keyboard, the shell switched arrangement, the field was rebuilt and
    /// the keyboard dropped, round and round. Opens the Type panel in
    /// landscape and asserts that it, and the field's keyboard focus, stay
    /// put for 5 s and the arrangement doesn't change (the dock stays
    /// where it was). On a simulator with "Connect Hardware Keyboard" on,
    /// no on-screen keyboard shows; the field's focus is checked instead.
    func test18_KeyboardStaysOpenInLandscape() {
        useFullScreenAppsIfAsked()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        launch()
        guard connect() else { return }
        sleep(1)
        let dock = element("ph.dock")
        let dockFrame = dock.exists ? dock.frame : .zero
        guard tapIfExists("ph.dock.keyboard") || tapIfExists("ph.trackpad.keyboard") else { return }
        let panel = element("ph.type.panel")
        XCTAssertTrue(panel.waitForExistence(timeout: 3), "The Type panel didn't open")
        sleep(1)
        snap("type-panel-open")
        let field = element("ph.type.field")
        let hadKeyboard = app.keyboards.count > 0
        for tick in 0..<10 {
            usleep(500_000)
            XCTAssertTrue(panel.exists, "The Type panel closed by itself after \(Double(tick + 1) * 0.5) s")
            if hadKeyboard {
                XCTAssertTrue(app.keyboards.count > 0, "The keyboard dropped after \(Double(tick + 1) * 0.5) s")
            } else {
                XCTAssertTrue(hasKeyboardFocus(field), "The field lost focus after \(Double(tick + 1) * 0.5) s")
            }
            if dock.exists, dockFrame != .zero {
                XCTAssertEqual(dock.frame, dockFrame, "The shell moved under the keyboard (arrangement changed)")
            }
        }
        snap("type-panel-after-5s")
        if field.exists {
            field.typeText("hello")
            snap("type-panel-typed")
        }
        // Compose, Numpad, and back.
        if tapIfExists("ph.type.mode.compose") {
            sleep(1)
            snap("type-compose")
            if field.exists { field.typeText("draft") }
            snap("type-compose-draft")
        }
        if tapIfExists("ph.type.tab.numpad") {
            sleep(1)
            snap("type-numpad")
            tapIfExists("ph.type.tab.keys")
        }
        tapIfExists("ph.type.mode.live")
        // Rotating while open keeps the panel.
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(panel.exists, "The Type panel closed on rotation")
        snap("type-panel-portrait")
        tapIfExists("ph.type.close")
        sleep(1)
        XCTAssertFalse(panel.exists, "The close button didn't close the panel")
    }

    /// OT-5 (P1): after one run Ask was left on a Name field with no way
    /// back. Walks ask → run → New request → Save as key → Cancel → ask
    /// again, asserting each step offers what the flow says.
    func test19_AskAgainAfterRun() {
        launch()
        guard connect() else { return }
        guard openAsk() else { return }
        let field = element("ph.ask.field")
        guard field.waitForExistence(timeout: 3) else { snap("missing-ask-field"); return }
        field.tap()
        field.typeText("Show Mission Control")
        tapIfExists("ph.ask.submit")
        XCTAssertTrue(element("ph.ask.run").waitForExistence(timeout: 10), "No Run after planning")
        snap("ask-plan")
        tapIfExists("ph.ask.run")
        // A confirmation may ask first.
        let confirm = app.buttons["Run"].firstMatch
        if confirm.waitForExistence(timeout: 1), confirm.isHittable, !element("ph.ask.run").isHittable { confirm.tap() }
        XCTAssertTrue(element("ph.ask.newRequest").waitForExistence(timeout: 10), "No New request after the run")
        XCTAssertTrue(element("ph.ask.runAgain").exists, "No Run again after the run")
        XCTAssertTrue(element("ph.ask.saveAsKey").exists, "No Save as key after the run")
        XCTAssertTrue(element("ph.ask.result").exists, "No result line after the run")
        snap("ask-result")

        tapIfExists("ph.ask.newRequest")
        sleep(1)
        let cleared = (field.value as? String) ?? ""
        XCTAssertTrue(cleared.isEmpty || cleared == field.placeholderValue, "New request didn't clear the field")
        snap("ask-new-request")

        field.typeText("Take a screenshot")
        tapIfExists("ph.ask.submit")
        XCTAssertTrue(element("ph.ask.saveAsKey").waitForExistence(timeout: 10), "No Save as key on the plan")
        tapIfExists("ph.ask.saveAsKey")
        XCTAssertTrue(element("ph.ask.name").waitForExistence(timeout: 3), "Save as key didn't ask for a name")
        XCTAssertTrue(element("ph.ask.cancel").exists, "Save as key has no Cancel")
        snap("ask-naming")
        tapIfExists("ph.ask.cancel")
        sleep(1)
        XCTAssertFalse(element("ph.ask.name").exists, "Cancel left the name field")
        XCTAssertTrue(element("ph.ask.run").exists, "Cancel didn't return to the plan")
        snap("ask-after-cancel")

        field.tap()
        field.typeText(" now")
        tapIfExists("ph.ask.submit")
        XCTAssertTrue(element("ph.ask.run").waitForExistence(timeout: 10), "Asking again didn't plan")
        snap("ask-again")
        closeAsk()
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        return (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    // MARK: - Helpers

    /// Build 22 (P2): the lock banner sits under the header and never
    /// draws over the Mac pill. Records `banner-overlaps-header` if it does.
    private func checkBannerBelowHeader() {
        let banner = element("ph.status.locked")
        let pill = element("ph.header.macPill")
        guard banner.waitForExistence(timeout: 1), pill.exists else { return }
        snap("lock-banner")
        if banner.frame.minY < pill.frame.maxY - 1 {
            snap("banner-overlaps-header")
        }
    }

    /// The mirror's toolbar fades after 3 s. Off, a tap on the picture
    /// brings it back; on (OR-16), a tap where the toolbar sits does.
    private func revealMirrorToolbar() {
        let toggle = element("ph.mirror.pointerControl")
        if toggle.exists, toggle.isHittable { return }
        let pane = element("ph.mirror")
        guard pane.exists else { return }
        pane.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        sleep(1)
    }

    /// Opens Ask: the tab bar's Ask on compact windows, the Ask field or
    /// circle (`ph.ask`) on iPad, where it opens in the right column when
    /// the arrangement has one.
    @discardableResult
    private func openAsk() -> Bool {
        if element("ph.tab.ask").waitForExistence(timeout: 2) {
            return tapIfExists("ph.tab.ask")
        }
        return tapIfExists("ph.ask")
    }

    /// Closes the Ask sheet, or returns the right column to the deck.
    private func closeAsk() {
        let deckSwitch = element("ph.column.deck")
        if deckSwitch.exists, deckSwitch.isHittable {
            deckSwitch.tap()
            sleep(1)
        } else {
            dismissSheet()
        }
    }

    private func launch(onboarded: Bool = true, free: Bool? = nil) {
        app = XCUIApplication()
        let isFree = free ?? (ProcessInfo.processInfo.environment["PH_QA_FREE"] == "1")
        app.launchArguments += [
            "-settings.hasCompletedOnboarding", onboarded ? "YES" : "NO",
            "-store.developerUnlock", isFree ? "NO" : "YES",
        ]
        app.launch()
        acceptSystemAlerts()
    }

    /// Accepts system permission prompts (Local Network on first launch,
    /// Camera for the scanner, Photos). Discovery stalls until Local
    /// Network is answered, and the interruption monitor only runs when
    /// the test touches the app.
    private func acceptSystemAlerts(timeout: TimeInterval = 3) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return }
        snap("system-alert")
        for label in ["Allow", "OK", "Allow Full Access", "Allow Access to All Photos"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                sleep(1)
                return
            }
        }
    }

    private func openSettings() -> Bool {
        guard connect() else { return false }
        guard tapIfExists("ph.header.more") else { return false }
        let settings = app.buttons["Settings"].firstMatch
        guard settings.waitForExistence(timeout: 2) else {
            snap("missing-settings-item")
            return false
        }
        settings.tap()
        sleep(1)
        return true
    }

    /// Picks the Mac (`macRow()`) and waits for the shell. Returns false
    /// (with a screenshot) if no Mac shows up or it never allows us.
    ///
    /// VQ-103: a Mac this simulator isn't paired with is never tapped, so
    /// the Mac is never left showing an Allow prompt nobody answers:
    /// - with PH_QA_PAIRCODE_FILE, the walk pairs by code from the picker's
    ///   Pair sheet (the code goes out with the request, so the Mac
    ///   doesn't ask);
    /// - without it, the walk is skipped with a `skipped-unpaired` snapshot
    ///   and a "SKIPPED" activity naming the fix.
    /// PH_QA_ALLOW_PROMPT=1 keeps the old behaviour (tap and wait for a
    /// person to click Allow). Whatever happens, a request still waiting
    /// at the deadline is withdrawn.
    @discardableResult
    private func connect(timeout: TimeInterval = 90) -> Bool {
        let pill = element("ph.header.macPill")
        if pill.waitForExistence(timeout: 6) {
            // A paired Mac reconnects by itself; give it a moment.
            for _ in 0..<8 where !isConnected() { sleep(1) }
            if isConnected() { sleep(1); return true }
        }
        let row = macRow()
        acceptSystemAlerts(timeout: 1)
        guard row.waitForExistence(timeout: 45) else {
            snap("no-mac-found")
            return false
        }
        let name = rowName(row)
        let allowsPrompt = ProcessInfo.processInfo.environment["PH_QA_ALLOW_PROMPT"] == "1"
        if isPairedRow(row) || allowsPrompt {
            row.tap()
            sleep(1)
            snap("waiting-for-allow")
        } else if let code = pairingCode() {
            guard pairFromPicker(code, macName: name) else {
                withdrawRequest()
                return false
            }
        } else {
            skipConnect("This simulator isn’t paired with \(name), so the connect walks are skipped and no request was sent to the Mac. Set TEST_RUNNER_PH_QA_PAIRCODE_FILE to a file holding the Mac’s pairing code (Pair a device on the Mac) to pair it, or TEST_RUNNER_PH_QA_ALLOW_PROMPT=1 if someone will click Allow.")
            return false
        }
        let deadline = Date().addingTimeInterval(timeout)
        var triedCode = false
        while Date() < deadline {
            if isConnected() { break }
            if !triedCode, let code = pairingCode(), element("ph.authorization.enterCode").exists {
                triedCode = true
                enterPairingCode(code)
            }
            sleep(1)
        }
        guard isConnected() else {
            snap("never-allowed")
            withdrawRequest()
            return false
        }
        sleep(2)
        return true
    }

    /// Whether the picker row says this device is paired with the Mac. Rows
    /// read "<name>, my Mac, paired, nearby" to VoiceOver.
    private func isPairedRow(_ row: XCUIElement) -> Bool {
        row.label.components(separatedBy: ", ").dropFirst().contains { $0.lowercased() == "paired" }
    }

    /// The Mac's name from its picker row's label.
    private func rowName(_ row: XCUIElement) -> String {
        row.label.components(separatedBy: ", ").first ?? row.label
    }

    /// VQ-103: pairs with `macName` by code from the picker's Pair sheet,
    /// without tapping its row. Picks the Mac on the "Pair with" row when
    /// several are listed (VQ-100); a full code sends itself, the sheet
    /// closes and the app connects with the code.
    private func pairFromPicker(_ code: String, macName: String) -> Bool {
        guard tapIfExists("ph.connect.pair") else { return false }
        let field = element("ph.pairing.codeField")
        guard field.waitForExistence(timeout: 3) else {
            snap("missing-ph.pairing.codeField")
            dismissSheet()
            return false
        }
        let chooser = element("ph.pairing.macChooser")
        if chooser.exists, !chooser.label.localizedCaseInsensitiveContains(macName) {
            chooser.tap()
            let option = app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH[c] %@ AND identifier != %@", macName, "ph.connect.macRow"
            )).firstMatch
            guard option.waitForExistence(timeout: 2) else {
                snap("pair-chooser-missing-mac")
                dismissMenu()
                dismissSheet()
                return false
            }
            option.tap()
            sleep(1)
        }
        snap("pair-sheet-from-picker")
        field.tap()
        field.typeText(code)
        snap("pairing-code-typed")
        sleep(2)
        // Still open: the code didn't send itself (no Mac chosen, or a
        // typo the check digit caught).
        if field.exists {
            if !tapIfExists("ph.pairing.reconnect", timeout: 1) {
                snap("pair-sheet-stuck")
                dismissSheet()
                return false
            }
            sleep(1)
        }
        snap("pairing-sent")
        return true
    }

    /// Withdraws a request this walk left waiting, so the Mac isn't left
    /// showing an Allow prompt (VQ-103): the approval card's Disconnect, or
    /// the connecting toast's Cancel.
    private func withdrawRequest() {
        for id in ["ph.authorization.disconnect", "ph.authorization.dismiss", "ph.connect.cancel"] {
            let button = element(id)
            if button.exists, button.isHittable {
                button.tap()
                sleep(1)
                snap("request-withdrawn")
                return
            }
        }
    }

    /// Records why a walk is skipped: a snapshot, a named activity in the
    /// result bundle, and a line in the log.
    private func skipConnect(_ reason: String) {
        snap("skipped-unpaired")
        XCTContext.runActivity(named: "SKIPPED: \(reason)") { _ in }
        print("PH_QA SKIPPED \(name): \(reason)")
    }

    /// VQ-092: with the iPad simulator's windowing on, the app stays a
    /// portrait window when the device rotates, so the landscape walks
    /// captured portrait. With PH_QA_FULLSCREEN=1 (set
    /// TEST_RUNNER_PH_QA_FULLSCREEN=1) this sets Settings › Multitasking &
    /// Gestures to Full Screen Apps first. iPad only; a snapshot names
    /// any step it couldn't find, and the walk goes on either way.
    private func useFullScreenAppsIfAsked() {
        guard ProcessInfo.processInfo.environment["PH_QA_FULLSCREEN"] == "1",
              UIDevice.current.userInterfaceIdiom == .pad else { return }
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let multitasking = settings.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Multitasking")).firstMatch
        var found = multitasking.waitForExistence(timeout: 3)
        // The row can sit below the fold of the sidebar.
        for _ in 0..<4 where !found || !multitasking.isHittable {
            settings.swipeUp()
            found = multitasking.exists
        }
        guard found, multitasking.isHittable else {
            snap("fullscreen-missing-multitasking")
            settings.terminate()
            return
        }
        multitasking.tap()
        let fullScreen = settings.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Full Screen Apps")).firstMatch
        if fullScreen.waitForExistence(timeout: 3), fullScreen.isHittable {
            fullScreen.tap()
            sleep(1)
            snap("fullscreen-set")
        } else {
            snap("fullscreen-missing-option")
        }
        settings.terminate()
    }

    /// The picker's row for the Mac to test against (VQ-096): the one whose
    /// name starts with PH_QA_MAC_NAME (set TEST_RUNNER_PH_QA_MAC_NAME), so
    /// another Mac on the network isn't sent a request; the first Mac when
    /// it isn't set. Rows read "<name>, my Mac, paired, nearby" to
    /// VoiceOver, so the name leads the label.
    private func macRow() -> XCUIElement {
        let rows = app.descendants(matching: .any).matching(identifier: "ph.connect.macRow")
        guard let name = ProcessInfo.processInfo.environment["PH_QA_MAC_NAME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return rows.firstMatch }
        return rows.matching(NSPredicate(format: "label BEGINSWITH[c] %@", name)).firstMatch
    }

    /// The shell is up and no approval or refusal card covers it.
    private func isConnected() -> Bool {
        element("ph.header.macPill").exists
            && !element("ph.authorization.disconnect").exists
            && !element("ph.authorization.dismiss").exists
            && !element("ph.authorization.enterCode").exists
    }

    /// The pairing code the QA script read from the Mac's pairing window,
    /// from the file named by PH_QA_PAIRCODE_FILE (any text; the digits
    /// are used).
    private func pairingCode() -> String? {
        guard let path = ProcessInfo.processInfo.environment["PH_QA_PAIRCODE_FILE"],
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let line = text.split(separator: "\n").first { $0.contains("Pairing code") } ?? Substring(text)
        let digits = line.filter(\.isNumber)
        return digits.count >= 6 ? String(digits.prefix(8)) : nil
    }

    private func enterPairingCode(_ code: String) {
        guard tapIfExists("ph.authorization.enterCode") else { return }
        let field = element("ph.pairing.codeField")
        guard field.waitForExistence(timeout: 3) else { return }
        field.tap()
        field.typeText(code)
        snap("pairing-code-typed")
        tapIfExists("ph.pairing.pair")
        sleep(2)
        snap("after-pair")
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func tapIfExists(_ id: String, timeout: TimeInterval = 3) -> Bool {
        let el = element(id)
        guard el.waitForExistence(timeout: timeout) else {
            snap("missing-\(id)")
            return false
        }
        guard el.isHittable else {
            snap("not-hittable-\(id)")
            return false
        }
        el.tap()
        return true
    }

    private func dismissSheet() {
        for label in ["Done", "Close", "Cancel"] {
            let button = app.buttons[label].firstMatch
            if button.exists, button.isHittable {
                button.tap()
                sleep(1)
                return
            }
        }
        app.swipeDown(velocity: .fast)
        sleep(1)
    }

    private func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        sleep(1)
    }

    private func slug(_ text: String) -> String {
        String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    private func snap(_ name: String) {
        shot += 1
        let screenshot = XCUIScreen.main.screenshot()
        let fileName = String(format: "%02d-%@", shot, slug(String(name.prefix(60))))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)

        let env = ProcessInfo.processInfo.environment
        guard let root = env["PH_QA_OUT"], !root.isEmpty else { return }
        let device = slug(env["SIMULATOR_DEVICE_NAME"] ?? "device")
        let tag = env["PH_QA_TAG"].map { "-\($0)" } ?? ""
        let testName = folder(forTest: self.name)
        let dir = URL(fileURLWithPath: root)
            .appendingPathComponent("\(device)\(tag)")
            .appendingPathComponent(testName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(fileName).png"))
    }

    /// "-[PixelHandUITests test05_Deck]" → "test05_Deck".
    private func folder(forTest full: String) -> String {
        let last = full.split(separator: " ").last.map(String.init) ?? full
        return last.trimmingCharacters(in: CharacterSet(charactersIn: "[]-"))
    }
}
