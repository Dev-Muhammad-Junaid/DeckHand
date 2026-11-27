//
//  FocusTextSync.swift
//  DeckHandMac
//
//  Live text sync, Phase 1 (protocol 17, `RD-live-sync-and-caret.md` §3):
//  the Mac's side of the iPad's synced Live field. Owned with the focus
//  tracker (Mac system control lane).
//
//  - Remotes ask with `system.watchFocus(on: true, wantsText: true)` while
//    their Live field is open. Nothing reads text otherwise.
//  - `FocusTextObserver` watches the front app's focused field
//    (`AXObserver`, 30 a second at most) and the geometry poll in
//    `FocusTracker` calls `pollTick` as a safety net. Each reading goes
//    through Core's `TextRevisionTracker` (field token, revision) and is
//    sent as `system.textState` when it changed.
//  - `input.textEdit`: one at a time. The Mac waits for keys it already
//    posted to reach the field (two equal reads in a row), reads it fresh,
//    checks the edit's context (`TextEditCheck`: apply, rebase, conflict,
//    refuse), then puts the caret there and **confirms it with a read**
//    before typing (`TextSelectionPlacement`: Accessibility, else arrow
//    keys from the caret it read, else nothing is typed and the edit is
//    refused). Then it **types** the replacement through `TypingQueue`,
//    the path Live already uses, and waits until the field shows it
//    (`TextSelectionPlacement.landed`) before it sends the new
//    `textState` and then `textEditResult`. `AXValue` is never set. The
//    Mac is the source of truth: on a conflict it types nothing and sends
//    its own state ("MAC WINS" on the iPad). Build 29 bug 9: typing went
//    out before the selection had taken, at the old caret.
//  - `input.textSelect`: the same placement, nothing typed.
//  - `input.caretMove`, and keys and typed text while a remote watches
//    text (`inOrder`): behind any edit or selection still running, so
//    Accept ⇥ never lands inside the text typed before it.
//  - `input.caretMove`: arrow chords through `TypingQueue`, refused under
//    secure input.
//  - Locked (`LockPolicy.withholdsText`): one `.locked` state, nothing
//    read, edits dropped. Secure input: `.secure`, edits refused, keys
//    still go (they type the password).
//  - Logs name revisions and offsets only (`TextSyncLog`), never text.
//

import Foundation
import LoomKit

@MainActor
final class FocusTextSync {
    static let shared = FocusTextSync()

    private var watchers: [UUID: LoomConnectionHandle] = [:]
    private var tracker = TextRevisionTracker()
    private var lastSent: FocusedTextState?
    private var windowStart: Int?
    private let observer = FocusTextObserver()
    private var reading = false
    private var readAgain = false
    /// Readings are numbered when asked for; one that comes back after a
    /// newer one was published is dropped, so a stale text never follows
    /// a fresh one (an observer read racing an edit's read).
    private var readSequence = 0
    private var publishedSequence = 0
    /// Edits, selections and caret moves run one at a time, in order.
    private var work: Task<Void, Never>?
    /// Jobs queued or running on `work`.
    private var pendingJobs = 0
    /// The last reading had the app's own selection (not a stand-in).
    private var lastSelectionKnown = false

    /// A fresh reading and whether its selection is the app's own.
    private struct Observed {
        var state: FocusedTextState
        var selectionKnown: Bool
    }

    /// Reads taken while waiting for posted keys to reach the field.
    private static let stableReads = 8
    private static let stableInterval = Duration.milliseconds(25)
    /// How long the Mac waits for its typing to show before answering.
    private static let landedReads = 20

    private init() {
        observer.onChange = {
            Task { @MainActor in FocusTextSync.shared.refresh() }
        }
    }

    var isWatching: Bool { !watchers.isEmpty }

    // MARK: Watching

    /// `watchFocus(on:wantsText:)` from `connection`.
    func watch(_ wantsText: Bool, connection: LoomConnectionHandle) {
        if wantsText {
            let isNew = watchers[connection.id] == nil
            watchers[connection.id] = connection
            if watchers.count == 1, isNew {
                DeckHandLog.context.info("Focus text: sync started")
                observer.start(front: Self.front())
            }
            if isNew, let lastSent {
                send(.system(.textState(state: lastSent)), to: [connection])
            }
            refresh()
        } else {
            remove(connection.id)
        }
    }

    func removeConnection(id: UUID) {
        remove(id)
    }

    /// The lock changed: send `.locked` at once, or read again.
    func lockStateChanged(_ state: MacLockState) {
        guard isWatching else { return }
        if LockPolicy.withholdsText(state) {
            publish(elementKey: nil, reading: .init(readable: .locked, window: nil, length: 0, selection: .caret(0), canSetSelection: false, canEdit: false))
        } else {
            observer.start(front: Self.front())
            refresh()
        }
    }

    /// The geometry poll looked (4–8 a second): catch anything the
    /// observer missed.
    func pollTick() {
        guard isWatching else { return }
        refresh()
    }

    private func remove(_ id: UUID) {
        guard watchers.removeValue(forKey: id) != nil else { return }
        if watchers.isEmpty {
            observer.stop()
            tracker.reset()
            lastSent = nil
            windowStart = nil
            publishedSequence = readSequence
            work?.cancel()
            work = nil
            DeckHandLog.context.info("Focus text: sync stopped")
        }
    }

    // MARK: Reading

    /// Reads the field (off the main actor) and sends it if it changed.
    /// Readings never overlap; one asked for during a read follows it.
    func refresh() {
        guard isWatching else { return }
        guard !reading else {
            readAgain = true
            return
        }
        reading = true
        Task {
            _ = await readNow()
            reading = false
            if readAgain {
                readAgain = false
                refresh()
            }
        }
    }

    /// One reading, sent when it changed. Returns the state.
    @discardableResult
    private func readNow() async -> FocusedTextState {
        let lock = MacLockMonitor.shared.state
        if LockPolicy.withholdsText(lock) {
            return publish(elementKey: nil, reading: .init(readable: .locked, window: nil, length: 0, selection: .caret(0), canSetSelection: false, canEdit: false))
        }
        readSequence += 1
        let sequence = readSequence
        let result = await observer.read(front: Self.front(), lock: lock, previousStart: windowStart)
        // The Mac may have locked while the observer looked.
        if LockPolicy.withholdsText(MacLockMonitor.shared.state) {
            lastSelectionKnown = false
            return publish(elementKey: nil, reading: .init(readable: .locked, window: nil, length: 0, selection: .caret(0), canSetSelection: false, canEdit: false))
        }
        guard sequence > publishedSequence, isWatching else {
            return lastSent ?? .unreadable(.noField)
        }
        publishedSequence = sequence
        lastSelectionKnown = result.selectionKnown
        return publish(elementKey: result.elementKey, reading: result.reading)
    }

    @discardableResult
    private func publish(elementKey: UInt64?, reading: TextRevisionTracker.Reading) -> FocusedTextState {
        let (state, changed) = tracker.observe(elementKey: elementKey, reading: reading)
        windowStart = state.window?.start
        if changed || lastSent == nil {
            lastSent = state
            send(.system(.textState(state: state)), to: Array(watchers.values))
        }
        return state
    }

    // MARK: Edits from a remote

    func edit(_ request: TextEditRequest, from connection: LoomConnectionHandle) {
        enqueue { [weak self] in await self?.applyEdit(request, from: connection) }
    }

    func select(_ request: TextSelectRequest, from connection: LoomConnectionHandle) {
        enqueue { [weak self] in await self?.applySelect(request) }
    }

    func caretMove(_ move: CaretMove) {
        inOrder {
            guard TextSyncPolicy.allowsCaretMove(secureInput: FocusTextObserver.secureInputEnabled(), lock: MacLockMonitor.shared.state) else {
                DeckHandLog.input.info("Focus text: caret move refused (secure input or locked)")
                return
            }
            for chord in TextSyncPolicy.chords(for: move) {
                TypingQueue.shared.shortcut(chord)
            }
        }
    }

    /// Keys and typed text from a remote (`keyboardShortcut`, `typeText`,
    /// `caretMove`). While a remote watches text and an edit or selection
    /// is still running, they wait behind it (Accept ⇥ pressed after typed
    /// text lands after it); otherwise they go at once, as before.
    func inOrder(_ body: @escaping @MainActor () -> Void) {
        guard isWatching, pendingJobs > 0 else {
            body()
            return
        }
        enqueue {
            body()
            await TypingQueue.shared.idle()
        }
    }

    private func enqueue(_ job: @escaping @MainActor () async -> Void) {
        let previous = work
        pendingJobs += 1
        work = Task {
            await previous?.value
            defer { self.pendingJobs = max(0, self.pendingJobs - 1) }
            guard !Task.isCancelled else { return }
            await job()
        }
    }

    private func applyEdit(_ request: TextEditRequest, from connection: LoomConnectionHandle) async {
        DeckHandLog.input.info("Focus text: \(TextSyncLog.describe(request), privacy: .public)")
        // Earlier typing first, and until the field shows it, so the field
        // we check is the one we type in.
        await TypingQueue.shared.idle()
        let observed = await readStable()
        let state = observed.state
        let decision: TextEditCheck.Decision
        if FocusTextObserver.secureInputEnabled() {
            decision = .refused(.secure)
        } else {
            let span = TextEditCheck.span(for: request, fieldLength: state.length)
            let units = state.readable.isReadable ? await observer.span(span) : nil
            decision = TextEditCheck.decide(
                request,
                field: state.field,
                readable: state.readable,
                canEdit: state.canEdit,
                fieldLength: state.length,
                span: units ?? [],
                spanStart: span.start
            )
        }

        var outcome = decision.outcome
        switch decision {
        case let .apply(range), let .rebase(range):
            if let placed = await placeSelection(range, from: observed) {
                type(request.replacement, replacing: range)
                await TypingQueue.shared.idle()
                await waitUntilLanded(range, replacement: request.replacement, lengthBefore: placed.state.length)
            } else {
                // Never type at a guessed position: the iPad says so.
                outcome = .refused(reason: .notEditable)
            }
        case .conflict, .refused:
            break
        }
        // The state for this revision goes out first (from `publish`, to
        // every watcher, the requester among them), then the answer.
        let after = await readNow()
        let result = TextEditResult(field: request.field, request: request.request, outcome: outcome, revision: after.revision)
        DeckHandLog.input.info("Focus text: \(TextSyncLog.describe(result), privacy: .public)")
        send(.system(.textEditResult(result: result)), to: [connection])
    }

    private func applySelect(_ request: TextSelectRequest) async {
        await TypingQueue.shared.idle()
        let observed = await readStable()
        let state = observed.state
        guard state.field == request.field, state.readable.isReadable, !FocusTextObserver.secureInputEnabled(),
              request.range.end <= state.length else {
            DeckHandLog.input.info("Focus text: \(TextSyncLog.describe(request), privacy: .public) dropped")
            return
        }
        if await placeSelection(request.range, from: observed) == nil {
            DeckHandLog.input.info("Focus text: \(TextSyncLog.describe(request), privacy: .public) not placed")
        }
        _ = await readNow()
    }

    /// Reads until two readings in a row agree (keys already posted have
    /// reached the field), at most `stableReads` times.
    private func readStable() async -> Observed {
        var previous = await readNow()
        for _ in 1..<Self.stableReads {
            try? await Task.sleep(for: Self.stableInterval)
            let next = await readNow()
            if next.window == previous.window, next.length == previous.length, next.selection == previous.selection {
                return Observed(state: next, selectionKnown: lastSelectionKnown)
            }
            previous = next
        }
        return Observed(state: previous, selectionKnown: lastSelectionKnown)
    }

    /// Puts the field's selection at `range` and confirms it with a fresh
    /// read (`TextSelectionPlacement`): Accessibility where it's settable,
    /// else arrow keys from the caret the Mac read. Returns the confirming
    /// reading, or `nil` when it couldn't (then nothing may be typed).
    private func placeSelection(_ range: PixelHandCore.TextRange, from start: Observed) async -> Observed? {
        var current = start
        var attempts = TextSelectionPlacement.Attempts()
        while true {
            let step = TextSelectionPlacement.next(
                target: range,
                current: current.selectionKnown ? current.state.selection : nil,
                canSetSelection: current.state.canSetSelection,
                window: current.state.window,
                attempts: attempts
            )
            switch step {
            case .done:
                return current
            case .fail:
                DeckHandLog.input.info("Focus text: caret not placed at \(range.start, privacy: .public)+\(range.length, privacy: .public) (settable \(current.state.canSetSelection, privacy: .public), caret known \(current.selectionKnown, privacy: .public))")
                return nil
            case .accessibility:
                attempts.accessibility += 1
                _ = await observer.select(range)
                current = await readStable()
            case let .arrows(chords):
                attempts.arrows += 1
                for chord in chords { TypingQueue.shared.shortcut(chord) }
                await TypingQueue.shared.idle()
                current = await readStable()
            }
        }
    }

    /// Waits (briefly) until the field shows the typed replacement, so the
    /// answer and the next edit never race keys still in the app's queue.
    /// The Mac's own autocorrect may change it: then it stops waiting.
    private func waitUntilLanded(_ range: PixelHandCore.TextRange, replacement: String, lengthBefore: Int) async {
        for _ in 0..<Self.landedReads {
            let state = await readNow()
            if TextSelectionPlacement.landed(range: range, replacement: replacement, lengthBefore: lengthBefore, after: state) {
                return
            }
            try? await Task.sleep(for: Self.stableInterval)
        }
        DeckHandLog.input.info("Focus text: typing not seen at \(range.start, privacy: .public) after \(Self.landedReads, privacy: .public) reads")
    }

    /// Types `replacement` over the selection: a deletion is one Delete
    /// (the selection goes), text replaces it as typed.
    private func type(_ replacement: String, replacing range: PixelHandCore.TextRange) {
        if replacement.isEmpty {
            if range.length > 0 { TypingQueue.shared.shortcut(["delete"]) }
            return
        }
        TypingQueue.shared.type(replacement, preferKeys: replacement.count <= TextSyncPolicy.fastTypingThreshold)
    }

    // MARK: Sending

    private func send(_ message: ControlMessage, to handles: [LoomConnectionHandle]) {
        for handle in handles {
            Task { try? await handle.send(message) }
        }
    }

    private static func front() -> FocusTextObserver.Front? {
        guard let front = FocusReader.frontmost() else { return nil }
        return FocusTextObserver.Front(pid: front.pid, name: front.name, bundleID: front.bundleID)
    }
}
