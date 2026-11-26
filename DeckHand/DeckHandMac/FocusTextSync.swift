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
//  - `input.textEdit`: one at a time. The Mac reads the field fresh,
//    checks the edit's context (`TextEditCheck`: apply, rebase, conflict,
//    refuse), sets the selection through Accessibility (or arrow keys
//    from the caret it knows), then **types** the replacement through
//    `TypingQueue`, the path Live already uses. `AXValue` is never set.
//    When the typing is done it sends the new `textState` and then
//    `textEditResult`. The Mac is the source of truth: on a conflict it
//    types nothing and sends its own state ("MAC WINS" on the iPad).
//  - `input.textSelect`: the same selection step, nothing typed.
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
            return publish(elementKey: nil, reading: .init(readable: .locked, window: nil, length: 0, selection: .caret(0), canSetSelection: false, canEdit: false))
        }
        guard sequence > publishedSequence, isWatching else {
            return lastSent ?? .unreadable(.noField)
        }
        publishedSequence = sequence
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
        guard TextSyncPolicy.allowsCaretMove(secureInput: FocusTextObserver.secureInputEnabled(), lock: MacLockMonitor.shared.state) else {
            DeckHandLog.input.info("Focus text: caret move refused (secure input or locked)")
            return
        }
        for chord in TextSyncPolicy.chords(for: move) {
            TypingQueue.shared.shortcut(chord)
        }
    }

    private func enqueue(_ job: @escaping @MainActor () async -> Void) {
        let previous = work
        work = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await job()
        }
    }

    private func applyEdit(_ request: TextEditRequest, from connection: LoomConnectionHandle) async {
        DeckHandLog.input.info("Focus text: \(TextSyncLog.describe(request), privacy: .public)")
        // Earlier typing first, so the field we check is the one we type in.
        await TypingQueue.shared.idle()
        let state = await readNow()
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
            if await placeSelection(range, in: state) {
                type(request.replacement, replacing: range)
                await TypingQueue.shared.idle()
                // Give the app a moment to post its notifications.
                try? await Task.sleep(for: .milliseconds(40))
            } else {
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
        let state = await readNow()
        guard state.field == request.field, state.readable.isReadable, !FocusTextObserver.secureInputEnabled(),
              request.range.end <= state.length else {
            DeckHandLog.input.info("Focus text: \(TextSyncLog.describe(request), privacy: .public) dropped")
            return
        }
        if await placeSelection(request.range, in: state) {
            await TypingQueue.shared.idle()
        }
        _ = await readNow()
    }

    /// Puts the field's selection at `range`: through Accessibility where
    /// it's settable, else with arrow keys from the caret the Mac knows.
    private func placeSelection(_ range: PixelHandCore.TextRange, in state: FocusedTextState) async -> Bool {
        if state.selection == range { return true }
        if state.canSetSelection, await observer.select(range) { return true }
        guard let window = state.window,
              let chords = TextSyncPolicy.arrowChords(window: window.value, windowStart: window.start, from: state.selection, to: range) else {
            return false
        }
        for chord in chords { TypingQueue.shared.shortcut(chord) }
        return true
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
