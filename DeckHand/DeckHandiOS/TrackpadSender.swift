//
//  TrackpadSender.swift
//  DeckHandiOS
//

import Foundation
import LoomKit
import os
import QuartzCore

/// What became of a command sent with `TrackpadSender.sendConfirmed(_:)`.
enum CommandDelivery: Sendable, Equatable {
    /// Sent to a host that doesn't send receipts; nothing more is known.
    case sent
    /// The Mac received it and handed it to input injection.
    case confirmed
    /// The Mac received it but couldn't act (Accessibility isn't granted).
    case failed
    /// No receipt arrived in time.
    case timedOut
}

/// Actor that owns the active connection handle and throttles outgoing control messages.
/// Tuned for buttery-smooth 120 Hz trackpad input on iPad Pro (ProMotion).
actor TrackpadSender {
    private let handle: LoomConnectionHandle

    // ── Timing ──────────────────────────────────────────────────────
    // 120 Hz matches iPad Pro's ProMotion refresh rate so no touch
    // data is thrown away.  On non-ProMotion iPads (60 Hz) this just
    // means the cap is never hit. Settings can drop it to 60 to halve
    // packet volume when the link is congested.
    private var minimumInterval: Double = 1.0 / 120.0

    /// Changes the outgoing throttle. Takes effect from the next delta; any
    /// already-scheduled flush completes on the old interval.
    func setSendRate(hz: Int) {
        minimumInterval = 1.0 / Double(max(1, hz))
    }

    // Independent timestamps so that continuous scrolling doesn't starve
    // mouse movement (and vice versa). Previously both streams shared
    // `lastSentAt`, which meant fast scroll input could delay cursor
    // updates by up to 8 ms per tick.
    private var lastMouseSentAt: Double = 0     // CACurrentMediaTime()
    private var lastScrollSentAt: Double = 0

    // ── Delta accumulator ───────────────────────────────────────────
    private var pendingDeltaX: Float = 0
    private var pendingDeltaY: Float = 0
    private var isSendScheduled: Bool = false

    // ── Scroll accumulator ──────────────────────────────────────────
    private var pendingScrollDX: Float = 0
    private var pendingScrollDY: Float = 0
    private var isScrollSendScheduled: Bool = false
    /// Tracks whether we're inside an active scroll gesture so the host
    /// receives a single `.begin` followed by `.changed` ticks. The next
    /// `.changed` flips this back to false on `endScroll(...)`.
    private var inScrollGesture: Bool = false

    // ── Diagnostics ─────────────────────────────────────────────────
    // The send path used to swallow every error (`try?`) and log nothing,
    // so "the iPad isn't sending" and "the send failed on the wire" looked
    // identical to "no finger movement." These prove the iPad is actually
    // transmitting and surface transport failures, throttled so the 120 Hz
    // path doesn't flood Console.
    private var mouseSendCount: UInt64 = 0
    private var lastSendErrorLogAt: Double = 0

    // ── Drag (iOS interaction lane) ─────────────────────────────────
    /// Repeats `mouseDown` while a button is held, so the Mac knows the
    /// remote is still there (it releases an unrefreshed button).
    private var dragKeepAlive: [MouseButton: Task<Void, Never>] = [:]

    // ── Delivery receipts ───────────────────────────────────────────
    /// Set when the host's `hostStatus` lists `ProtocolFeature.commandReceipts`.
    /// A host that doesn't is sent plain messages, never a `deck.run`.
    private var hostSendsReceipts = false
    private var pendingReceipts: [String: CheckedContinuation<CommandDelivery, Never>] = [:]
    /// How long to wait for a receipt before calling it lost.
    private static let receiptTimeout: Duration = .milliseconds(1500)

    init(handle: LoomConnectionHandle) {
        self.handle = handle
    }

    // MARK: - Throttled mouse delta (120 Hz)

    func sendMouseDelta(dx: Float, dy: Float) async {
        pendingDeltaX += dx
        pendingDeltaY += dy

        let now = CACurrentMediaTime()
        let elapsed = now - lastMouseSentAt

        if elapsed >= minimumInterval {
            await flushMouseDelta()
        } else if !isSendScheduled {
            isSendScheduled = true
            let delay = minimumInterval - elapsed
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await self.flushMouseDelta()
            }
        }
    }

    private func flushMouseDelta() async {
        isSendScheduled = false
        guard pendingDeltaX != 0 || pendingDeltaY != 0 else { return }

        let dx = pendingDeltaX
        let dy = pendingDeltaY
        pendingDeltaX = 0
        pendingDeltaY = 0
        lastMouseSentAt = CACurrentMediaTime()

        mouseSendCount &+= 1
        if mouseSendCount % 120 == 1 {
            DeckHandLog.input.info("📤 iPad mouseDelta stream alive (\(self.mouseSendCount) sent)")
        }
        await send(.input(.mouseDelta(dx: dx, dy: dy)))
    }

    // MARK: - Throttled scroll (120 Hz)

    func sendScroll(dx: Float, dy: Float) async {
        pendingScrollDX += dx
        pendingScrollDY += dy

        let now = CACurrentMediaTime()
        let elapsed = now - lastScrollSentAt

        if elapsed >= minimumInterval {
            await flushScroll()
        } else if !isScrollSendScheduled {
            isScrollSendScheduled = true
            let delay = minimumInterval - elapsed
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await self.flushScroll()
            }
        }
    }

    private func flushScroll() async {
        isScrollSendScheduled = false
        guard pendingScrollDX != 0 || pendingScrollDY != 0 else { return }

        let dx = pendingScrollDX
        let dy = pendingScrollDY
        pendingScrollDX = 0
        pendingScrollDY = 0
        lastScrollSentAt = CACurrentMediaTime()

        // The first delta inside a gesture goes out with `.begin`; every
        // subsequent delta is `.changed` until the iPad surfaces a finger
        // lift via `endScroll(...)`.
        let phase: ScrollPhase
        if inScrollGesture {
            phase = .changed
        } else {
            phase = .begin
            inScrollGesture = true
        }
        await send(.input(.mouseScroll(dx: dx, dy: dy, phase: phase)))
    }

    /// Called when the iPad detects the scroll-driving fingers have lifted.
    /// We flush any pending delta first so the `.end` event lands after the
    /// last real movement, then mark the gesture closed.
    func endScroll(momentumDX: Float = 0, momentumDY: Float = 0) async {
        if pendingScrollDX != 0 || pendingScrollDY != 0 {
            await flushScroll()
        }
        if inScrollGesture {
            await send(.input(.mouseScroll(dx: 0, dy: 0, phase: .end)))
            inScrollGesture = false
        }
        // If the iPad reports residual velocity (true momentum), let the
        // host know so AppKit's scroll views can run their decay animation.
        if momentumDX != 0 || momentumDY != 0 {
            await send(.input(.mouseScroll(dx: momentumDX, dy: momentumDY, phase: .momentumBegin)))
            await send(.input(.mouseScroll(dx: 0, dy: 0, phase: .momentumEnd)))
        }
    }

    // MARK: - Immediate sends (clicks, shortcuts, etc.)

    func sendClick(_ button: MouseButton) async {
        await send(.input(.mouseClick(button: button)))
    }

    func sendDoubleClick(_ button: MouseButton) async {
        await send(.input(.mouseDoubleClick(button: button)))
    }

    func sendShortcut(_ keys: [String]) async {
        await send(.input(.keyboardShortcut(keys: keys)))
    }

    // MARK: - Typing and drags (iOS interaction lane)

    /// Types `text` on the Mac, in pieces the Mac accepts
    /// (`TextChunker`), in order.
    func typeText(_ text: String) async {
        for chunk in TextChunker.chunks(text) {
            await send(.input(.typeText(text: chunk)))
        }
    }

    /// Presses a special key (arrows, Return, Escape, …), with modifiers.
    func sendKey(_ key: RemoteKey, modifiers: [KeyModifier] = []) async {
        await send(.input(.keyboardShortcut(keys: key.chord(with: modifiers))))
    }

    /// Replays an edit of the typing field: Backspaces, then text.
    func sendTypingEdit(_ edit: TypingEdit) async {
        for _ in 0..<min(edit.deletes, 500) {
            await send(.input(.keyboardShortcut(keys: [RemoteKey.delete.wireName])))
        }
        if !edit.insert.isEmpty {
            await typeText(edit.insert)
        }
    }

    /// Presses `button` and holds it until `sendMouseUp`, refreshing it
    /// every `DragPolicy.keepDownInterval`.
    func sendMouseDown(_ button: MouseButton) async {
        await flushMouseDelta()
        await send(.input(.mouseDown(button: button)))
        dragKeepAlive[button]?.cancel()
        dragKeepAlive[button] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DragPolicy.keepDownInterval))
                guard !Task.isCancelled, let self else { return }
                await self.refreshMouseDown(button)
            }
        }
    }

    private func refreshMouseDown(_ button: MouseButton) async {
        guard dragKeepAlive[button] != nil else { return }
        await send(.input(.mouseDown(button: button)))
    }

    /// Releases a held button, after the moves before it.
    func sendMouseUp(_ button: MouseButton) async {
        dragKeepAlive.removeValue(forKey: button)?.cancel()
        await flushMouseDelta()
        await send(.input(.mouseUp(button: button)))
    }

    /// A trackpad gesture's command (S11).
    func sendGesture(_ command: GestureCommand) async {
        await send(command.message)
    }

    // MARK: - Clipboard (S10)

    func setClipboardSync(enabled: Bool) async {
        await send(.sharing(.clipboardSync(enabled: enabled)))
    }

    /// Puts `text` on the Mac's clipboard, pressing ⌘V there with `paste`.
    func setMacClipboard(_ text: String, paste: Bool) async {
        await send(.sharing(.setClipboard(text: text, paste: paste)))
    }

    /// Runs a Mac-wide action (Mission Control, Show Desktop, …).
    func sendSystemAction(_ action: SystemMacro) async {
        await send(.system(.run(action: action)))
    }

    func sendLaunchApp(_ bundleID: String) async {
        await send(.apps(.launchApp(bundleID: bundleID)))
    }

    /// Activate `bundleID` on the Mac and inject `keys` once it's frontmost.
    /// Single message — the host coordinates the ordering so the shortcut
    /// doesn't leak into whatever window was previously focused.
    func sendAppShortcut(bundleID: String, keys: [String]) async {
        await send(.apps(.appShortcut(bundleID: bundleID, keys: keys)))
    }

    /// Asks the Mac to walk `bundleID`'s menu bar via Accessibility and
    /// return every shortcut it advertises.
    func requestMenuShortcuts(bundleID: String) async {
        await send(.deck(.requestAppMenuShortcuts(bundleID: bundleID)))
    }

    func sendMediaKey(_ key: MediaKey) async {
        await send(.input(.media(key: key)))
    }

    /// Issues a screenshot request tagged with `requestID` so the iPad can
    /// reject responses that belong to a previous, timed-out request.
    /// `mode` defaults to full-screen so callers that don't care about
    /// region/window capture stay one-liner.
    func requestScreenshot(
        requestID: String,
        mode: CaptureMode = .fullScreen,
        quality: CaptureQuality = .standard
    ) async {
        await send(.capture(.requestScreenshot(requestID: requestID, mode: mode, quality: quality)))
    }

    /// Asks the Mac to enumerate visible windows so the iPad can present a
    /// picker before issuing a `.window(windowID:)` capture.
    func requestWindowList(requestID: String) async {
        await send(.capture(.requestWindowList(requestID: requestID)))
    }

    /// Briefly highlights the Mac cursor's current location with an animated
    /// crosshair overlay.
    func locateCursor() async {
        await send(.system(.run(action: .locateCursor)))
    }

    func requestAppList() async {
        await send(.apps(.requestAppList))
    }

    /// Resync query for the approval handshake — see
    /// `PairingMessage.requestAuthorizationStatus`.
    func requestAuthorizationStatus() async {
        await send(.pairing(.requestAuthorizationStatus))
    }

    /// Liveness heartbeat — see `SessionMessage.ping`.
    func sendPing(seq: UInt64) async {
        await send(.session(.ping(seq: seq)))
    }

    // MARK: - Live mini mirror (WID-403)

    /// Asks the Mac to start streaming low-res screen frames. The default
    /// 640px @ 20 fps keeps frames in the 20–50 KB range — smooth on LAN,
    /// far below anything that could starve the 120 Hz input path. The
    /// expanded thumbnail re-negotiates at a higher width (see ControlView).
    func startMirror(fps: Int = 20, maxWidth: Int = 640, displayID: UInt32? = nil, codec: MirrorCodec = .jpeg, windowID: UInt32? = nil) async {
        await send(.mirror(.start(fps: fps, maxWidth: maxWidth, displayID: displayID, codec: codec, windowID: windowID)))
    }

    func stopMirror() async {
        await send(.mirror(.stop))
    }

    func switchSpace(_ direction: SpaceDirection, displayID: UInt32?) async {
        await send(.system(.switchSpace(direction: direction, displayID: displayID)))
    }

    // MARK: - Delivery receipts

    func setHostSendsReceipts(_ enabled: Bool) {
        hostSendsReceipts = enabled
    }

    /// Runs `action` and waits for the Mac's receipt, for controls that
    /// show whether the command arrived. Returns `.sent` straight away when
    /// the host doesn't send receipts. Other traffic isn't held up while it
    /// waits.
    func sendConfirmed(_ action: Action) async -> CommandDelivery {
        guard hostSendsReceipts else {
            await send(action.message)
            return .sent
        }
        let requestID = UUID().uuidString
        return await withCheckedContinuation { continuation in
            // Registered before the send goes out, so even an instant
            // receipt finds its continuation. Every path resumes it exactly
            // once: the receipt or the timeout, whichever comes first.
            pendingReceipts[requestID] = continuation
            Task {
                await self.send(.deck(.run(requestID: requestID, action: action)))
            }
            Task {
                try? await Task.sleep(for: Self.receiptTimeout)
                self.finishReceipt(requestID, with: .timedOut)
            }
        }
    }

    func receivedReceipt(requestID: String, outcome: ActionOutcome) {
        finishReceipt(requestID, with: outcome.isSuccess ? .confirmed : .failed)
    }

    private func finishReceipt(_ requestID: String, with delivery: CommandDelivery) {
        pendingReceipts.removeValue(forKey: requestID)?.resume(returning: delivery)
    }

    // MARK: - Core send

    private func send(_ message: ControlMessage) async {
        do {
            try await handle.send(message)
        } catch {
            // Throttled: a dead connection would otherwise log every 120 Hz
            // mouseDelta. The heartbeat in ControlView tears the session down
            // shortly after, so one error/sec is enough to see the cause.
            let now = CACurrentMediaTime()
            if now - lastSendErrorLogAt > 1 {
                lastSendErrorLogAt = now
                DeckHandLog.connection.error("📤 iPad send failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
