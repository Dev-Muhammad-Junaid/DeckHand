//
//  DeliveryDots.swift
//  DeckHandiOS
//
//  Five dots under a chip that answer "did the Mac get that?". They light
//  left to right as the command goes out, then turn mint when the Mac
//  confirms it or red if it couldn't act or never answered. Nothing shows
//  at rest.
//

import SwiftUI

enum DeliveryState: Equatable {
    case idle
    case sending
    /// Sent to a host that doesn't confirm; the dots just fade.
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

    /// How long the result stays before the dots fade.
    var hold: Duration {
        self == .failed ? .milliseconds(1400) : .milliseconds(900)
    }
}

struct DeliveryDots: View {
    let state: DeliveryState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let count = 5
    /// In flight: the accent on light chips, the icon's ray color on dark.
    private static let sendingColor = Color(light: "3A4CF2", dark: "9FF6FF")

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                    .fill(color)
                    .frame(width: 2.5, height: 2.5)
                    .shadow(color: color.opacity(state == .idle ? 0 : 0.7), radius: 2)
                    .opacity(state == .idle ? 0 : 1)
                    .animation(animation(for: index), value: state)
            }
        }
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch state {
        case .idle, .sending, .sent: Self.sendingColor
        case .confirmed: DeckHandTheme.success
        case .failed: DeckHandTheme.danger
        }
    }

    private func animation(for index: Int) -> Animation {
        // Light up left to right on the way out; settle together on the answer.
        guard state == .sending, !reduceMotion else { return .easeOut(duration: 0.2) }
        return .easeOut(duration: 0.12).delay(Double(index) * 0.045)
    }

    /// Spoken when a confirmed command doesn't arrive, so VoiceOver users
    /// learn what the red dots show.
    static func announceFailure() {
        let message: String = "The Mac didn’t confirm that command"
        AccessibilityNotification.Announcement(message).post()
    }
}

/// Runs one confirmed send for a chip: lights the dots, waits for the
/// answer, holds it briefly, then clears. A newer tap takes over the dots.
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

    /// One send through a chip's tracker: lights the dots, waits for the
    /// answer, holds it, then clears unless a newer tap took over.
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

extension View {
    /// The delivery dots along the bottom edge of a chip.
    func deliveryDots(_ state: DeliveryState) -> some View {
        overlay(alignment: .bottom) {
            DeliveryDots(state: state)
                .padding(.bottom, 1.5)
        }
    }
}

