//
//  LockState.swift
//  DeckHandMac
//
//  Knows whether this Mac is locked (S8), for the locked-Mac gate
//  (`LockGate.swift`) and the remote's banner. The rule is Core's
//  `LockPolicy` / `LockReader`; this file only reads the witnesses:
//
//  | Witness | API |
//  | --- | --- |
//  | On the console | `CGSessionCopyCurrentDictionary`, `kCGSSessionOnConsoleKey` (public) |
//  | Screen locked | the same dictionary's undocumented `CGSSessionScreenIsLocked` key |
//  | Screen locked | notify(3) `com.apple.sessionagent.screenIsLocked` (public call, undocumented name) |
//  | Console user | `SCDynamicStoreCopyConsoleUser` (public) |
//  | Notifications | `com.apple.screenIsLocked` / `…Unlocked` (distributed), `NSWorkspace.sessionDidResignActive` / `…BecomeActive` |
//
//  No private symbol is called, so nothing needs `dlsym`; an undocumented
//  key or name that stops answering only removes that witness, and the
//  public session dictionary still says whether this session is on the
//  console. Any witness saying locked wins; an unlock counts once every
//  witness has said so for `LockPolicy.settle` seconds.
//
//  Looks happen at start, on every witness's change, and once a second
//  while a remote is connected. The session dictionary is a WindowServer
//  round trip, so it is read off the main actor and bounded; no answer in
//  time counts as locked.
//
//  DEBUG: `defaults write com.widgetsflow.pixelhand.mac PixelHandTestLockState screenLocked`
//  (or `offConsole`) makes the Mac read as locked without locking it.
//

import AppKit
import CoreGraphics
import Darwin
import Foundation
import LoomKit
import SystemConfiguration

@MainActor
final class MacLockMonitor {
    static let shared = MacLockMonitor()

    /// The gate's state. `.offConsole` until the first look finishes.
    private(set) var state: MacLockState = .offConsole

    private var reader = LockReader()
    private var witnesses = LockWitnesses()
    private var holdSetAt: Date?
    private var notifyToken: Int32 = 0
    private var notifyRegistered = false
    private var connections: [UUID: LoomConnectionHandle] = [:]
    private var pollTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var looking = false
    private var lookAgain = false
    private var unansweredLooks = 0
    private var gateDisabled = false
    private var pendingConnectWake = false
    private let notificationRelay = LockNotificationRelay()

    private static let notifyName = "com.apple.sessionagent.screenIsLocked"
    private static let pollInterval: Duration = .seconds(1)
    private static let sessionReadBound: TimeInterval = 0.5
    #if DEBUG
    private static let testOverrideKey = "PixelHandTestLockState"
    #endif

    private init() {
        registerNotify()
        notificationRelay.onEvent = { [weak self] event in
            self?.handle(event)
        }
        notificationRelay.start()
        // The first look is synchronous for the cheap witnesses so the gate
        // has a reading before the first message; the session dictionary
        // follows on its own queue.
        witnesses.notifyScreenLocked = readNotifyState()
        witnesses.consoleUserIsThisUser = Self.readConsoleUserIsThisUser()
        look()
    }

    // MARK: - Connections

    /// Sends the current state to a new remote, declares display activity
    /// for the connection, and keeps looking once a second while any
    /// remote is connected. Before the first reading has finished (the
    /// first connection after launch) both wait for it, so the remote
    /// never sees a passing "off console" and the display still wakes.
    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {
        connections[id] = handle
        if reader.hasFirstReading {
            let current = state
            Task { try? await handle.send(.system(.lockState(state: current))) }
            DisplayWake.shared.note(.connected, lock: current)
        } else {
            pendingConnectWake = true
        }
        startPollingIfNeeded()
        look()
    }

    /// Approved remotes, by connection id.
    var connectionHandles: [UUID: LoomConnectionHandle] { connections }

    func removeConnection(id: UUID) {
        connections.removeValue(forKey: id)
        if connections.isEmpty {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                self?.look()
            }
        }
    }

    // MARK: - Witnesses

    private func registerNotify() {
        var token: Int32 = 0
        let status = notify_register_dispatch(Self.notifyName, &token, DispatchQueue.main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notifyChanged()
            }
        }
        if status == UInt32(NOTIFY_STATUS_OK) {
            notifyToken = token
            notifyRegistered = true
        } else {
            DeckHandLog.connection.error("Lock state: couldn't watch \(Self.notifyName, privacy: .public) (status \(status, privacy: .public)); using the other witnesses")
        }
    }

    private func readNotifyState() -> Bool? {
        guard notifyRegistered else { return nil }
        var value: UInt64 = 0
        guard notify_get_state(notifyToken, &value) == UInt32(NOTIFY_STATUS_OK) else { return nil }
        return value != 0
    }

    private func notifyChanged() {
        let locked = readNotifyState()
        witnesses.notifyScreenLocked = locked
        // An unlock seen here after a lock notification means the lock
        // notification's unlock was lost; drop the hold.
        if locked == false, witnesses.notificationHold == .screenLocked {
            witnesses.notificationHold = nil
        }
        look()
    }

    private func handle(_ event: LockNotificationRelay.Event) {
        switch event {
        case .screenLocked:
            setHold(.screenLocked)
        case .screenUnlocked:
            if witnesses.notificationHold == .screenLocked { witnesses.notificationHold = nil }
        case .sessionResigned:
            setHold(.offConsole)
        case .sessionBecameActive:
            if witnesses.notificationHold == .offConsole { witnesses.notificationHold = nil }
        }
        look()
    }

    private func setHold(_ hold: MacLockState) {
        // Off console is the stronger hold; a lock notification doesn't
        // weaken it.
        if witnesses.notificationHold == .offConsole, hold == .screenLocked { return }
        witnesses.notificationHold = hold
        holdSetAt = Date()
        // A lock acts at once, before the slower witnesses are read.
        apply(at: Date())
    }

    /// Reads every witness and updates `state`. Overlapping looks collapse
    /// into one more look after the current one.
    func look() {
        if looking {
            lookAgain = true
            return
        }
        looking = true
        witnesses.notifyScreenLocked = readNotifyState()
        Task { [weak self] in
            let session = await Self.readSessionBounded()
            let consoleUser = await Self.readOffMain { Self.readConsoleUserIsThisUser() }
            guard let self else { return }
            self.witnesses.sessionOnConsole = session.onConsole
            self.witnesses.sessionScreenLocked = session.screenLocked
            self.witnesses.consoleUserIsThisUser = consoleUser
            self.clearStaleOffConsoleHold()
            self.apply(at: Date())
            self.looking = false
            if self.lookAgain {
                self.lookAgain = false
                self.look()
            }
        }
    }

    /// A switch-away hold whose "back" notification was lost: once the
    /// console is this user's again and on console for a while, drop it.
    private func clearStaleOffConsoleHold() {
        guard witnesses.notificationHold == .offConsole,
              witnesses.consoleUserIsThisUser == true,
              witnesses.sessionOnConsole == true,
              let holdSetAt, Date().timeIntervalSince(holdSetAt) >= LockPolicy.settle
        else { return }
        witnesses.notificationHold = nil
    }

    private func apply(at now: Date) {
        var raw = LockPolicy.reading(witnesses)
        if raw == nil {
            unansweredLooks += 1
            // No witness can be read at all on this macOS: rather than
            // refuse everything for good, turn the gate off and say so.
            if unansweredLooks >= 3 {
                if !gateDisabled {
                    gateDisabled = true
                    DeckHandLog.connection.error("Lock state: no witness answers on this macOS; the locked-Mac gate is off")
                }
                raw = .unlocked
            }
        } else {
            unansweredLooks = 0
        }
        #if DEBUG
        if let forced = UserDefaults.standard.string(forKey: Self.testOverrideKey).flatMap(MacLockState.init(rawValue:)),
           forced.isLocked {
            raw = forced == .offConsole || raw == .offConsole ? .offConsole : .screenLocked
        }
        #endif
        let previous = state
        let hadFirstReading = reader.hasFirstReading
        let next = reader.update(raw, at: now)
        scheduleSettleLook()
        let isFirstReading = !hadFirstReading && reader.hasFirstReading
        guard next != previous || isFirstReading else { return }
        state = next
        if next != previous { log(previous: previous, next: next) }
        let message = ControlMessage.system(.lockState(state: next))
        for handle in connections.values {
            Task { try? await handle.send(message) }
        }
        if isFirstReading, pendingConnectWake {
            pendingConnectWake = false
            DisplayWake.shared.note(.connected, lock: next)
        }
        if next != previous {
            MacSystemSession.lockStateChanged(from: previous, to: next)
        }
    }

    /// Looks again when a pending unlock will have settled.
    private func scheduleSettleLook() {
        settleTask?.cancel()
        guard let deadline = reader.settleDeadline else { return }
        let wait = max(0.05, deadline.timeIntervalSinceNow + 0.05)
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.look()
        }
    }

    private func log(previous: MacLockState, next: MacLockState) {
        switch next {
        case .screenLocked:
            DeckHandLog.connection.info("Locked: this Mac's screen is locked; remotes can type and click at the lock screen, nothing else runs until it is unlocked")
        case .offConsole:
            DeckHandLog.connection.info("Locked: another user, or the login window, is on this Mac's screen; nothing a remote sends is posted until this session is back")
        case .unlocked:
            DeckHandLog.connection.info("Unlocked: this Mac's screen is unlocked (was \(previous.rawValue, privacy: .public))")
        }
    }

    // MARK: - Readers (off the main actor)

    private struct SessionReading: Sendable {
        var onConsole: Bool?
        var screenLocked: Bool?
    }

    /// `CGSessionCopyCurrentDictionary` on a utility queue, bounded. No
    /// answer in time, or no dictionary, counts as locked.
    private static func readSessionBounded() async -> SessionReading {
        await withCheckedContinuation { (continuation: CheckedContinuation<SessionReading, Never>) in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .utility).async {
                once.resume(readSession())
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + sessionReadBound) {
                once.resume(SessionReading(onConsole: nil, screenLocked: true))
            }
        }
    }

    nonisolated private static func readSession() -> SessionReading {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return SessionReading(onConsole: nil, screenLocked: true)
        }
        let onConsole = (dict["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue
        let locked = (dict["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue
        return SessionReading(onConsole: onConsole, screenLocked: locked)
    }

    nonisolated private static func readConsoleUserIsThisUser() -> Bool? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String? else { return nil }
        if name == "loginwindow" || name.isEmpty { return false }
        return uid == getuid()
    }

    private static func readOffMain<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: body())
            }
        }
    }
}

/// Resumes a continuation with the first value only.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// Lock, unlock and fast-user-switch notifications, delivered immediately
/// even while Pixel Hand isn't the active app.
@MainActor
private final class LockNotificationRelay: NSObject {
    enum Event: Sendable {
        case screenLocked, screenUnlocked, sessionResigned, sessionBecameActive
    }

    var onEvent: ((Event) -> Void)?

    func start() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: Notification.Name("com.apple.screenIsLocked"), object: nil, suspensionBehavior: .deliverImmediately)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil, suspensionBehavior: .deliverImmediately)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    // Delivered on the main thread, but entered from Objective-C, so hop
    // explicitly rather than rely on the isolation check.
    @objc nonisolated private func screenLocked() { deliver(.screenLocked) }
    @objc nonisolated private func screenUnlocked() { deliver(.screenUnlocked) }
    @objc nonisolated private func sessionResigned() { deliver(.sessionResigned) }
    @objc nonisolated private func sessionBecameActive() { deliver(.sessionBecameActive) }

    nonisolated private func deliver(_ event: Event) {
        Task { @MainActor [weak self] in
            self?.onEvent?(event)
        }
    }
}
