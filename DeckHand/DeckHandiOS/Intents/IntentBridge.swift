//
//  IntentBridge.swift
//  DeckHandiOS
//
//  Where App Intents, widget buttons and Control Center controls meet the
//  live session (D6). `IntentDispatch` (shared with the widget extension)
//  hands every command here when it runs in the app's process:
//
//  1. gate it on the plan (`RemoteCommand.feature`, `SubscriptionStore`);
//  2. with a Mac connected, run it on that session: deck keys, system
//     actions and media keys as a tracked `deck.run`, text through the
//     keyboard path, a screenshot through `CaptureCoordinator`, the mirror
//     through `toggleMirror`;
//  3. with no Mac connected, queue it in the App Group
//     (`PendingCommandQueue`, 90 s) and run it when a session attaches.
//
//  `ControlView` attaches its session with `.intentBridge(…)`
//  (`IntentBridgeModifier`); nothing here opens or chooses connections.
//

import Foundation
import PixelHandCore
import SwiftUI

@MainActor
@Observable
final class IntentBridge {
    static let shared = IntentBridge()

    /// A surface an intent asked the shell to show ("Open Trackpad",
    /// "Start Mirror"); the shell reads it with `.intentSurfaceRequests`.
    private(set) var surfaceRequest: SurfaceRequest?

    struct SurfaceRequest: Equatable {
        let surface: ControlSurface
        /// What was asked for, for the arrangement on preset windows
        /// (VQ-079, `RemoteSurface.arrangement(from:)`).
        let requested: RemoteSurface
        let id = UUID()
    }

    @ObservationIgnored private weak var session: ControlSessionModel?
    @ObservationIgnored private weak var settings: DeckHandSettings?
    @ObservationIgnored private var mac: RecentMac?
    @ObservationIgnored private var hasStarted = false

    private init() {}

    /// Registers the handler and starts the widget snapshot writer. Called
    /// once at launch.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        IntentDispatch.handler = { [weak self] pending in
            guard let self else { return .waitingForMac }
            return await self.handle(pending)
        }
        WidgetSnapshotWriter.shared.start()
        // Commands a widget or control queued before the app was running
        // that don't need a Mac (opening a surface) run now; the rest wait.
        for pending in PixelHandAppGroup.drainPending(forMac: nil) {
            Task { _ = await handle(pending) }
        }
    }

    // MARK: - Session

    /// The session that intents now run on. Runs anything queued for it
    /// once its sender is up.
    func attach(session: ControlSessionModel, settings: DeckHandSettings, macID: String, macName: String) {
        self.session = session
        self.settings = settings
        let mac = RecentMac(id: macID, name: macName, lastConnected: Date())
        self.mac = mac
        WidgetSnapshotWriter.shared.recordMac(mac)
        observeGlance(session, macID: macID)
        Task { [weak self] in
            guard let self, await self.waitForSender(session) else { return }
            guard self.session === session else { return }
            for pending in PixelHandAppGroup.drainPending(forMac: macID) {
                let outcome = await self.handle(pending)
                DeckHandLog.app.info("Intent \(pending.command.kindName, privacy: .public) (queued) → \(String(describing: outcome), privacy: .public)")
            }
        }
    }

    func detach(session: ControlSessionModel) {
        guard self.session === session else { return }
        if let mac {
            WidgetSnapshotWriter.shared.updateGlance(macID: mac.id, frontApp: nil, glance: .offline)
        }
        self.session = nil
        mac = nil
    }

    /// Keeps the widget strip's `STUDIO · XCODE` current (VQ-072): the
    /// front app while the session is up, LOCKED while the Mac is locked.
    /// `@Observable`, so it re-arms after every change.
    private func observeGlance(_ session: ControlSessionModel, macID: String) {
        guard self.session === session else { return }
        let (app, lock) = withObservationTracking {
            (session.activeAppName, session.macLockState)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeGlance(session, macID: macID)
            }
        }
        WidgetSnapshotWriter.shared.updateGlance(macID: macID, frontApp: app, glance: lock.isLocked ? .locked : .live)
    }

    // MARK: - Running

    func handle(_ pending: PendingCommand) async -> IntentRunOutcome {
        let command = pending.command
        if let issue = command.validationIssue { return .invalid(issue) }
        guard await isAllowed(command) else { return .needsPro(command.feature) }

        if case let .open(surface) = command {
            requestSurface(surface)
            return .done
        }
        guard let session, let mac else {
            PixelHandAppGroup.enqueue(pending)
            return .waitingForMac
        }
        if let wanted = pending.macID, wanted != mac.id {
            return .connectedToOtherMac(mac.name)
        }
        guard await waitForSender(session), let sender = session.sender else {
            PixelHandAppGroup.enqueue(pending)
            return .waitingForMac
        }
        let outcome = await execute(command, session: session, sender: sender)
        DeckHandLog.app.info("Intent \(command.kindName, privacy: .public) → \(String(describing: outcome), privacy: .public)")
        return outcome
    }

    private func execute(_ command: RemoteCommand, session: ControlSessionModel, sender: TrackpadSender) async -> IntentRunOutcome {
        switch command {
        case let .runKey(keyID):
            guard let key = DeckStore.shared.document.pages.lazy.flatMap(\.keys).first(where: { $0.id == keyID }) else {
                return .keyMissing
            }
            return Self.outcome(await sender.sendConfirmed(key.action))
        case .system, .media:
            guard let action = command.action else { return .notDelivered }
            return Self.outcome(await sender.sendConfirmed(action))
        case let .typeText(text):
            await sender.typeText(text)
            return .done
        case .screenshot:
            let quality = settings?.screenshotQuality ?? .standard
            session.capture.beginCapture(intent: .fullScreen, mode: .fullScreen, quality: quality)
            return .done
        case let .mirror(mode):
            guard let settings else { return .notDelivered }
            if mode.shouldToggle(isRunning: session.isMirrorActive) {
                session.toggleMirror(settings: settings)
            }
            if session.isMirrorActive { requestSurface(.screen) }
            return .done
        case let .open(surface):
            requestSurface(surface)
            return .done
        }
    }

    private static func outcome(_ delivery: CommandDelivery) -> IntentRunOutcome {
        switch delivery {
        case .sent, .confirmed: .done
        case .failed, .timedOut: .notDelivered
        }
    }

    /// Whether the plan allows `command`. Right after a cold launch StoreKit
    /// may not have answered yet; a Pro command waits up to two seconds for
    /// it rather than showing a subscriber a paywall message.
    private func isAllowed(_ command: RemoteCommand) async -> Bool {
        if command.feature.tier == .free { return true }
        for _ in 0..<20 {
            let entitlement = SubscriptionStore.shared.entitlement
            if command.isAllowed(by: entitlement) { return true }
            if entitlement.isSettled { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return command.isAllowed(by: SubscriptionStore.shared.entitlement)
    }

    /// The session's sender appears when its `run` starts; give it a few
    /// seconds after a connection.
    private func waitForSender(_ session: ControlSessionModel) async -> Bool {
        for _ in 0..<50 {
            if session.sender != nil { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return session.sender != nil
    }

    private func requestSurface(_ surface: RemoteSurface) {
        let target: ControlSurface = switch surface {
        case .trackpad: .pointer
        case .deck: .deck
        case .screen: .screen
        }
        surfaceRequest = SurfaceRequest(surface: target, requested: surface)
    }
}

// MARK: - View hooks

extension View {
    /// Lets App Intents run on `session` while this view is up
    /// (`ControlView`).
    func intentBridge(session: ControlSessionModel, settings: DeckHandSettings, macID: UUID, macName: String) -> some View {
        modifier(IntentBridgeModifier(session: session, settings: settings, macID: macID.uuidString, macName: macName))
    }

    /// Switches `selection` when an intent asks for a surface
    /// (`PixelHandShell`). On a window that arranges by preset, pass
    /// `preset` too: "Trackpad" then opens the Pointer arrangement (VQ-079).
    func intentSurfaceRequests(selection: Binding<ControlSurface>, preset: Binding<LayoutPreset>? = nil) -> some View {
        modifier(IntentSurfaceModifier(selection: selection, preset: preset))
    }
}

private struct IntentBridgeModifier: ViewModifier {
    let session: ControlSessionModel
    let settings: DeckHandSettings
    let macID: String
    let macName: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                IntentBridge.shared.attach(session: session, settings: settings, macID: macID, macName: macName)
            }
            .onDisappear {
                IntentBridge.shared.detach(session: session)
            }
    }
}

private struct IntentSurfaceModifier: ViewModifier {
    @Binding var selection: ControlSurface
    var preset: Binding<LayoutPreset>?

    /// The last request applied, so a window that comes back (or a
    /// layout that changes form) doesn't re-apply an old one.
    @State private var appliedID: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear { apply(IntentBridge.shared.surfaceRequest) }
            .onChange(of: IntentBridge.shared.surfaceRequest) { _, request in apply(request) }
    }

    private func apply(_ request: IntentBridge.SurfaceRequest?) {
        guard let request, request.id != appliedID else { return }
        appliedID = request.id
        if let preset, let arrangement = request.requested.arrangement(from: preset.wrappedValue) {
            preset.wrappedValue = arrangement
        }
        if selection != request.surface {
            selection = request.surface
        }
    }
}
