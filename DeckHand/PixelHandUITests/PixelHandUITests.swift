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
        if openTypePanel(required: false) {
            sleep(1)
            snap("keyboard")
            if app.keyboards.count > 0, ensureScratchFrontmost() {
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
        guard openTypePanel() else { return }
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
        if field.exists, ensureScratchFrontmost() {
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
        // Build 25 (OT-7): the numpad is a toggle that docks beside the keys.
        if tapIfExists("ph.type.tab.numpad") {
            sleep(1)
            snap("type-numpad")
            tapIfExists("ph.type.tab.numpad")
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

        // Build 25 bug 2: focusing the field after a plan selects the old
        // request, so typing replaces it instead of joining it.
        field.tap()
        field.typeText("Show Mission Control")
        XCTAssertEqual(field.value as? String, "Show Mission Control", "The new request joined the old one")
        tapIfExists("ph.ask.submit")
        XCTAssertTrue(element("ph.ask.run").waitForExistence(timeout: 10), "Asking again didn't plan")
        snap("ask-again")
        closeAsk()
    }

    /// OT-6 and OT-7 (owner testing, build 25): the Type panel moves,
    /// snaps, resizes, folds to a pill and reflows; the arrows are an
    /// inverted T; the numpad docks beside the keys. Landscape on iPad
    /// (with `PH_QA_FULLSCREEN=1`), whatever fits on iPhone.
    func test20_TypePanelMovesAndResizes() {
        useFullScreenAppsIfAsked()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        launch()
        guard connect() else { return }
        sleep(1)
        guard openTypePanel() else { return }
        let panel = element("ph.type.panel")
        XCTAssertTrue(panel.waitForExistence(timeout: 3), "The Type panel didn't open")
        sleep(1)
        snap("type-panel-default")

        // The inverted T: ↑ above ↓, ← and → either side of ↓.
        let up = element("ph.type.key.up"), down = element("ph.type.key.down")
        let left = element("ph.type.key.left"), right = element("ph.type.key.right")
        XCTAssertTrue(up.exists && down.exists && left.exists && right.exists, "The arrow cluster is missing a key")
        if up.exists, down.exists, left.exists, right.exists {
            XCTAssertLessThan(up.frame.midY, down.frame.midY, "↑ isn't above ↓")
            XCTAssertEqual(up.frame.midX, down.frame.midX, accuracy: 2, "↑ isn't over ↓")
            XCTAssertLessThan(left.frame.midX, down.frame.midX, "← isn't left of ↓")
            XCTAssertGreaterThan(right.frame.midX, down.frame.midX, "→ isn't right of ↓")
            XCTAssertEqual(left.frame.midY, down.frame.midY, accuracy: 2, "← ↓ → aren't one row")
            XCTAssertGreaterThanOrEqual(up.frame.height, 43.5, "Arrow keys lost their 44 pt target")
            if ensureScratchFrontmost() { up.tap() }
        }
        // The keys: two rows, modifiers with esc and tab first.
        let command = element("ph.type.modifier.command"), delete = element("ph.type.key.delete")
        if command.exists, delete.exists {
            XCTAssertLessThan(command.frame.midY, delete.frame.midY, "The modifiers aren't the first row")
            XCTAssertEqual(element("ph.type.key.escape").frame.midY, command.frame.midY, accuracy: 2, "esc isn't with the modifiers")
        }

        // Drag by the grip to the top-left corner: the magnet snaps it.
        let grip = element("ph.type.grip")
        if grip.waitForExistence(timeout: 2) {
            let start = panel.frame
            let window = app.windows.firstMatch.frame
            grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.08)))
            sleep(1)
            snap("type-panel-dragged")
            let moved = panel.frame
            XCTAssertNotEqual(moved.origin, start.origin, "Dragging the grip didn't move the panel")
            XCTAssertLessThan(moved.minX - window.minX, 40, "The panel didn't snap to the leading edge")
            XCTAssertGreaterThanOrEqual(moved.minX, window.minX, "The panel left the window")
        } else {
            snap("missing-ph.type.grip")
        }

        // Resize from the right corner: narrower, never under the minimum,
        // and the layout reflows (stacked: the keys go under the field).
        let handle = element("ph.type.resize.trailing")
        if handle.exists {
            let before = panel.frame.width
            handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: -600, dy: 0)))
            sleep(1)
            snap("type-panel-narrow")
            let after = panel.frame.width
            XCTAssertLessThan(after, before, "Resizing didn't make the panel narrower")
            XCTAssertGreaterThanOrEqual(after, 359, "The panel went under its 360 pt minimum")
            let field = element("ph.type.field")
            if field.exists, command.exists {
                XCTAssertGreaterThan(command.frame.minY, field.frame.minY, "Narrow panel didn't stack the keys under the field")
            }
        } else if app.windows.firstMatch.frame.width >= 700 {
            snap("missing-ph.type.resize.trailing")
        }

        // The numpad docks in the same panel and goes away again.
        if tapIfExists("ph.type.tab.numpad") {
            sleep(1)
            let numpad = element("ph.type.numpad")
            XCTAssertTrue(numpad.waitForExistence(timeout: 2), "The numpad didn't show")
            // OT-11 (build 26): only the arrows and the numpad.
            XCTAssertFalse(element("ph.type.modifier.command").isHittable, "The modifier row stayed with the numpad")
            if numpad.exists {
                XCTAssertTrue(panel.frame.insetBy(dx: -1, dy: -1).contains(numpad.frame), "The numpad isn't inside the panel")
                XCTAssertGreaterThan(numpad.frame.width, panel.frame.width * 0.5, "The numpad doesn't fill the panel")
            }
            snap("type-numpad-docked")
            if ensureScratchFrontmost() { tapIfExists("ph.type.numpad.seven") }
            tapIfExists("ph.type.tab.numpad")
            sleep(1)
            XCTAssertFalse(element("ph.type.numpad").exists, "The numpad didn't go away")
        }

        // Fold to the pill and back.
        if tapIfExists("ph.type.collapse") {
            sleep(1)
            let pill = element("ph.type.pill")
            XCTAssertTrue(pill.waitForExistence(timeout: 2), "Collapse didn't leave a pill")
            XCTAssertFalse(panel.exists, "The panel stayed open behind the pill")
            snap("type-pill")
            pill.tap()
            XCTAssertTrue(panel.waitForExistence(timeout: 2), "Tapping the pill didn't open the panel")
        }

        // The place is remembered: close, open, same corner.
        let remembered = panel.frame
        tapIfExists("ph.type.close")
        sleep(1)
        if openTypePanel() {
            XCTAssertTrue(panel.waitForExistence(timeout: 3))
            sleep(1)
            XCTAssertEqual(panel.frame.minX, remembered.minX, accuracy: 2, "The panel didn't come back where it was")
            snap("type-panel-remembered")
            tapIfExists("ph.type.close")
        }
    }

    /// OT-11 (owner testing, build 26): the Type panel uses its space.
    /// Resizing taller grows the arrows and keys; the field is as tall as
    /// the arrows; the key rows span the panel; at its shortest the arrows
    /// go to one row; the app is named once. Portrait and landscape.
    func test22_TypePanelFillsItsSpace() {
        useFullScreenAppsIfAsked()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            launch()
            guard connect() else { return }
            sleep(1)
            guard openTypePanel() else { return }
            let panel = element("ph.type.panel")
            XCTAssertTrue(panel.waitForExistence(timeout: 3), "The Type panel didn't open")
            sleep(1)
            let tag = orientation == .portrait ? "portrait" : "landscape"
            snap("type-fill-\(tag)-default")

            let field = element("ph.type.field"), up = element("ph.type.key.up"), down = element("ph.type.key.down")
            let command = element("ph.type.modifier.command"), fn = element("ph.type.fn")
            // The target shows once: no "Typing into" placeholder in the field.
            let typingInto = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ OR placeholderValue BEGINSWITH %@", "Typing into", "Typing into"))
            XCTAssertLessThanOrEqual(typingInto.count, 1, "The target is named twice")
            XCTAssertTrue(element("ph.type.target").exists, "The header has no target")
            XCTAssertTrue(element("ph.type.accept").exists, "Live has no Accept (Tab) action")

            // Taller: drag a corner down. Build 27 bug 2: the panel rides
            // on the keyboard (iPad) or docks above it (iPhone), so there's
            // no room below; the top rises instead and the arrows grow.
            let handle = element("ph.type.resize.trailing")
            if handle.exists, up.exists, down.exists {
                let before = down.frame.height
                let panelBefore = panel.frame
                handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: -200, dy: 400)))
                sleep(1)
                snap("type-fill-\(tag)-tall")
                XCTAssertGreaterThan(panel.frame.height, panelBefore.height + 20, "The corner drag didn't make the panel taller: \(panelBefore) → \(panel.frame)")
                XCTAssertGreaterThan(down.frame.height, before + 4, "The arrows didn't grow with the panel")
                XCTAssertGreaterThan(down.frame.height, 48, "The arrows are still \(down.frame.height) pt tall")
                if app.keyboards.count > 0, let keyboard = app.keyboards.allElementsBoundByIndex.first {
                    XCTAssertLessThanOrEqual(panel.frame.maxY, keyboard.frame.minY + 1, "The taller panel went under the keyboard")
                }
                // Field and arrows share their band's height.
                if field.exists, up.frame.minY < down.frame.minY {
                    XCTAssertEqual(field.frame.minY, up.frame.minY, accuracy: 6, "The field doesn't start with the arrows")
                    XCTAssertEqual(field.frame.maxY, down.frame.maxY, accuracy: 6, "Empty strip under the field")
                }
                // The key rows span the panel.
                if command.exists, fn.exists {
                    XCTAssertLessThan(command.frame.minX - panel.frame.minX, 20, "The key rows don't start at the edge")
                    XCTAssertLessThan(panel.frame.maxX - fn.frame.maxX, 20, "Empty block right of the keys")
                }
                // Shortest: drag far up; on panels wide enough the arrows
                // go to one row.
                handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: -800)))
                sleep(1)
                snap("type-fill-\(tag)-short")
                if panel.frame.width >= 448, command.exists, command.frame.minY > up.frame.maxY {
                    XCTAssertEqual(up.frame.midY, down.frame.midY, accuracy: 2, "The shortest stacked panel didn't put the arrows in one row")
                }
            } else {
                snap("missing-ph.type.resize.trailing-\(tag)")
            }
            // OT-12: the target chip opens the loupe (Pro), attached to
            // the panel; with the mirror off it offers to start it.
            if tapIfExists("ph.type.target") {
                sleep(2)
                let loupe = element("ph.type.loupe")
                if loupe.waitForExistence(timeout: 3) {
                    XCTAssertEqual(loupe.frame.width, panel.frame.width, accuracy: 2, "The loupe isn't as wide as the panel")
                    XCTAssertTrue(loupe.frame.maxY <= panel.frame.minY + 1 || loupe.frame.minY >= panel.frame.maxY - 1, "The loupe covers the panel")
                    // Build 27 bug 1: the loupe's scaled picture made its
                    // frame ~4,536 pt wide and took the panel's taps.
                    XCTAssertLessThanOrEqual(loupe.frame.height, 201, "The loupe's frame is bigger than the loupe: \(loupe.frame)")
                    XCTAssertTrue(element("ph.type.target").isHittable, "The target chip isn't hittable with the loupe open")
                    XCTAssertTrue(element("ph.type.close").isHittable, "Close isn't hittable with the loupe open")
                    snap("type-loupe-\(tag)")
                    tapIfExists("ph.type.target")
                    sleep(1)
                    XCTAssertFalse(loupe.exists, "The target chip didn't close the loupe")
                } else {
                    snap("type-loupe-paywall-\(tag)")
                }
            }
            tapIfExists("ph.type.close")
            sleep(1)
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// OT-8 (owner testing, build 25): Ask's "Open Safari · Type “youtube”
    /// · Press ⏎" ran, but Save as key refused it. Walks Ask → Run → Save
    /// as key → the key on the deck → run it (it asks first, naming
    /// Safari). The two runs type "youtube" and Return into Safari on the
    /// Mac, so they only happen with `PH_QA_TYPE_IN_SAFARI=1`; without it
    /// the walk saves from the plan and cancels the key's confirmation.
    func test21_AskTypedPlanSavesAsKey() {
        let runs = ProcessInfo.processInfo.environment["PH_QA_TYPE_IN_SAFARI"] == "1"
        launch()
        guard connect() else { return }
        guard openAsk() else { return }
        let field = element("ph.ask.field")
        guard field.waitForExistence(timeout: 3) else { snap("missing-ask-field"); return }
        field.tap()
        field.typeText("Open Safari and type youtube and press return")
        tapIfExists("ph.ask.submit")
        XCTAssertTrue(element("ph.ask.run").waitForExistence(timeout: 10), "No Run after planning")
        snap("ask-typed-plan")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "can’t type text yet")).firstMatch.exists, "The old refusal is back")

        if runs {
            tapIfExists("ph.ask.run")
            let confirm = app.buttons["Run"].firstMatch
            if confirm.waitForExistence(timeout: 2), confirm.isHittable, !element("ph.ask.run").isHittable { confirm.tap() }
            XCTAssertTrue(element("ph.ask.saveAsKey").waitForExistence(timeout: 15), "No Save as key after the run")
            snap("ask-typed-result")
        }

        tapIfExists("ph.ask.saveAsKey")
        let name = element("ph.ask.name")
        XCTAssertTrue(name.waitForExistence(timeout: 3), "Save as key didn't ask for a name")
        let keyName = "YT \(Int.random(in: 100...999))"
        name.tap()
        // VQ-106: clear the whole default name, not just its first part.
        if let current = name.value as? String, !current.isEmpty, current != name.placeholderValue {
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 8))
        }
        name.typeText(keyName)
        sleep(1)
        // VQ-104: with the keyboard up, Save and Cancel scroll into view
        // above it (iPad portrait put them under it).
        let save = element("ph.ask.save")
        XCTAssertTrue(save.isHittable, "Save as key's Save is under the keyboard")
        XCTAssertTrue(element("ph.ask.cancel").isHittable, "Save as key's Cancel is under the keyboard")
        if app.keyboards.count > 0, let keyboard = app.keyboards.allElementsBoundByIndex.first, keyboard.frame.height > 100 {
            XCTAssertLessThanOrEqual(save.frame.maxY, keyboard.frame.minY + 1, "Save sits under the keyboard: \(save.frame)")
            XCTAssertLessThanOrEqual(name.frame.maxY, keyboard.frame.minY + 1, "The name field sits under the keyboard")
        }
        snap("ask-typed-naming")
        tapIfExists("ph.ask.save")
        let note = element("ph.ask.note")
        XCTAssertTrue(note.waitForExistence(timeout: 3), "Saving didn't confirm")
        if note.exists {
            XCTAssertTrue(note.label.hasPrefix("Saved as a key"), "Save as key failed: \(note.label)")
        }
        snap("ask-typed-saved")
        closeAsk()

        // The key is on the deck, and running it asks first.
        tapIfExists("ph.tab.deck")
        sleep(1)
        let key = app.descendants(matching: .any)
            .matching(identifier: "ph.deck.key")
            .matching(NSPredicate(format: "label CONTAINS %@", keyName))
            .firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5), "The saved key isn't on the deck")
        guard key.exists else { return }
        snap("deck-typed-key")
        key.tap()
        let run = app.buttons["Run"].firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 3), "The typing key didn't ask first")
        let message = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Types into")).firstMatch
        XCTAssertTrue(message.exists, "The confirmation doesn't say where the text goes")
        snap("deck-typed-key-confirm")
        if runs {
            run.tap()
            sleep(3)
            snap("deck-typed-key-ran")
        } else {
            // VQ-106: the iPhone shows a popover with only Run; tapping
            // outside it dismisses it.
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists, cancel.isHittable {
                cancel.tap()
            } else {
                dismissMenu()
            }
            sleep(1)
        }

        // The key editor shows the typed step as editable text.
        if tapIfExists("ph.deck.edit") {
            key.tap()
            sleep(1)
            snap("deck-typed-key-inspector")
            XCTAssertTrue(element("ph.inspector.asksFirst").exists, "No Ask before running in the inspector")
            dismissSheet()
            tapIfExists("ph.deck.done")
        }
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        return (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    // MARK: - Owner testing, build 26

    /// OT-9: the Send sheet in the pixel identity, portrait then landscape.
    /// Asserts the Send | Inbox switch, three source chips of one size on
    /// one line, the field with its Add button, compact device cards
    /// (offline Macs smaller still), and a sheet no taller than its
    /// content (its Done button isn't pushed to the top of the screen
    /// with a short list).
    func test23_SendSheetLayout() {
        useFullScreenAppsIfAsked()
        launch()
        guard connect() else { return }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            let tag = orientation == .portrait ? "portrait" : "landscape"
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            guard tapIfExists("ph.transfer.send") else { break }
            sleep(1)
            snap("send-\(tag)")

            XCTAssertTrue(element("ph.transfer.tab").exists, "Send | Inbox switch (\(tag))")
            XCTAssertTrue(element("ph.send.tab.send").exists, "Send side of the switch (\(tag))")
            XCTAssertTrue(element("ph.send.tab.inbox").exists, "Inbox side of the switch (\(tag))")

            let chips = ["photos", "files", "clipboard"].map { element("ph.send.source.\($0)") }
            if chips.allSatisfy({ $0.exists }) {
                let frames = chips.map(\.frame)
                let heights = frames.map(\.height)
                let widths = frames.map(\.width)
                let tops = frames.map(\.minY)
                XCTAssertLessThanOrEqual(heights.max()! - heights.min()!, 1, "Source chips share one height (\(tag)): \(heights)")
                XCTAssertLessThanOrEqual(widths.max()! - widths.min()!, 1, "Source chips share one width (\(tag)): \(widths)")
                XCTAssertLessThanOrEqual(tops.max()! - tops.min()!, 1, "Source chips sit on one line (\(tag)): \(tops)")
                XCTAssertGreaterThanOrEqual(heights.min()!, 44, "Source chips are 44 pt targets (\(tag))")
            } else {
                snap("missing-source-chips-\(tag)")
            }
            XCTAssertTrue(element("ph.send.field").exists, "Text-or-link field (\(tag))")
            XCTAssertTrue(element("ph.send.add").exists, "Field's Add button (\(tag))")

            let cards = app.descendants(matching: .any).matching(identifier: "ph.transfer.macCard").allElementsBoundByIndex
            let offline = app.descendants(matching: .any).matching(identifier: "ph.send.offlineCard").allElementsBoundByIndex
            // OT-16: cards sized to the names (64, or 80 with two-line
            // names), offline Macs the same muted card, one height for all,
            // one width per grid, inside the chips' row.
            let allCards = cards + offline
            let cardHeights = allCards.map(\.frame.height)
            for card in allCards {
                XCTAssertLessThanOrEqual(card.frame.height, 84, "Device cards are compact (\(tag)): \(card.frame)")
            }
            if let low = cardHeights.min(), let high = cardHeights.max() {
                XCTAssertLessThanOrEqual(high - low, 1, "Live and offline cards share one height (\(tag)): \(cardHeights)")
            }
            let cardWidths = allCards.map(\.frame.width)
            if let low = cardWidths.min(), let high = cardWidths.max() {
                XCTAssertLessThanOrEqual(high - low, 1, "Cards share one column width (\(tag)): \(cardWidths)")
            }
            if chips.allSatisfy({ $0.exists }) {
                let row = chips[0].frame.union(chips[2].frame)
                for card in allCards {
                    XCTAssertGreaterThanOrEqual(card.frame.minX, row.minX - 1, "Card inside the margins (\(tag))")
                    XCTAssertLessThanOrEqual(card.frame.maxX, row.maxX + 1, "Card inside the margins (\(tag))")
                }
                // OT-15: the switch and Done sit on the same margins as the
                // chips, centred on one line.
                let tabSwitch = element("ph.transfer.tab").frame
                let doneFrame = element("ph.send.done").frame
                XCTAssertLessThanOrEqual(abs(tabSwitch.minX - row.minX), 2, "Switch on the leading margin (\(tag)): \(tabSwitch.minX) vs \(row.minX)")
                XCTAssertLessThanOrEqual(abs(doneFrame.maxX - row.maxX), 2, "Done's target on the trailing margin (\(tag)): \(doneFrame.maxX) vs \(row.maxX)")
                XCTAssertLessThanOrEqual(abs(tabSwitch.midY - doneFrame.midY), 1, "Switch and Done centred on one line (\(tag))")
                // OT-17: the three chips have one face. Their fill, sampled
                // at both ends (clear of icon and label), matches.
                checkChipsLookAlike(chips, tag: tag)
            }

            // Sized to the content: with no more than a row of cards and no
            // tray, the sheet starts well below the top of the window.
            let done = element("ph.send.done")
            if done.exists, cards.count <= 3, offline.count <= 3, !element("ph.send.trayItem").exists {
                let window = app.windows.firstMatch.frame
                XCTAssertGreaterThan(done.frame.minY, window.minY + window.height * 0.25, "Sheet sized to its content (\(tag)): Done at \(done.frame.minY)")
            }

            // OT-15: on iPad the sheet is a card centred on the window, and
            // Send and Inbox are one size (switching doesn't move it).
            let sheet = element("ph.send.sheet")
            let sendFrame = sheet.exists ? sheet.frame : .zero
            if sheet.exists, UIDevice.current.userInterfaceIdiom == .pad {
                let window = app.windows.firstMatch.frame
                XCTAssertLessThanOrEqual(abs(sendFrame.midX - window.midX), 2, "Sheet centred across the window (\(tag)): \(sendFrame) in \(window)")
                XCTAssertLessThanOrEqual(abs(sendFrame.midY - window.midY), 2, "Sheet centred down the window (\(tag)): \(sendFrame) in \(window)")
                XCTAssertLessThanOrEqual(sendFrame.width, 561, "Sheet at most 560 wide (\(tag))")
            }
            if tapIfExists("ph.send.tab.inbox") {
                sleep(1)
                snap("inbox-\(tag)")
                if sheet.exists {
                    let inboxFrame = sheet.frame
                    XCTAssertLessThanOrEqual(abs(inboxFrame.height - sendFrame.height), 1, "Send and Inbox one height (\(tag)): \(sendFrame.height) / \(inboxFrame.height)")
                    XCTAssertLessThanOrEqual(abs(inboxFrame.midX - sendFrame.midX), 1, "Inbox doesn't move the sheet (\(tag))")
                    let empty = element("ph.inbox.empty")
                    if empty.exists {
                        let header = element("ph.send.header").frame
                        let panel = CGRect(x: inboxFrame.minX, y: header.maxY, width: inboxFrame.width, height: inboxFrame.maxY - header.maxY)
                        XCTAssertLessThanOrEqual(abs(empty.frame.midX - panel.midX), 2, "Nothing yet centred across (\(tag)): \(empty.frame) in \(panel)")
                        XCTAssertLessThanOrEqual(abs(empty.frame.midY - panel.midY), 4, "Nothing yet centred down (\(tag)): \(empty.frame) in \(panel)")
                    }
                }
                tapIfExists("ph.send.tab.send")
            }
            if !tapIfExists("ph.send.done") { dismissSheet() }
            sleep(1)
        }
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    /// OT-14: badges draw above their controls' glass, never clipped.
    /// Runs on the free plan, where the header's Pro circles carry the lock
    /// (and the Send circle its unseen dot when the Inbox has new items).
    /// For each badge (`ph.badge.*`, exposed by `-qa.exposeBadges`): it
    /// touches its control, sits on the 4 pt grid relative to it, and its
    /// colour on screen is the badge's own (sampled from a screenshot), not
    /// the glass's: a badge under the glass reads washed out.
    func test25_BadgesAboveGlass() {
        launch(free: true)
        guard connect() else { return }
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            let tag = orientation == .portrait ? "portrait" : "landscape"
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            snap("badges-\(tag)")
            let controls = ["ph.header.screen", "ph.header.capture", "ph.transfer.send"].map(element).filter(\.exists)
            let badges = ["proLock", "dot"].flatMap { kind in
                app.descendants(matching: .any).matching(identifier: "ph.badge.\(kind)").allElementsBoundByIndex.map { (kind, $0) }
            }
            if badges.isEmpty { snap("no-badges-\(tag)") }
            let shot = XCUIScreen.main.screenshot()
            for (kind, badge) in badges {
                let frame = badge.frame
                guard let control = controls.first(where: { $0.frame.insetBy(dx: -12, dy: -12).intersects(frame) }) else { continue }
                XCTAssertTrue(control.frame.intersects(frame), "\(kind) touches its control (\(tag)): \(frame) / \(control.frame)")
                let dx = (frame.minX - control.frame.minX).truncatingRemainder(dividingBy: 4)
                let dy = (frame.minY - control.frame.minY).truncatingRemainder(dividingBy: 4)
                XCTAssertLessThanOrEqual(min(abs(dx), 4 - abs(dx)), 0.5, "\(kind) on the 4 pt grid (\(tag))")
                XCTAssertLessThanOrEqual(min(abs(dy), 4 - abs(dy)), 0.5, "\(kind) on the 4 pt grid (\(tag))")
                // The lock tile's left edge (clear of its glyph); the dot's centre.
                let point = kind == "proLock" ? CGPoint(x: frame.minX + 3, y: frame.midY) : CGPoint(x: frame.midX, y: frame.midY)
                if let colour = pixel(at: point, in: shot) {
                    XCTAssertGreaterThan(colour.b - colour.r, 60, "\(kind) drawn above the glass, in its own blue (\(tag)): rgb \(colour)")
                }
            }
        }
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    /// OT-18: the header's compact ⌘K button. In iPad landscape: about 80
    /// pt wide, 44 tall, centred on the header's line; a tap opens Ask in
    /// the column with its field focused, and the button then reads open;
    /// with Ask back to the deck, ⌘K opens it again.
    func test26_HeaderAskButton() {
        launch()
        guard connect() else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        let ask = element("ph.ask")
        guard ask.waitForExistence(timeout: 3) else {
            snap("no-ask-button")
            XCUIDevice.shared.orientation = .portrait
            return
        }
        snap("header-ask-button")
        XCTAssertLessThanOrEqual(ask.frame.width, 96, "Compact ⌘K button, not a field: \(ask.frame)")
        XCTAssertLessThanOrEqual(abs(ask.frame.height - 44), 1, "44 pt tall: \(ask.frame)")
        let more = element("ph.header.more")
        if more.exists {
            XCTAssertLessThanOrEqual(abs(ask.frame.midY - more.frame.midY), 1, "On the header's line with More")
            XCTAssertLessThan(ask.frame.maxX, more.frame.minX, "In the trailing cluster, before More")
        }
        ask.tap()
        sleep(1)
        snap("header-ask-open")
        XCTAssertTrue(element("ph.ask.field").waitForExistence(timeout: 3), "⌘K button opens Ask")
        if element("ph.column.deck").exists {
            let value = ask.value as? String ?? ""
            XCTAssertTrue(value.hasPrefix("Open"), "The button shows Ask is open: \(value)")
            element("ph.column.deck").tap()
            sleep(1)
            app.typeKey("k", modifierFlags: .command)
            sleep(1)
            snap("header-ask-cmd-k")
            XCTAssertTrue(element("ph.ask.field").waitForExistence(timeout: 3), "⌘K still opens Ask")
            closeAsk()
        } else {
            closeAsk()
        }
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    /// OT-10: the capture preview fills the screen. Takes the default
    /// capture and asserts, in portrait, that the picture fills the width
    /// (or, for a tall capture, most of the height), sits centred between
    /// the header and the dock, and that the dock is anchored at the
    /// bottom; double-tap zooms in and back out; then the same in
    /// landscape.
    func test24_CapturePreviewFillsPortrait() {
        useFullScreenAppsIfAsked()
        XCUIDevice.shared.orientation = .portrait
        launch()
        guard connect() else { return }
        guard tapIfExists("ph.header.capture") else { return }
        let picture = element("ph.capture.preview")
        guard picture.waitForExistence(timeout: 15) else {
            snap("missing-ph.capture.preview")
            dismissSheet()
            return
        }
        sleep(1)
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            let tag = orientation == .portrait ? "portrait" : "landscape"
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            snap("capture-\(tag)")
            let window = app.windows.firstMatch.frame
            let well = element("ph.capture.well").exists ? element("ph.capture.well").frame : picture.frame
            let dock = element("ph.capture.dock")
            guard dock.exists else { snap("missing-ph.capture.dock-\(tag)"); continue }

            // Aspect-fit: one side meets the room's edge (16 pt margins).
            let fillsWidth = well.width >= window.width - 2 * 16 - 2
            let fillsHeight = well.height >= (dock.frame.minY - well.minY) - 2 * 12 - 2
            XCTAssertTrue(fillsWidth || fillsHeight, "Picture fills the room (\(tag)): \(well) in \(window)")
            if orientation == .portrait, well.width >= well.height {
                XCTAssertTrue(fillsWidth, "A wide capture fills the width in portrait: \(well.width) of \(window.width)")
            }
            // Build 27 bug 4: `ph.capture.dock` is the dock's card, a row
            // of actions tall, not a frame running past the window.
            XCTAssertLessThan(dock.frame.height, 160, "The dock's frame is the card (\(tag)): \(dock.frame)")
            XCTAssertEqual(picture.frame.width, well.width, accuracy: 1, "ph.capture.preview is the well's frame (\(tag))")
            // The dock is at the bottom, under the picture, clear of the
            // home indicator.
            XCTAssertGreaterThanOrEqual(dock.frame.minY, well.maxY, "Dock under the picture (\(tag))")
            XCTAssertGreaterThan(dock.frame.maxY, window.maxY - 64, "Dock anchored at the bottom (\(tag)): \(dock.frame)")
            XCTAssertLessThanOrEqual(dock.frame.maxY, window.maxY, "Dock inside the window (\(tag))")
            // No empty band: the picture is centred between the header
            // (its close button) and the dock.
            let close = app.buttons["Close capture"].firstMatch
            if close.exists {
                let above = well.minY - close.frame.maxY
                let below = dock.frame.minY - well.maxY
                XCTAssertLessThanOrEqual(abs(above - below), 4, "Picture centred between header and dock (\(tag)): \(above) above, \(below) below")
            }

            picture.doubleTap()
            sleep(1)
            snap("capture-zoomed-\(tag)")
            picture.doubleTap()
            sleep(1)
        }
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        dismissSheet()
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
            // OT-14: badges become findable (`ph.badge.<kind>`) for test25.
            "-qa.exposeBadges", "YES",
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
        checkConnectToastClearOfPair()
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

    /// VQ-107: while the launch reconnect waits, "Connecting to <Mac>…"
    /// and its Cancel sit under the picker's Pair and Settings, never over
    /// them, and the text isn't squeezed (at AX3 it read "Con- / necti…").
    private func checkConnectToastClearOfPair() {
        let toast = element("ph.connect.toast"), cancel = element("ph.connect.cancel"), pair = element("ph.connect.pair")
        guard toast.exists, pair.exists else { return }
        snap("picker-connecting")
        XCTAssertFalse(toast.frame.intersects(pair.frame), "The connecting toast covers Pair: \(toast.frame) / \(pair.frame)")
        if cancel.exists {
            XCTAssertFalse(cancel.frame.intersects(pair.frame), "The toast's Cancel covers Pair: \(cancel.frame) / \(pair.frame)")
        }
        XCTAssertGreaterThan(toast.frame.width, 120, "The connecting toast is squeezed: \(toast.frame)")
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
    /// True when the Mac's front app is the scratch app the walks may type
    /// into (`PH_QA_SCRATCH_APP`, default TextEdit), read from the Type
    /// panel's "Typing into …" line. Checked before every step that types
    /// on the Mac: in build 25 the front app changed mid-run and a walk typed
    /// into another app. When the line isn't shown, the step is allowed
    /// (nothing reaches the Mac without the Type panel).
    private func ensureScratchFrontmost() -> Bool {
        let scratch = ProcessInfo.processInfo.environment["PH_QA_SCRATCH_APP"] ?? "TextEdit"
        let target = element("ph.type.target")
        guard target.waitForExistence(timeout: 2) else { return true }
        if target.label.localizedCaseInsensitiveContains(scratch) { return true }
        snap("skipped-typing-front-app-not-\(slug(scratch))")
        print("PixelHandUITests: skipped a typing step because the Mac's front app isn't \(scratch) (\(target.label)).")
        return false
    }

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

    // MARK: - Live text sync (protocol 17)

    /// Live text sync walks. They type into the Mac's front app, so they
    /// run only with `PH_QA_LIVE_SYNC=1`, and expect the QA script to have
    /// TextEdit in front on the Mac with a new, empty plain-text document
    /// (`open -a TextEdit`, ⌘N, ⇧⌘T). Optional:
    ///   PH_QA_LIVE_SYNC_MARKER=<text>  text the QA script types on the Mac
    ///     while test27 waits (e.g. `osascript -e 'tell application
    ///     "System Events" to keystroke "<text>"'`).
    ///   PH_QA_LIVE_SYNC_OUT=<path>  test29 writes what the Mac's document
    ///     should hold there, for the script to compare with TextEdit's
    ///     text afterwards.
    private func openSyncedLiveField(_ tag: String) -> (field: XCUIElement, badge: XCUIElement)? {
        guard ProcessInfo.processInfo.environment["PH_QA_LIVE_SYNC"] == "1" else {
            snap("skipped-live-sync")
            XCTContext.runActivity(named: "SKIPPED: set PH_QA_LIVE_SYNC=1 with TextEdit in front on the Mac") { _ in }
            return nil
        }
        launch()
        guard connect() else { return nil }
        sleep(1)
        guard openTypePanel() else { return nil }
        let field = element("ph.type.field")
        guard field.waitForExistence(timeout: 3) else {
            snap("missing-ph.type.field")
            return nil
        }
        let badge = element("ph.type.sync")
        XCTAssertTrue(badge.waitForExistence(timeout: 3), "Live has no sync badge")
        // The Mac's state arrives within a moment of opening Live.
        let synced = NSPredicate(format: "label == %@", "In sync with the Mac")
        let wait = XCTNSPredicateExpectation(predicate: synced, object: badge)
        if XCTWaiter.wait(for: [wait], timeout: 5) != .completed {
            snap("\(tag)-not-synced")
            XCTFail("The badge never said SYNC (label: \(badge.label), value: \(badge.value ?? "")). Is TextEdit in front on the Mac?")
            return nil
        }
        field.tap()
        sleep(1)
        snap("\(tag)-synced")
        return (field, badge)
    }

    private func fieldText(_ field: XCUIElement) -> String {
        (field.value as? String) ?? ""
    }

    /// Typing on the Mac shows in the iPad's Live field.
    func test27_LiveSyncTypeOnMac() {
        guard let (field, badge) = openSyncedLiveField("type-on-mac") else { return }
        let marker = ProcessInfo.processInfo.environment["PH_QA_LIVE_SYNC_MARKER"] ?? "typed on the Mac"
        let shows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", marker), object: field)
        let result = XCTWaiter.wait(for: [shows], timeout: 30)
        snap("type-on-mac-after")
        XCTAssertEqual(result, .completed, "The field never showed the Mac's “\(marker)” (it shows “\(fieldText(field))”)")
        XCTAssertEqual(badge.label, "In sync with the Mac")
        tapIfExists("ph.type.close")
    }

    /// Accept ⇥ stays in Live; what Tab puts in the Mac's field shows in
    /// the iPad's from the Mac's next value change (TextEdit has no
    /// suggestion, so Tab inserts a tab).
    func test28_LiveSyncTabAccept() {
        guard let (field, _) = openSyncedLiveField("tab-accept") else { return }
        app.typeText("accept")
        sleep(1)
        let before = fieldText(field)
        XCTAssertTrue(tapIfExists("ph.type.accept"), "Live has no Accept (Tab)")
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: field)
        let result = XCTWaiter.wait(for: [changed], timeout: 3)
        snap("tab-accept-after")
        XCTAssertEqual(result, .completed, "The accepted text never showed in the field (still “\(before)”)")
        tapIfExists("ph.type.close")
    }

    /// Editing on the iPad lands on the Mac: typed text, then a caret moved
    /// to the start with a tap and a letter typed there.
    func test29_LiveSyncEditFromIPad() {
        guard let (field, badge) = openSyncedLiveField("edit-from-ipad") else { return }
        let start = fieldText(field)
        app.typeText("pixel hand")
        sleep(2)
        snap("edit-typed")
        XCTAssertTrue(fieldText(field).contains("pixel hand"), "The typed text isn't in the field: “\(fieldText(field))”")
        XCTAssertEqual(badge.label, "In sync with the Mac", "The badge didn't settle back to SYNC")
        // The caret is free: tap at the very start and type there.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.0)).withOffset(CGVector(dx: 2, dy: 14)).tap()
        sleep(1)
        app.typeText("X")
        sleep(2)
        snap("edit-caret-moved")
        let text = fieldText(field)
        XCTAssertTrue(text.hasPrefix("X"), "The caret didn't move to the start (field: “\(text)”)")
        if let out = ProcessInfo.processInfo.environment["PH_QA_LIVE_SYNC_OUT"] {
            try? text.write(toFile: out, atomically: true, encoding: .utf8)
        }
        XCTAssertNotEqual(text, start)
        tapIfExists("ph.type.close")
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

    /// Opens the Type panel from whichever keyboard button this window
    /// has: the dock's, the rail's (iPhone landscape, VQ-105) or the pad's.
    /// `required`: no button at all is a failure (VQ-105 had the walks
    /// return early and pass), with a `missing-keyboard-button` snapshot.
    @discardableResult
    private func openTypePanel(required: Bool = true) -> Bool {
        for id in ["ph.dock.keyboard", "ph.rail.keyboard", "ph.trackpad.keyboard"] where tapIfExists(id, timeout: 1) {
            return true
        }
        if required {
            snap("missing-keyboard-button")
            XCTFail("No keyboard button (ph.dock.keyboard, ph.rail.keyboard or ph.trackpad.keyboard) to open the Type panel")
        }
        return false
    }

    private func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        sleep(1)
    }

    private func slug(_ text: String) -> String {
        String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// OT-17: the three source chips have one face: their fill, sampled
    /// just inside each end (clear of icon and label), matches within a
    /// few levels, and so does the label's colour band (the darkest or
    /// lightest pixel across the chip's middle line).
    private func checkChipsLookAlike(_ chips: [XCUIElement], tag: String) {
        let shot = XCUIScreen.main.screenshot()
        var fills: [(r: Int, g: Int, b: Int)] = []
        for chip in chips {
            let f = chip.frame
            for x in [f.minX + 5, f.maxX - 5] {
                if let colour = pixel(at: CGPoint(x: x, y: f.midY), in: shot) { fills.append(colour) }
            }
        }
        guard let first = fills.first else { return }
        for colour in fills {
            let diff = max(abs(colour.r - first.r), abs(colour.g - first.g), abs(colour.b - first.b))
            XCTAssertLessThanOrEqual(diff, 12, "Source chips share one fill (\(tag)): \(fills)")
        }
        // No accent text: a chip whose ink is blue (b ≫ r) is the odd one.
        for chip in chips {
            let f = chip.frame
            var bluest = 0
            for step in stride(from: f.minX + 12, through: f.maxX - 12, by: 2) {
                if let colour = pixel(at: CGPoint(x: step, y: f.midY), in: shot) { bluest = max(bluest, colour.b - colour.r) }
            }
            XCTAssertLessThan(bluest, 90, "\(chip.identifier): icon and label in ink, not accent (\(tag))")
        }
    }

    /// The colour at `point` (points, in the app's orientation) in a
    /// screenshot, 0–255 per channel.
    private func pixel(at point: CGPoint, in shot: XCUIScreenshot) -> (r: Int, g: Int, b: Int)? {
        let image = shot.image
        guard point.x >= 0, point.y >= 0, point.x < image.size.width, point.y < image.size.height else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let one = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in
            image.draw(at: CGPoint(x: -point.x, y: -point.y))
        }
        guard let cg = one.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
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
