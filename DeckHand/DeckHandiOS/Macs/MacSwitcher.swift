//
//  MacSwitcher.swift
//  DeckHandiOS – Macs
//
//  Several paired Macs, one focused at a time (UX-030, backlog M1/M2).
//
//  - The list: Core's `MacRoster` over discovery (the same peer query the
//    picker uses), the Pairing lane's `PairedMacsStore` and this device's
//    `MacMemoryBook`. My Macs, the iPad sidebar, the pill swipe, ⌘1–4 and
//    the three-finger switch all read it.
//  - Switching: Core's `MacSwitchMachine`. The new Mac is dialled (through
//    `RemoteConnect`, so VPN hosts stay paired-only and key-pinned) while
//    the old session keeps running; `ContentRootView` moves to the new
//    session when it connects and closes the old one after the slide. One
//    session model per connection, so one message loop.
//  - The free plan: `SubscriptionStore.admitMac` (Store lane) runs before
//    any dial, exactly as the picker does. A Mac that needs Pro opens the
//    paywall; buying Pro or switching the free Mac retries the switch.
//  - Per-Mac state: the deck page here; the surface and mirror settings in
//    `PerMacState.swift`. Saved when a Mac is left, restored when entered.
//  - Quick reconnect: at launch to the Mac used last (paired or own iCloud,
//    in reach), and after a drop, with backoff (`MacReconnectPolicy`).
//
//  No second connection is kept warm: a background Loom session costs radio
//  time and battery, and a switch to a paired Mac takes about a second.
//
//  No SwiftUI here: Linux type-checks it (`Scripts/linux-typecheck`).
//

import Foundation
import Loom
import LoomKit
import Observation

/// Keys for the Multi-Mac settings (`DeckHandSettings`, `// MARK: Multi-Mac`).
enum MultiMacSettingsKey {
    /// Three-finger sideways swipes switch Macs (2+ Macs in reach).
    static let swipeBetweenMacs = "settings.swipeBetweenMacs"
    /// Reconnect to the last Mac at launch and after a drop.
    static let reconnectAutomatically = "settings.reconnectAutomatically"
    /// `MacMemoryBook` JSON.
    static let macMemory = "settings.macMemory"
    /// Onboarding's key, read so launch reconnect waits for it.
    static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
}

@MainActor
@Observable
final class MacSwitcher {
    static let shared = MacSwitcher()

    /// A session to move to, handed to `ContentRootView`.
    struct Adoption {
        let handle: LoomConnectionHandle
        let name: String
        let direction: MacSwitchDirection
        /// The session switched away from: close it once the slide ends.
        let release: LoomConnectionHandle?
    }

    private(set) var machine = MacSwitchMachine()
    private(set) var book: MacMemoryBook
    private(set) var peers: [LoomPeerSnapshot] = []
    /// Bumped when pairing changes, so the list re-reads it.
    private var pairingRevision = 0
    /// A line for the root view's toast ("Couldn't reach Laptop").
    var notice: String?
    /// Set while a dropped Mac is being redialled.
    private(set) var reconnectingDeviceID: UUID?

    /// "iPhone" or "iPad", for "Please update Pixel Hand on your …".
    @ObservationIgnored var thisDeviceKind = "iPhone"
    /// Called on the main actor to move the UI to a new session.
    @ObservationIgnored var onAdopt: (@MainActor (Adoption) -> Void)?
    @ObservationIgnored private var context: LoomContext?
    @ObservationIgnored private var handle: LoomConnectionHandle?
    @ObservationIgnored private var triedLaunchReconnect = false
    @ObservationIgnored private var redialTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        book = MacMemoryBook(storage: defaults.data(forKey: MultiMacSettingsKey.macMemory))
    }

    // MARK: - Settings

    var swipeBetweenMacs: Bool {
        defaults.object(forKey: MultiMacSettingsKey.swipeBetweenMacs) as? Bool ?? true
    }

    var reconnectAutomatically: Bool {
        defaults.object(forKey: MultiMacSettingsKey.reconnectAutomatically) as? Bool ?? true
    }

    // MARK: - The list

    var focusedDeviceID: UUID? { machine.focusedDeviceID }

    var listings: [MacListing] {
        _ = pairingRevision
        var listings = MacRoster.listings(
            discovered: peers.map {
                MacCandidate(deviceID: $0.deviceID, name: $0.name, isReachable: true, isNearby: $0.isNearby, isOwnICloud: $0.isSameICloudDevice)
            },
            paired: PairedMacsStore.shared.macs.filter { $0.kind == .mac }.map {
                MacPairing(deviceID: $0.deviceID, name: $0.name, pairedAt: $0.pairedAt)
            },
            memory: book,
            activeDeviceID: machine.focusedDeviceID,
            connectingDeviceID: machine.dialingDeviceID ?? reconnectingDeviceID
        )
        // The live link and lock state for the focused Mac come with its
        // glance; nothing else to merge.
        if listings.isEmpty, let focused = machine.focusedDeviceID {
            listings = [MacListing(deviceID: focused, name: book.memory(for: focused)?.name ?? "Mac", slot: 1, isActive: true, isReachable: true)]
        }
        return listings
    }

    func memory(for deviceID: UUID) -> MacMemory? {
        book.memory(for: deviceID)
    }

    /// The focused Mac's memory (surface, mirror).
    var focusedMemory: MacMemory? {
        machine.focusedDeviceID.flatMap { book.memory(for: $0) }
    }

    /// Whether the three-finger sideways swipe switches Macs now.
    var swipeSwitchesMacs: Bool {
        MacRoster.swipeSwitchesMacs(settingOn: swipeBetweenMacs, listings: listings)
    }

    // MARK: - Inputs from the root view

    func start(context: LoomContext) {
        self.context = context
    }

    /// Discovery changed. Also the moment to reconnect at launch.
    func update(peers: [LoomPeerSnapshot]) {
        self.peers = peers
        pairingRevision += 1
        reconnectAtLaunchIfNeeded()
    }

    /// The picker connected (a tap or a QR code): that Mac is now focused.
    func adoptFromPicker(_ handle: LoomConnectionHandle, name: String) {
        let deviceID = handle.peer.deviceID
        redialTask?.cancel()
        reconnectingDeviceID = nil
        triedLaunchReconnect = true
        machine.adopted(deviceID)
        self.handle = handle
        entered(deviceID, name: name)
    }

    /// The person disconnected (Disconnect, the approval card's button).
    func endedByUser() {
        redialTask?.cancel()
        reconnectingDeviceID = nil
        if let focused = machine.focusedDeviceID {
            left(focused)
            machine.ended(focused)
        }
        handle = nil
        book.clearLastActive()
        save()
    }

    /// The focused session's connection dropped. `isVerdict` when the Mac
    /// said no (denied, revoked, forgotten): never redialled.
    func connectionDropped(_ handle: LoomConnectionHandle, isVerdict: Bool) {
        guard handle.id == self.handle?.id else { return }
        let deviceID = handle.peer.deviceID
        // The heartbeat and the connection can both report the same drop.
        guard reconnectingDeviceID != deviceID else { return }
        left(deviceID)
        scheduleRedial(deviceID, attempt: 0, isVerdict: isVerdict)
    }

    /// The focused session's glance changed (front app, lock, link).
    func noteGlance(_ glance: MacGlance, for deviceID: UUID) {
        guard deviceID == machine.focusedDeviceID else { return }
        guard !glance.sameContent(as: book.memory(for: deviceID)?.glance) else { return }
        book.update(deviceID) { $0.glance = glance }
        save()
    }

    /// The shell's surface on the focused Mac.
    func noteSurface(_ surface: String) {
        guard let focused = machine.focusedDeviceID, book.memory(for: focused)?.surface != surface else { return }
        book.update(focused) { $0.surface = surface }
        save()
    }

    /// The mirror settings on the focused Mac.
    func noteMirror(_ mirror: MacMirrorMemory) {
        guard let focused = machine.focusedDeviceID, book.memory(for: focused)?.mirror != mirror else { return }
        book.update(focused) { $0.mirror = mirror }
        save()
    }

    /// Pairing changed (paired, forgotten): re-read the list.
    func pairingChanged() {
        pairingRevision += 1
    }

    /// Removes a Mac from the list (My Macs › Forget). Pairing itself is
    /// forgotten in Settings › Paired Macs.
    func forget(_ deviceID: UUID) {
        guard deviceID != machine.focusedDeviceID else { return }
        book.forget(deviceID)
        save()
    }

    // MARK: - Switching

    /// Makes `deviceID` the focused Mac.
    func request(_ deviceID: UUID) {
        let listing = listings.first { $0.deviceID == deviceID }
        let peer = peers.first { $0.deviceID == deviceID }
        let name = peer?.name ?? listing?.name ?? "that Mac"

        // The focused Mac, or the one dialling: the machine settles it
        // (going back cancels a dial) without the free-plan check.
        if deviceID == machine.focusedDeviceID || deviceID == machine.dialingDeviceID {
            _ = machine.request(deviceID, isReachable: true, admission: .allowed)
            return
        }
        guard let peer else {
            show("\(name) isn’t in reach. Open Pixel Hand on it, on the same Wi-Fi or a cable.")
            return
        }
        if let message = PeerCompatibility(advertisement: peer.advertisement).updateMessage(thisDevice: thisDeviceKind, peer: "Mac") {
            show(message)
            return
        }
        // Store lane's one-Mac rule, unchanged: without Pro another Mac
        // opens the paywall, which retries this switch.
        let admitted = SubscriptionStore.shared.admitMac(deviceID: deviceID, name: peer.name) { [weak self] in
            self?.request(deviceID)
        }
        let outcome = machine.request(deviceID, isReachable: true, admission: admitted ? .allowed : .needsPro)
        guard case let .dial(target, attempt) = outcome else { return }
        dial(peer, target: target, attempt: attempt)
    }

    /// ⌘1–⌘4.
    func switchToSlot(_ slot: Int) {
        guard let mac = MacRoster.mac(inSlot: slot, of: listings) else { return }
        request(mac.deviceID)
    }

    /// Next (1) or previous (-1) Mac in reach: the pill swipe and ⌘`.
    /// Returns `false` when there is no other Mac to go to.
    @discardableResult
    func step(by step: Int) -> Bool {
        guard let next = MacRoster.neighbor(of: machine.focusedDeviceID, step: step, in: listings),
              next.deviceID != machine.focusedDeviceID
        else { return false }
        request(next.deviceID)
        return true
    }

    /// The trackpad's three-finger swipe. Returns `true` when it switched
    /// Macs, so the trackpad doesn't also send the Spaces swipe.
    func handleTrackpadGesture(_ gesture: MultiFingerGesture) -> Bool {
        guard swipeSwitchesMacs else { return false }
        switch gesture {
        // Fingers to the left bring in what is on the right, as Spaces do.
        case .swipe(.left): return step(by: 1)
        case .swipe(.right): return step(by: -1)
        default: return false
        }
    }

    // MARK: - Internals

    private func dial(_ peer: LoomPeerSnapshot, target: UUID, attempt: Int) {
        guard let context else {
            _ = machine.dialFailed(target, attempt: attempt)
            return
        }
        DeckHandLog.connection.info("📡 Switching to \(peer.name, privacy: .public) id=\(peer.deviceID, privacy: .public)")
        Task { @MainActor in
            do {
                let newHandle = try await RemoteConnect.connect(peer, using: context)
                switch machine.dialSucceeded(target, attempt: attempt) {
                case let .adopt(deviceID, release):
                    adopt(newHandle, deviceID: deviceID, name: peer.name, releasing: release)
                case .discard:
                    DeckHandLog.connection.info("📡 Late connection to \(peer.name, privacy: .public) closed (superseded)")
                    await newHandle.disconnect()
                }
            } catch {
                DeckHandLog.connection.error("📡 Switch to \(peer.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                if machine.dialFailed(target, attempt: attempt) {
                    if reconnectingDeviceID == target {
                        scheduleRedial(target, attempt: redialAttempt + 1, isVerdict: false)
                    } else {
                        show("Couldn’t connect to \(peer.name): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func adopt(_ newHandle: LoomConnectionHandle, deviceID: UUID, name: String, releasing release: UUID?) {
        let previous = release
        if let previous { left(previous) }
        let direction = MacRoster.direction(from: previous, to: deviceID, in: listings)
        let old = previous == nil ? nil : handle
        handle = newHandle
        redialTask?.cancel()
        reconnectingDeviceID = nil
        redialAttempt = 0
        entered(deviceID, name: name)
        onAdopt?(Adoption(handle: newHandle, name: name, direction: direction, release: old))
    }

    /// Saves what is worth keeping about the Mac being left.
    private func left(_ deviceID: UUID) {
        let page = DeckSurfaceModel.shared.shownPageID
        book.update(deviceID) { $0.deckPageID = page }
        save()
    }

    /// Records the Mac being entered and restores its deck page.
    private func entered(_ deviceID: UUID, name: String) {
        book.activated(deviceID: deviceID, name: name, at: Date())
        save()
        if let page = book.memory(for: deviceID)?.deckPageID,
           DeckSurfaceModel.shared.document.pages.contains(where: { $0.id == page }) {
            DeckSurfaceModel.shared.select(pageID: page)
        }
    }

    @ObservationIgnored private var redialAttempt = 0

    private func scheduleRedial(_ deviceID: UUID, attempt: Int, isVerdict: Bool) {
        redialTask?.cancel()
        guard let delay = MacReconnectPolicy.redialDelay(
            isEnabled: reconnectAutomatically, attempt: attempt, endedByVerdict: isVerdict, endedByUser: false
        ) else {
            reconnectingDeviceID = nil
            return
        }
        redialAttempt = attempt
        reconnectingDeviceID = deviceID
        redialTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.reconnectingDeviceID == deviceID else { return }
            // The dropped Mac stops being focused so the redial is a fresh
            // connect; the root view keeps its "not answering" card up.
            self.machine.ended(deviceID)
            guard let peer = self.peers.first(where: { $0.deviceID == deviceID }) else {
                self.scheduleRedial(deviceID, attempt: attempt + 1, isVerdict: false)
                return
            }
            let outcome = self.machine.request(deviceID, isReachable: true, admission: .allowed)
            if case let .dial(target, dialAttempt) = outcome {
                self.dial(peer, target: target, attempt: dialAttempt)
            }
        }
    }

    private func reconnectAtLaunchIfNeeded() {
        guard machine.focusedDeviceID == nil, machine.dialingDeviceID == nil, handle == nil else { return }
        guard let target = MacReconnectPolicy.launchTarget(
            isEnabled: reconnectAutomatically,
            hasCompletedOnboarding: defaults.bool(forKey: MultiMacSettingsKey.hasCompletedOnboarding),
            alreadyTried: triedLaunchReconnect,
            hasSession: handle != nil,
            lastActiveDeviceID: book.lastActiveDeviceID,
            listings: listings,
            isLockedByFreePlan: { SubscriptionStore.shared.isLockedMac(deviceID: $0) }
        ) else { return }
        triedLaunchReconnect = true
        DeckHandLog.connection.info("📡 Reconnecting to the last Mac at launch")
        request(target)
    }

    private func show(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled, self.notice == message else { return }
            self.notice = nil
        }
    }

    private func save() {
        defaults.set(book.encoded(), forKey: MultiMacSettingsKey.macMemory)
    }
}
