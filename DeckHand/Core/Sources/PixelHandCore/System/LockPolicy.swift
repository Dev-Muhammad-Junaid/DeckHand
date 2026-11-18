//
//  LockPolicy.swift
//  PixelHandCore
//
//  The locked-Mac gate's rules (S8). A remote must not see or drive more of
//  a locked Mac than someone standing at it could: while the screen is
//  locked a remote may type the password and click, but launch nothing,
//  read no window, menu or app list, and run no system action; when another
//  user (or the login window) holds the console, nothing a remote sends
//  reaches this session at all.
//
//  The Mac reads several witnesses (`DeckHandMac/LockState.swift`), this
//  file turns them into one reading, holds an unlock until it has settled,
//  and decides each message. `DeckHandMac/LockGate.swift` applies it in
//  front of the router.
//
//  Behaviour re-implemented from Sill's documented locked-Mac rule (no code
//  copied): any witness saying locked wins, a lock acts at once, an unlock
//  only after it has held for `settle` seconds.
//

import Foundation

/// What the remote is told about the Mac's console. Sent as
/// `SystemMessage.lockState(state:)`.
public enum MacLockState: String, Codable, Sendable, Hashable, CaseIterable {
    /// This user's session is on the console and its screen is unlocked.
    case unlocked
    /// This session is on the console with its lock screen up.
    case screenLocked
    /// Another user's session, the login window, or nobody is on the console.
    case offConsole

    public var isLocked: Bool { self != .unlocked }

    /// One line for the remote's banner. `macName` is the Mac's name as the
    /// remote shows it.
    public func bannerText(macName: String) -> String? {
        switch self {
        case .unlocked:
            nil
        case .screenLocked:
            "\(macName) is locked. Type its password and press Return to unlock it; apps, windows and shortcuts come back once it is unlocked."
        case .offConsole:
            "Another user is using \(macName), or it is at the login window. Nothing you send reaches it until your account is back."
        }
    }
}

/// Every source the Mac reads for the lock state. `nil` means that witness
/// isn't available or hasn't answered yet.
public struct LockWitnesses: Equatable, Sendable {
    /// `kCGSessionOnConsoleKey` from `CGSessionCopyCurrentDictionary`.
    public var sessionOnConsole: Bool?
    /// The same dictionary's undocumented `CGSSessionScreenIsLocked` key.
    public var sessionScreenLocked: Bool?
    /// notify(3) state of `com.apple.sessionagent.screenIsLocked`.
    public var notifyScreenLocked: Bool?
    /// Whether the console user is this process's user
    /// (`SCDynamicStoreCopyConsoleUser`).
    public var consoleUserIsThisUser: Bool?
    /// A lock (`.screenLocked`) or switch-away (`.offConsole`) notification
    /// seen with no unlock or switch back since. A lost notification never
    /// holds the Mac locked for good: the Mac clears the hold once another
    /// witness has seen the change.
    public var notificationHold: MacLockState?

    public init(
        sessionOnConsole: Bool? = nil,
        sessionScreenLocked: Bool? = nil,
        notifyScreenLocked: Bool? = nil,
        consoleUserIsThisUser: Bool? = nil,
        notificationHold: MacLockState? = nil
    ) {
        self.sessionOnConsole = sessionOnConsole
        self.sessionScreenLocked = sessionScreenLocked
        self.notifyScreenLocked = notifyScreenLocked
        self.consoleUserIsThisUser = consoleUserIsThisUser
        self.notificationHold = notificationHold
    }

    /// At least one witness gave an answer.
    public var hasAnyAnswer: Bool {
        sessionOnConsole != nil || sessionScreenLocked != nil
            || notifyScreenLocked != nil || consoleUserIsThisUser != nil
    }
}

/// The gate's verdict on one message.
public enum LockGateDecision: Equatable, Sendable {
    case allow
    /// Drop the message; `reply` says what to tell the remote so it doesn't
    /// wait for an answer that won't come.
    case refuse(reply: LockRefusalReply)
}

/// What the Mac answers a refused request with.
public enum LockRefusalReply: Equatable, Sendable {
    /// Nothing: a fire-and-forget message.
    case none
    /// `deck.receipt(requestID, .refused(.macLocked))`.
    case receipt(requestID: String)
    /// `capture.screenshotError(requestID, …)`.
    case screenshotError(requestID: String)
    /// `capture.windowListResponse(requestID, [])`.
    case emptyWindowList(requestID: String)
    /// Send the app list once the Mac is unlocked.
    case appListAfterUnlock
}

public enum LockPolicy {
    /// How long every witness must say unlocked before the gate opens. A
    /// return to the console is often followed by macOS's own lock about a
    /// second later; nothing should slip out in between.
    public static let settle: TimeInterval = 2

    /// The copy for a refused screenshot.
    public static let lockedErrorMessage = "The Mac is locked."
    /// Why the mirror stopped when another user took the Mac's screen.
    public static let offConsoleMirrorMessage = "Another user is using this Mac, so the mirror stopped. It can start again once your account is back on the Mac's screen."

    /// One reading from the witnesses, or `nil` while none has answered.
    /// Off console beats locked beats unlocked; any witness saying so wins.
    public static func reading(_ w: LockWitnesses) -> MacLockState? {
        if w.sessionOnConsole == false || w.consoleUserIsThisUser == false || w.notificationHold == .offConsole {
            return .offConsole
        }
        if w.sessionScreenLocked == true || w.notifyScreenLocked == true || w.notificationHold == .screenLocked {
            return .screenLocked
        }
        return w.hasAnyAnswer ? .unlocked : nil
    }

    /// Decides one message from a remote against the effective lock state.
    public static func decide(_ message: ControlMessage, state: MacLockState) -> LockGateDecision {
        guard state.isLocked else { return .allow }
        let offConsole = state == .offConsole
        switch message {
        case .session, .pairing:
            // Liveness and approval keep working, or the remote would drop.
            return .allow

        case .input:
            // At the lock screen an approved remote may type the password
            // and click. Off console nothing it sends belongs here.
            return offConsole ? .refuse(reply: .none) : .allow

        case let .system(m):
            switch m {
            case .run(.locateCursor):
                return offConsole ? .refuse(reply: .none) : .allow
            case .run, .switchSpace:
                return .refuse(reply: .none)
            case .displayState, .lockState:
                return .allow // Mac → remote; the handler ignores it
            }

        case let .apps(m):
            switch m {
            case .requestAppList:
                return .refuse(reply: .appListAfterUnlock)
            case .launchApp, .appShortcut, .triggerContextAction:
                return .refuse(reply: .none)
            case .appListResponse, .runningAppsUpdate, .activeAppUpdate, .uiContextUpdate:
                return .allow // Mac → remote
            }

        case let .deck(m):
            switch m {
            case let .run(requestID, action):
                // Judged as the message it stands for, answered with a receipt.
                return decide(action.message, state: state) == .allow
                    ? .allow
                    : .refuse(reply: .receipt(requestID: requestID))
            case .requestAppMenuShortcuts:
                // Reading menus activates the app.
                return .refuse(reply: .none)
            case .appMenuShortcutsResponse, .receipt:
                return .allow
            }

        case let .mirror(m):
            switch m {
            case .start:
                // At the lock screen the display shows only the lock
                // screen. Off console, a capture of this session's display
                // would show its desktop behind the login window.
                return offConsole ? .refuse(reply: .none) : .allow
            case .stop, .frame, .displayList, .error:
                return .allow
            }

        case let .capture(m):
            switch m {
            case let .requestScreenshot(requestID, mode, _):
                // A window capture draws the window whatever covers it.
                if offConsole { return .refuse(reply: .screenshotError(requestID: requestID)) }
                if case .window = mode { return .refuse(reply: .screenshotError(requestID: requestID)) }
                return .allow
            case let .requestWindowList(requestID):
                return .refuse(reply: .emptyWindowList(requestID: requestID))
            case .screenshotData, .screenshotError, .windowListResponse:
                return .allow
            }

        case .sharing, .diagnostics:
            // Reserved domains with no cases yet. Whoever activates one
            // decides its rule here; until then nothing decodes.
            return .refuse(reply: .none)
        }
    }

    /// Mac → remote context (frontmost app, running apps, dialog buttons)
    /// is withheld while locked, and sent again at the unlock.
    public static func withholdsContext(_ state: MacLockState) -> Bool {
        state.isLocked
    }
}

/// Turns raw readings into the effective state: a lock or a switch away
/// acts at once, an unlock only after it has held for `LockPolicy.settle`.
public struct LockReader: Sendable, Equatable {
    /// What the gate uses. Before the first reading it is `.offConsole`,
    /// the most restrictive.
    public private(set) var effective: MacLockState = .offConsole
    public private(set) var hasFirstReading = false
    private var unlockedSince: Date?

    public init() {}

    /// Feeds one raw reading. `nil` (no witness answered) changes nothing.
    @discardableResult
    public mutating func update(_ raw: MacLockState?, at now: Date) -> MacLockState {
        guard let raw else { return effective }
        if !hasFirstReading {
            // The first complete reading is taken as it is, so a Mac that
            // starts unlocked waits for nothing.
            hasFirstReading = true
            effective = raw
            unlockedSince = raw == .unlocked ? now : nil
            return effective
        }
        if raw.isLocked {
            effective = raw
            unlockedSince = nil
            return effective
        }
        // Unlocked.
        if effective == .unlocked { return effective }
        let since = unlockedSince ?? now
        unlockedSince = since
        if now.timeIntervalSince(since) >= LockPolicy.settle {
            effective = .unlocked
        }
        return effective
    }

    /// When a pending unlock will have settled, so the Mac can look again
    /// then. `nil` when nothing is pending.
    public var settleDeadline: Date? {
        guard effective.isLocked, let unlockedSince else { return nil }
        return unlockedSince.addingTimeInterval(LockPolicy.settle)
    }
}
