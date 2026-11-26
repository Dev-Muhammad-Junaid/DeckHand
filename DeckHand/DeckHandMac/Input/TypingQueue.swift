//
//  TypingQueue.swift
//  DeckHandMac
//
//  Types `input.typeText` and posts key chords in the order they arrived,
//  paced so the frontmost app keeps up. A chord sent right after text
//  (Return after a sentence, ⌘A after typing) waits for the text before
//  it, instead of overtaking it.
//
//  Text is planned with Core's `TypingPlanner` against the current layout
//  (`KeyboardLayoutMap`): characters on the layout are pressed as keys,
//  the rest go as Unicode strings. At most `TypingPolicy.maxQueuedBytes`
//  wait at once; more is dropped with a log line.
//

import Foundation

@MainActor
final class TypingQueue {
    static let shared = TypingQueue()

    private enum Item {
        case text(String)
        case chord([String])
    }

    private var items: [Item] = []
    private var queuedBytes = 0
    private var drainTask: Task<Void, Never>?
    /// Bumped by `cancelAll`, so a cancelled drain that finishes late
    /// doesn't clear the task of the drain that replaced it.
    private var generation = 0
    private var lastDropLogAt: Date = .distantPast
    private let injector = InputInjector.shared

    private init() {}

    /// Whether text or chords are waiting or being typed.
    var isBusy: Bool { drainTask != nil }

    /// Queues `text` (already cleaned by `RemoteInputValidation`).
    func type(_ text: String) {
        let bytes = text.utf8.count
        guard queuedBytes + bytes <= TypingPolicy.maxQueuedBytes else {
            let now = Date()
            if now.timeIntervalSince(lastDropLogAt) > 5 {
                lastDropLogAt = now
                DeckHandLog.input.error("Typing: dropped \(bytes, privacy: .public) B of text; \(self.queuedBytes, privacy: .public) B still waiting to be typed")
            }
            return
        }
        queuedBytes += bytes
        items.append(.text(text))
        startDraining()
    }

    /// Posts `keys` now, or after the text queued before it.
    func shortcut(_ keys: [String]) {
        guard isBusy else {
            injector.sendShortcut(keys: keys)
            return
        }
        items.append(.chord(keys))
    }

    /// Returns once everything queued so far (and anything queued while
    /// waiting) has been typed or dropped: a deck sequence's typed step
    /// (OT-8) finishes before the step after it, even one that doesn't go
    /// through this queue (an app shortcut, a launch).
    func idle() async {
        while let task = drainTask {
            await task.value
        }
    }

    /// Drops whatever hasn't been typed yet (the remote left).
    func cancelAll() {
        items.removeAll()
        queuedBytes = 0
        generation += 1
        drainTask?.cancel()
        drainTask = nil
    }

    private func startDraining() {
        guard drainTask == nil else { return }
        let generation = self.generation
        drainTask = Task { [weak self] in
            await self?.drain(generation: generation)
        }
    }

    private func drain(generation: Int) async {
        defer {
            if self.generation == generation { drainTask = nil }
        }
        while !items.isEmpty {
            if Task.isCancelled { return }
            let item = items.removeFirst()
            switch item {
            case let .chord(keys):
                injector.sendShortcut(keys: keys)
                try? await Task.sleep(for: TypingPolicy.interEventDelay)
            case let .text(text):
                queuedBytes = max(0, queuedBytes - text.utf8.count)
                KeyboardLayoutMap.shared.refreshIfNeeded()
                let map = KeyboardLayoutMap.shared
                let steps = TypingPlanner.plan(text) { map.stroke(for: $0) }
                for step in steps {
                    if Task.isCancelled { return }
                    switch step {
                    case let .key(stroke): injector.typeKey(stroke)
                    case let .named(name): injector.typeNamedKey(name)
                    case let .unicode(run): injector.typeUnicode(run)
                    }
                    try? await Task.sleep(for: TypingPolicy.interEventDelay)
                }
            }
        }
    }
}
