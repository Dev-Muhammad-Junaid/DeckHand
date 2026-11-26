//
//  MacSwitchMachine.swift
//  PixelHandCore – Multi-Mac
//
//  The focused-Mac switch (backlog M1): one Mac is active at a time, and a
//  switch dials the new Mac **while the old session keeps running**. Only
//  when the new connection is up does the remote move to it and release
//  the old one, so a failed or refused dial leaves the person where they
//  were. A newer request supersedes a dial in flight; the late connection
//  is closed.
//
//  The free plan's one-Mac rule (`FreeMacPolicy`, Store lane) runs before
//  any dial: a Mac that needs Pro opens the paywall and nothing is dialled.
//
//      idle ──request──▶ dialing(target, from: nil) ──ok──▶ active(target)
//      active(A) ──request(B)──▶ dialing(B, from: A) ──ok──▶ active(B), release A
//                                              └──fail──▶ active(A)
//

import Foundation

public struct MacSwitchMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case active(UUID)
        /// Dialling `target`; `from` is still connected (and in use) until
        /// the dial ends.
        case dialing(target: UUID, from: UUID?, attempt: Int)
    }

    /// The one-Mac rule's answer for the target, from `FreeMacPolicy`.
    public enum Admission: Equatable, Sendable {
        case allowed
        case needsPro

        public init(_ admission: FreeMacPolicy.Admission) {
            switch admission {
            case .allowed: self = .allowed
            case .needsPro: self = .needsPro
            }
        }
    }

    public enum RequestOutcome: Equatable, Sendable {
        /// Dial `target`; report back with `attempt`.
        case dial(target: UUID, attempt: Int)
        /// Already the focused Mac (or already being dialled).
        case alreadyActive
        /// The free plan allows one Mac: show the paywall, dial nothing.
        case paywall
        /// Not in reach now.
        case unreachable
    }

    public enum DialOutcome: Equatable, Sendable {
        /// Show the new Mac; close `release` (the Mac switched away from).
        case adopt(UUID, release: UUID?)
        /// A newer request replaced this dial: close the new connection.
        case discard
    }

    public private(set) var phase: Phase = .idle
    private var attempts = 0

    public init() {}

    /// The Mac on screen: the active one, or the one a dial is leaving.
    public var focusedDeviceID: UUID? {
        switch phase {
        case .idle: nil
        case let .active(id): id
        case let .dialing(_, from, _): from
        }
    }

    public var dialingDeviceID: UUID? {
        if case let .dialing(target, _, _) = phase { return target }
        return nil
    }

    /// Asks to make `target` the focused Mac.
    public mutating func request(_ target: UUID, isReachable: Bool, admission: Admission) -> RequestOutcome {
        if dialingDeviceID == target { return .alreadyActive }
        if focusedDeviceID == target {
            // Back to the Mac on screen while another dials: drop that dial
            // (its late connection is discarded).
            if dialingDeviceID != nil {
                attempts += 1
                phase = .active(target)
            }
            return .alreadyActive
        }
        guard admission == .allowed else { return .paywall }
        guard isReachable else { return .unreachable }
        attempts += 1
        phase = .dialing(target: target, from: focusedDeviceID, attempt: attempts)
        return .dial(target: target, attempt: attempts)
    }

    /// The dial for `target` connected.
    public mutating func dialSucceeded(_ target: UUID, attempt: Int) -> DialOutcome {
        guard case let .dialing(current, from, currentAttempt) = phase,
              current == target, currentAttempt == attempt
        else { return .discard }
        phase = .active(target)
        return .adopt(target, release: from == target ? nil : from)
    }

    /// The dial for `target` failed. Returns whether it was the current one
    /// (so the remote says why); the old Mac stays focused.
    @discardableResult
    public mutating func dialFailed(_ target: UUID, attempt: Int) -> Bool {
        guard case let .dialing(current, from, currentAttempt) = phase,
              current == target, currentAttempt == attempt
        else { return false }
        phase = from.map { .active($0) } ?? .idle
        return true
    }

    /// The person cancelled the dial in flight ("Connecting to Studio…" ›
    /// Cancel). The Mac it was leaving stays focused; a late connection is
    /// discarded. Returns whether there was a dial to cancel.
    @discardableResult
    public mutating func cancelDial() -> Bool {
        guard case let .dialing(_, from, _) = phase else { return false }
        attempts += 1
        phase = from.map { .active($0) } ?? .idle
        return true
    }

    /// A connection made outside a switch (the picker) became the focused
    /// Mac. Supersedes any dial in flight.
    public mutating func adopted(_ deviceID: UUID) {
        attempts += 1
        phase = .active(deviceID)
    }

    /// The focused Mac's session ended (disconnect, drop, Forget). A dial
    /// in flight carries on, now from no Mac.
    public mutating func ended(_ deviceID: UUID) {
        switch phase {
        case .idle:
            break
        case let .active(id):
            if id == deviceID { phase = .idle }
        case let .dialing(target, from, attempt):
            if from == deviceID { phase = .dialing(target: target, from: nil, attempt: attempt) }
        }
    }
}

/// When the remote reconnects on its own ("quick reconnect", backlog M1).
public enum MacReconnectPolicy {
    /// Waits before each redial after a connection drops.
    public static let redialDelays: [TimeInterval] = [1, 2, 4, 8]

    /// The Mac to dial at launch, or `nil`: the Mac used last, when it is
    /// in reach and connects without a prompt (paired, or the person's own
    /// iCloud Mac), and the free plan allows it. With no Mac used last (a
    /// fresh install that paired during onboarding, VQ-058), the one Mac in
    /// reach that connects without a prompt; none when there are several,
    /// so the person picks. Never twice per launch, never before
    /// onboarding, never over a running session.
    ///
    /// Never before the network can dial (`isNetworkReady`): since Loom
    /// browses before its start returns, the paired Mac is listed before
    /// the remote can connect to it. Build 23 (VQ-058) spent its one try
    /// on that dial, which failed silently, and then waited for a tap.
    public static func launchTarget(
        isEnabled: Bool,
        hasCompletedOnboarding: Bool,
        alreadyTried: Bool,
        hasSession: Bool,
        isNetworkReady: Bool = true,
        lastActiveDeviceID: UUID?,
        listings: [MacListing],
        isLockedByFreePlan: (UUID) -> Bool
    ) -> UUID? {
        guard isEnabled, hasCompletedOnboarding, isNetworkReady, !alreadyTried, !hasSession else { return nil }
        func connectsWithoutPrompt(_ mac: MacListing) -> Bool {
            mac.isReachable && (mac.isPaired || mac.isOwnICloud) && !isLockedByFreePlan(mac.deviceID)
        }
        guard let lastActiveDeviceID else {
            let candidates = listings.filter(connectsWithoutPrompt)
            return candidates.count == 1 ? candidates[0].deviceID : nil
        }
        guard let mac = listings.first(where: { $0.deviceID == lastActiveDeviceID }),
              connectsWithoutPrompt(mac)
        else { return nil }
        return lastActiveDeviceID
    }

    /// The Mac the launch reconnect is waiting to dial while the network
    /// isn't ready yet, or `nil` (build 24, VQ-101). After a cold boot that
    /// wait took 7–15 s and the picker showed a bare "Paired · Nearby"; the
    /// remote now says "Connecting to <Mac>…" with Cancel meanwhile.
    public static func pendingLaunchTarget(
        isEnabled: Bool,
        hasCompletedOnboarding: Bool,
        alreadyTried: Bool,
        hasSession: Bool,
        isNetworkReady: Bool,
        lastActiveDeviceID: UUID?,
        listings: [MacListing],
        isLockedByFreePlan: (UUID) -> Bool
    ) -> UUID? {
        guard !isNetworkReady else { return nil }
        return launchTarget(
            isEnabled: isEnabled,
            hasCompletedOnboarding: hasCompletedOnboarding,
            alreadyTried: alreadyTried,
            hasSession: hasSession,
            isNetworkReady: true,
            lastActiveDeviceID: lastActiveDeviceID,
            listings: listings,
            isLockedByFreePlan: isLockedByFreePlan
        )
    }

    /// How long "Connecting to <Mac>…" stays up while the network still
    /// isn't ready; after that the picker waits for a tap as before.
    public static let launchWaitLimit: TimeInterval = 30

    /// The toast while the launch reconnect waits or dials.
    public static func connectingLine(macName: String) -> String {
        "Connecting to \(macName)…"
    }

    /// Whether a dial that failed is tried again on the redial schedule
    /// (build 26, VQ-107). A redial of a dropped Mac always was. The launch
    /// reconnect wasn't: one failed dial (a slow or busy device, a Mac
    /// still waking) showed "Couldn't reach …" and left the picker waiting
    /// for a tap, so at AX3 the walks never reached the shell. It now
    /// redials like a drop. A dial the person started reports its error
    /// and stops: they're looking at the picker and can tap again.
    public static func redialsFailedDial(isEnabled: Bool, isRedial: Bool, isLaunchReconnect: Bool) -> Bool {
        isEnabled && (isRedial || isLaunchReconnect)
    }

    /// The wait before redial number `attempt` (0-based) after the focused
    /// Mac dropped, or `nil` to stop. Approval verdicts (denied, revoked,
    /// forgotten) and the person's own Disconnect never redial.
    public static func redialDelay(isEnabled: Bool, attempt: Int, endedByVerdict: Bool, endedByUser: Bool) -> TimeInterval? {
        guard isEnabled, !endedByVerdict, !endedByUser, attempt >= 0, attempt < redialDelays.count else { return nil }
        return redialDelays[attempt]
    }
}
