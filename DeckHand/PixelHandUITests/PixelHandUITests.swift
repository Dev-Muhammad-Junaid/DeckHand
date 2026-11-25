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
//                      pairing code (from its "Pair a device" window). When the
//                      approval card offers "Enter pairing code", the walk
//                      pairs with it, so later runs connect without asking.
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

    // MARK: - Helpers

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

    /// Picks the first Mac in the list and waits for the shell. Returns
    /// false (with a screenshot) if no Mac shows up or it never allows us.
    @discardableResult
    private func connect(timeout: TimeInterval = 90) -> Bool {
        let pill = element("ph.header.macPill")
        if pill.waitForExistence(timeout: 6) {
            // A paired Mac reconnects by itself; give it a moment.
            for _ in 0..<8 where !isConnected() { sleep(1) }
            if isConnected() { sleep(1); return true }
        }
        let row = element("ph.connect.macRow")
        acceptSystemAlerts(timeout: 1)
        guard row.waitForExistence(timeout: 45) else {
            snap("no-mac-found")
            return false
        }
        row.tap()
        sleep(1)
        snap("waiting-for-allow")
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
            return false
        }
        sleep(2)
        return true
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
