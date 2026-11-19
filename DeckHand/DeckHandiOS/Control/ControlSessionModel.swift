//
//  ControlSessionModel.swift
//  DeckHandiOS
//
//  Everything about one connection to a Mac that `ControlView` used to keep
//  in `@State`: the sender, the single inbound message loop, the liveness
//  heartbeat, the approval resync poll, what the Mac reports (permissions,
//  apps, frontmost app, dialog context) and the live mirror. Captures are
//  in `CaptureCoordinator`.
//
//  `ControlView` owns one in `@State` and runs it from `.task`, so the loop
//  and the heartbeat end when the view goes away, exactly as before.
//

import LoomKit
import Observation
import SwiftUI

extension Notification.Name {
    /// Broadcast when the Mac replies to a menu-shortcut import request.
    /// userInfo keys: `bundleID` (String), `added` (Int), `total` (Int).
    static let appMenuShortcutsImported = Notification.Name("DeckHand.appMenuShortcutsImported")
}

@MainActor
@Observable
final class ControlSessionModel {
    @ObservationIgnored let connection: LoomConnectionHandle
    @ObservationIgnored let onAuthStatusChanged: (String) -> Void

    private(set) var sender: TrackpadSender?
    let capture = CaptureCoordinator()

    /// Stream width the mirror's current on-screen size asks for, before the
    /// sharpness preference gets a say. Kept so a settings change can
    /// re-derive the effective width without waiting for another pinch.
    var mirrorNaturalWidth = 640

    // Bidirectional state
    private(set) var activeAppName: String?
    private(set) var activeBundleID: String?
    private(set) var installedApps: [InstalledAppInfo] = []
    /// Bundle IDs of apps currently running on the Mac, in Cmd+Tab order
    /// (most-recently-activated first). Pushed by `RunningAppMonitor`.
    private(set) var runningBundleIDs: [String] = []
    /// Latest accessibility-derived context snapshot from the Mac. When a
    /// modal dialog is visible on the frontmost app this carries its
    /// buttons; the Quick Actions bar swaps its contextual segment to
    /// surface them.
    private(set) var uiContext: UIContextSnapshot = .none

    // ── Live mini mirror (WID-403) ──────────────────────────────────
    /// Whether the user has the floating mirror thumbnail enabled. Drives
    /// startMirror/stopMirror on the wire and the overlay's visibility.
    private(set) var isMirrorActive = false
    /// Latest decoded mirror frame. Replaced wholesale per frame — at
    /// ~480px these are ~1 MB decoded, and only one is ever retained.
    private(set) var mirrorImage: UIImage?
    /// Highest sequence number rendered; lower/equal arrivals are stale
    /// (shouldn't happen on an ordered transport, but cheap to guard).
    @ObservationIgnored private var mirrorLastSeq: UInt64 = 0
    /// Display the current stream is pointed at. `nil` until the host says.
    private(set) var selectedMirrorDisplayID: UInt32?

    /// `true` once any `authorizationStatus` has arrived from the host.
    /// Gates the resync poll below — we stop asking once we've heard
    /// anything, because from then on pushes are flowing.
    @ObservationIgnored private var hasReceivedAuthStatus = false
    /// Last status received — keeps a "denied" verdict from being stomped
    /// by a liveness timeout.
    @ObservationIgnored var lastAuthStatus = "pending"

    // MARK: Network
    // Heartbeat, keep-alive tick, background pause and the link judgement.
    // Logic in ControlSessionModel+Network.swift (network lane).

    /// The link this session runs over as shown to the user ("Wired" over
    /// a USB cable). Set only by ControlSessionModel+Network.swift.
    var link: LinkKind = .unknown
    /// In front or not, this side's link and the Mac's report.
    @ObservationIgnored var keepAlive = KeepAliveGate()
    /// The current connection's liveness clock, made in `startNetwork`.
    @ObservationIgnored var livenessClock: LivenessClock?
    @ObservationIgnored var pingSeq: UInt64 = 0
    @ObservationIgnored var networkTasks: [Task<Void, Never>] = []
    @ObservationIgnored var lifecycleObservers: [NSObjectProtocol] = []

    // ── Host capabilities ───────────────────────────────────────────
    /// What the Mac can actually execute right now, as reported by the
    /// host on session start and refreshed periodically. `nil` = not yet
    /// reported. Drives the warning banner so "nothing happens" always
    /// has a visible reason.
    private(set) var hostAccessibilityGranted: Bool?
    private(set) var hostScreenRecordingGranted: Bool?

    // MARK: Mac system
    // Pushed by the Mac (protocol 3). Logic: ControlSessionModel+MacSystem.swift.

    /// Whether the Mac is locked; most requests are refused while it is.
    var macLockState: MacLockState = .unlocked
    /// The Mac's displays, Spaces and pointer display. `nil` until the Mac
    /// sends it. The Mirror lane builds the display picker, desktop dots
    /// and cursor badge on it.
    var displayLayout: DisplayLayout?

    init(connection: LoomConnectionHandle, onAuthStatusChanged: @escaping (String) -> Void) {
        self.connection = connection
        self.onAuthStatusChanged = onAuthStatusChanged
    }

    // MARK: - Session lifetime

    /// The body of `ControlView`'s `.task`: returns when the Mac's message
    /// stream ends, and is cancelled with the view.
    func run(settings: DeckHandSettings) async {
        let s = TrackpadSender(handle: connection)
        sender = s
        capture.sender = s
        await s.setSendRate(hz: settings.inputSendRate.rawValue)
        // Load cached app list for instant display
        if let cached = Self.loadCachedAppList() {
            installedApps = cached
        }
        // Then request fresh list from Mac
        Task { await s.requestAppList() }

        // ── Authorization resync poll ───────────────────────────
        // The host pushes `authorizationStatus`, and the handle's
        // message stream buffers, so the normal path never loses it.
        // But the push itself is a network send that can fail — and a
        // lost `granted` would strand this view on the approval
        // overlay while the Mac thinks the session is live. Poll
        // until a DECISIVE status (granted/denied) arrives — NOT the
        // initial "pending" the host emits before the user decides.
        // Queries sent while we're still pending sit buffered host-side
        // (the host only consumes this connection's inbox after it
        // authorizes) and are all answered "granted" the moment approval
        // lands, healing any dropped push. Bounded at 20 attempts
        // (~60 s, past the host's 45 s pending expiry) so the loop
        // always terminates even if the view outlives a dead connection.
        Task { [weak self] in
            for _ in 0..<20 {
                guard let self, !self.hasReceivedAuthStatus else { break }
                await s.requestAuthorizationStatus()
                try? await Task.sleep(for: .seconds(3))
            }
        }

        // ── Network: heartbeat, keep-alive tick, link ──────────
        // See ControlSessionModel+Network.swift. Structured with this
        // .task: everything stops when the view goes away.
        let liveness = startNetwork(sender: s)
        defer { stopNetwork() }

        // Single consolidated message loop — no competing consumers
        await listenForHostMessages(liveness: liveness)
    }

    #if DEBUG
    private func messageTypeName(_ m: ControlMessage) -> String {
        // "domain.case", for example "apps.activeAppUpdate".
        let parts = String(describing: m).split(separator: "(")
        let caseName = parts.count > 1 ? parts[1].split(separator: ".").last.map(String.init) ?? "?" : "?"
        return "\(m.domain.rawValue).\(caseName)"
    }
    #endif

    // MARK: - Single Message Listener
    //
    // All messages from the Mac come through here. Splitting this loop
    // across multiple views causes AsyncSequence racing where messages get
    // silently consumed by the wrong listener.

    private func listenForHostMessages(liveness: LivenessClock) async {
        for await data in connection.messages {
            // Anything from the Mac proves it's alive, so a pong stuck
            // behind mirror frames can't read as a dead host.
            liveness.noteInbound()
            let message: ControlMessage
            do {
                message = try ControlMessageCoding.decode(data)
            } catch {
                DeckHandLog.connection.error("Dropped an undecodable message from the Mac (\(data.count, privacy: .public) B): \(String(describing: error), privacy: .public)")
                continue
            }
            #if DEBUG
            print("DeckHandiOS: 📥 \(data.count)B \(messageTypeName(message))")
            #endif
            // Mirror frames are the only high-rate inbound payload (≤20/s)
            // and JPEG decode is the heavy part — decode them off the main
            // actor and only do the cheap state swap here.
            if case let .mirror(.frame(seq, frameData)) = message {
                // This loop runs on the main actor, so decode in a detached
                // task; up to 20 frames a second otherwise compete with
                // touch handling and the heartbeat.
                let decodedFrame = await Task.detached(priority: .userInitiated) {
                    UIImage(data: frameData)?.preparingForDisplay()
                }.value
                guard let decoded = decodedFrame else { continue }
                guard isMirrorActive else { continue }
                // Ordered transport: a sequence REGRESSION can only mean
                // the host restarted the stream (quality re-negotiation),
                // so adopt the new numbering. Only exact duplicates drop.
                guard seq != mirrorLastSeq else { continue }
                mirrorLastSeq = seq
                mirrorImage = decoded
                continue
            }
            // Feature flags and receipts only concern the sender actor; no
            // UI state changes, so they skip the UI handling below.
            switch message {
            case .session(.pong):
                liveness.noteHeartbeat()
                continue
            case let .deck(.receipt(requestID, outcome)):
                await sender?.receivedReceipt(requestID: requestID, outcome: outcome)
                continue
            case let .session(.hostStatus(status)):
                await sender?.setHostSendsReceipts(status.supports(.commandReceipts))
            default:
                break
            }
            handleOnMain(message)
        }

        // Say which side ended it: if the heartbeat didn't give up, the
        // stream ended because the Mac closed the connection.
        if liveness.gaveUp {
            DeckHandLog.connection.info("Host message stream ended after the iPad gave up (see the heartbeat line above)")
        } else {
            let since = Date().timeIntervalSince(liveness.snapshot.lastInboundAt)
            DeckHandLog.connection.info("Host message stream ended: the Mac closed the connection (MAC GAVE UP, quit or revoked; last message \(since, format: .fixed(precision: 1), privacy: .public)s ago)")
        }

        // No stream-end inference here. Liveness is decided by exactly one
        // mechanism — the ping/pong heartbeat above — which can't misfire
        // on view replacement (it's a structured child of the view's
        // .task) and detects every real death within seconds, including
        // abrupt host kills the transport never notices. ContentRootView's
        // events loop still handles explicit `.disconnected` events.
    }

    /// UI state changes for one inbound message.
    private func handleOnMain(_ message: ControlMessage) {
        switch message {
        case let .session(.link(kind)):
            applyHostLink(kind)

        case let .session(.hostStatus(hostStatus)):
            withAnimation(.easeInOut(duration: 0.2)) {
                hostAccessibilityGranted = hostStatus.accessibility
                hostScreenRecordingGranted = hostStatus.screenRecording
            }

        case let .pairing(.authorizationStatus(state)):
            // The UI keeps string states because it adds local ones
            // ("timed_out", "host_disconnected"); see ApprovalStatusCopy.
            let status = state.rawValue
            // Always-on so the pending→granted/denied transition is
            // visible in Console.app for release/TestFlight, not just
            // Xcode-attached DEBUG. `decisive` mirrors the resync-poll
            // gate below.
            DeckHandLog.connection.info("🔑 iPad authorizationStatus = \(status, privacy: .public) (decisive=\(status != "pending"))")
            // Only a DECISIVE verdict disarms the resync poll. The
            // host pushes "pending" the instant the connection lands
            // (before the user has decided); treating that as "heard
            // back" used to stop the poll immediately, so if the later
            // "granted" push was dropped on the wire the iPad sat on
            // the approval overlay forever. The poll is precisely the
            // recovery path for a lost push — keep it alive until the
            // host actually grants or denies.
            let isFirstGrant = status == "granted" && lastAuthStatus != "granted"
            if status != "pending" {
                hasReceivedAuthStatus = true
            }
            lastAuthStatus = status
            onAuthStatusChanged(status)
            // The host's pre-approval gate drops everything sent
            // before Allow, including the app-list request made when
            // this view appeared. Ask again once access is granted.
            if isFirstGrant, let sender {
                Task { await sender.requestAppList() }
            }

        case let .apps(.activeAppUpdate(name, bundleID)):
            withAnimation(.easeInOut(duration: 0.2)) {
                activeAppName = name
                activeBundleID = bundleID
            }

        case let .capture(.screenshotData(requestID, data)):
            capture.handleScreenshotData(requestID: requestID, data: data)

        case let .mirror(.error(message)):
            // Stop the mirror and surface the reason.
            if isMirrorActive {
                isMirrorActive = false
                mirrorImage = nil
                capture.showMirrorError(message)
            }

        case let .capture(.screenshotError(requestID, message)):
            capture.handleScreenshotError(requestID: requestID, message: message)

        case let .capture(.windowListResponse(requestID, windows)):
            capture.handleWindowList(requestID: requestID, windows: windows)

        case let .apps(.appListResponse(apps)):
            withAnimation(.easeInOut(duration: 0.2)) {
                installedApps = apps
            }
            // Cache to disk for instant display on next connect
            Self.cacheAppList(apps)

        case let .apps(.runningAppsUpdate(ids)):
            withAnimation(.easeInOut(duration: 0.2)) {
                runningBundleIDs = ids
            }

        case let .apps(.uiContextUpdate(snapshot)):
            #if DEBUG
            switch snapshot {
            case .none:
                print("DeckHandiOS: 📥 uiContextUpdate .none")
            case .dialog(let ctx):
                print("DeckHandiOS: 📥 uiContextUpdate dialog title='\(ctx.title ?? "")' buttons=\(ctx.buttons.map(\.title))")
            case .textField(let ctx):
                print("DeckHandiOS: 📥 uiContextUpdate textField kind=\(ctx.kind.rawValue)")
            }
            #endif
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                uiContext = snapshot
            }

        case let .system(m):
            handleSystemMessage(m)

        case let .mirror(.displayList(_, selectedDisplayID)):
            selectedMirrorDisplayID = selectedDisplayID

        case let .deck(.appMenuShortcutsResponse(bundleID, shortcuts)):
            let added = ShortcutStore.shared.importBindings(shortcuts, for: bundleID)
            NotificationCenter.default.post(
                name: .appMenuShortcutsImported,
                object: nil,
                userInfo: [
                    "bundleID": bundleID,
                    "added": added,
                    "total": shortcuts.count
                ]
            )

        default:
            break
        }
    }

    // MARK: - Live mirror control (WID-403)

    /// Flips the mirror on/off: updates local UI state immediately for
    /// responsiveness, then tells the Mac. Frame state is reset on stop so
    /// a later restart begins with the loading placeholder, and the last
    /// (~1 MB decoded) frame isn't retained while the mirror is hidden.
    func toggleMirror(settings: DeckHandSettings) {
        guard let sender else { return }
        isMirrorActive.toggle()
        if isMirrorActive {
            mirrorLastSeq = 0
            mirrorImage = nil
            // Seed from the layout the mirror will restore to, so a large
            // saved mirror opens at the right resolution instead of starting
            // small and immediately renegotiating.
            if settings.rememberMirrorLayout, let saved = settings.mirrorLayout {
                mirrorNaturalWidth = MirrorThumbnailView.streamWidth(for: CGFloat(saved.width))
            }
            let fps = settings.mirrorFrameRate.rawValue
            let width = settings.mirrorStreamWidth(naturalWidth: mirrorNaturalWidth)
            let displayID = selectedMirrorDisplayID
            Task { await sender.startMirror(fps: fps, maxWidth: width, displayID: displayID) }
        } else {
            mirrorImage = nil
            Task { await sender.stopMirror() }
        }
    }

    /// Re-negotiates the mirror stream to match how large the user has
    /// pinched the thumbnail and what the sharpness and frame-rate settings
    /// ask for, so text stays legible as it grows without paying for pixels a
    /// corner tile would throw away. Stop+start is cheap — a sub-second
    /// hiccup — and the sequence counter resets with the new stream so fresh
    /// frames aren't dropped as stale.
    func renegotiateMirror(settings: DeckHandSettings) {
        guard let sender, isMirrorActive else { return }
        mirrorLastSeq = 0
        let fps = settings.mirrorFrameRate.rawValue
        let width = settings.mirrorStreamWidth(naturalWidth: mirrorNaturalWidth)
        let displayID = selectedMirrorDisplayID
        Task {
            await sender.stopMirror()
            await sender.startMirror(
                fps: fps,
                maxWidth: width,
                displayID: displayID
            )
        }
    }

    func switchSpace(_ direction: SpaceDirection) {
        let displayID = selectedMirrorDisplayID
        Task { await sender?.switchSpace(direction, displayID: displayID) }
    }
}

// MARK: - App List Caching

extension ControlSessionModel {
    private nonisolated static var appListCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("deckhand_installed_apps.json")
    }

    nonisolated static func cacheAppList(_ apps: [InstalledAppInfo]) {
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(apps) {
                try? data.write(to: appListCacheURL, options: .atomic)
            }
        }
    }

    nonisolated static func loadCachedAppList() -> [InstalledAppInfo]? {
        guard let data = try? Data(contentsOf: appListCacheURL),
              let apps = try? JSONDecoder().decode([InstalledAppInfo].self, from: data) else {
            return nil
        }
        return apps
    }
}
