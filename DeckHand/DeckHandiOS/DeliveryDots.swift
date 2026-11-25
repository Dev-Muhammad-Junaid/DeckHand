//
//  DeliveryDots.swift
//  DeckHandiOS
//
//  The answer to "did the Mac get that?" for a chip or key. Under the
//  owner's glyph rule (OR-02) nothing shows while it sends or when it
//  lands: the press state and a haptic are enough. Only a refusal shows,
//  as a danger outline (`deliveryReceipt` in DesignSystem/DeliveryStrip)
//  and a VoiceOver announcement.
//

import SwiftUI

enum DeliveryState: Equatable {
    case idle
    case sending
    /// Sent to a host that doesn't confirm.
    case sent
    case confirmed
    case failed

    init(_ delivery: CommandDelivery) {
        switch delivery {
        case .sent: self = .sent
        case .confirmed: self = .confirmed
        case .failed, .timedOut: self = .failed
        }
    }

    /// How long the result stays before it clears.
    var hold: Duration {
        self == .failed ? .milliseconds(1400) : .milliseconds(900)
    }
}

enum DeliveryDots {
    /// Spoken when a confirmed command doesn't arrive, so VoiceOver users
    /// learn what the danger outline shows.
    @MainActor
    static func announceFailure() {
        let message: String = "The Mac didn’t confirm that command"
        AccessibilityNotification.Announcement(message).post()
    }
}

/// Runs one confirmed send for a chip: waits for the answer, holds a
/// refusal briefly, then clears. A newer tap takes over.
struct DeliveryTracker {
    private(set) var state: DeliveryState = .idle
    private var attempt = 0

    /// Starts a send and returns its attempt number.
    mutating func begin() -> Int {
        attempt += 1
        state = .sending
        return attempt
    }

    /// Records the answer if no newer tap has started. Returns whether it did.
    mutating func finish(_ delivery: CommandDelivery, attempt: Int) -> Bool {
        guard attempt == self.attempt else { return false }
        state = DeliveryState(delivery)
        return true
    }

    mutating func clear(attempt: Int) {
        guard attempt == self.attempt else { return }
        state = .idle
    }

    /// One send through a chip's tracker: waits for the answer, holds it,
    /// then clears unless a newer tap took over.
    @MainActor
    static func run(_ tracker: Binding<DeliveryTracker>, send: @MainActor () async -> CommandDelivery) async {
        let attempt = tracker.wrappedValue.begin()
        let result = await send()
        guard tracker.wrappedValue.finish(result, attempt: attempt) else { return }
        if tracker.wrappedValue.state == .failed {
            DeliveryDots.announceFailure()
        }
        try? await Task.sleep(for: tracker.wrappedValue.state.hold)
        tracker.wrappedValue.clear(attempt: attempt)
    }
}
