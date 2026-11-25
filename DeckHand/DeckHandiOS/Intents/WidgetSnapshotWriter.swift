//
//  WidgetSnapshotWriter.swift
//  DeckHandiOS
//
//  Keeps the App Group's `WidgetDeckSnapshot` current (D6): rewritten when
//  the deck changes (`DeckStore.document`, observed, so `DeckStore` needs
//  no edit), when a Mac connects (`recordMac`), when its front app, lock
//  state or connection changes (`updateGlance`) and when the plan changes
//  (`SubscriptionStore.entitlement`). Each write reloads the widgets and,
//  on iOS 18, the Control Center controls, and refreshes the App Shortcuts
//  parameters so Siri knows the deck keys' names.
//

import Combine
import Foundation
import PixelHandCore
import WidgetKit

@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    private var cancellables: Set<AnyCancellable> = []
    private var macs: [RecentMac] = []
    private var lastWritten: WidgetDeckSnapshot?
    private var lastIsPro: Bool?

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }
        macs = PixelHandAppGroup.readSnapshot().macs
        DeckStore.shared.$document
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.write() }
            .store(in: &cancellables)
        observeEntitlement()
        write()
    }

    func recordMac(_ mac: RecentMac) {
        glanceWrite?.cancel()
        macs = RecentMac.recording(mac, in: macs)
        write()
    }

    /// The pending write for a front-app change, coalesced so switching
    /// apps quickly reloads the widgets once.
    private var glanceWrite: Task<Void, Never>?

    /// Records what `macID` is doing for the widget strip (VQ-072). Going
    /// offline writes at once; front-app and lock changes settle for two
    /// seconds first.
    func updateGlance(macID: String, frontApp: String?, glance: RecentMac.Glance) {
        guard let index = macs.firstIndex(where: { $0.id == macID }) else { return }
        let updated = macs[index].with(frontApp: frontApp, glance: glance)
        guard updated != macs[index] else { return }
        macs[index] = updated
        glanceWrite?.cancel()
        if glance == .offline {
            write()
            return
        }
        glanceWrite = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    /// Writes the snapshot when what a widget shows changed. The timestamp
    /// alone never triggers a reload.
    func write() {
        let isPro = SubscriptionStore.shared.entitlement.isPro
        let snapshot = WidgetDeckSnapshot.make(from: DeckStore.shared.document, macs: macs, isPro: isPro, now: Date())
        if var previous = lastWritten {
            previous.generatedAt = snapshot.generatedAt
            if previous == snapshot { return }
        }
        lastWritten = snapshot
        PixelHandAppGroup.writeSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
        PixelHandShortcuts.updateAppShortcutParameters()
    }

    /// `SubscriptionStore` is `@Observable`: re-arm after every change.
    private func observeEntitlement() {
        withObservationTracking {
            _ = SubscriptionStore.shared.entitlement
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isPro = SubscriptionStore.shared.entitlement.isPro
                if isPro != self.lastIsPro {
                    self.lastIsPro = isPro
                    self.write()
                }
                self.observeEntitlement()
            }
        }
    }
}
