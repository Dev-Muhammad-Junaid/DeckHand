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

    // MARK: Mirror
    // Live mirror (WID-403), binary stream, local cursor (S3), display
    // picker and stats (S6). Logic in ControlSessionModel+Mirror.swift;
    // frames arrive on the mirror's own stream (MirrorStreamReceiver), not
    // through the message loop below. Setters are internal so that
    // extension can write them.

    /// Stream width the mirror's current on-screen size asks for, before the
    /// sharpness preference gets a say. Kept so a settings change can
    /// re-derive the effective width without waiting for another pinch.
    var mirrorNaturalWidth = 640
    /// Whether the user has the floating mirror thumbnail enabled. Drives
    /// start/stop on the wire and the overlay's visibility.
    var isMirrorActive = false
    /// Latest decoded mirror frame. Replaced wholesale per frame; only one
    /// is ever retained.
    var mirrorImage: UIImage?
    /// Display the current stream is pointed at. `nil` until the host says.
    var selectedMirrorDisplayID: UInt32?
    /// Displays the Mac can mirror, from `mirror.displayList`.
    var mirrorDisplays: [DisplayInfo] = []
    /// Where the Mac's pointer is (S3). Only the cursor layer reads it, so
    /// 60 updates a second don't redraw the rest of the mirror.
    var mirrorCursor: MirrorCursorState?
    /// The display the pointer is on. Changes rarely, so the badge reads
    /// this instead of `mirrorCursor`.
    var mirrorCursorDisplayID: UInt32?
    /// The image for `mirrorCursor.shapeID`, once it has arrived.
    var mirrorCursorSprite: MirrorCursorSprite?
    @ObservationIgnored var mirrorCursorShapes = MirrorCursorShapeCache<UIImage>()
    /// Follow-cursor timing (MirrorDisplayFollower).
    @ObservationIgnored var mirrorFollower = MirrorDisplayFollower()
    /// The latest stats from each end (S6), for the HUD.
    var mirrorHostStats: MirrorHostStats?
    var mirrorClientStats: MirrorClientStats?
    @ObservationIgnored let mirrorStatsBox = MirrorClientStatsBox()
    /// The settings the mirror was started with (frame rate, sharpness,
    /// Follow cursor). Set by `run(settings:)`.
    @ObservationIgnored weak var mirrorSettings: DeckHandSettings?
    /// HEVC video (S5): the layer frames are decoded into, whether it (not
    /// `mirrorImage`) is showing, and the picture size from the parameter
    /// sets.
    @ObservationIgnored let mirrorVideoRenderer = MirrorVideoRenderer()
    var mirrorShowsVideo = false
    var mirrorVideoSize: CGSize?
    /// Decides what to decode and when to ask for a key frame or JPEG.
    @ObservationIgnored var mirrorWatchdog = MirrorVideoWatchdog(now: 0)
    /// HEVC gave up in this session; the mirror asks for JPEG from now on.
    @ObservationIgnored var mirrorHEVCFellBack = false
    @ObservationIgnored var mirrorLastRequestedCodec: MirrorCodec?
    /// S14: the window the mirror asked for and the one the Mac shows.
    var mirrorWindowSelection = MirrorWindowSelection()
    /// The latest cursor update's "over the mirrored display / window".
    var mirrorCursorInsideMirror: Bool?
    /// A passing notice over the mirror (a mirrored window ended and the
    /// mirror went back to its display), and the task that clears it.
    var mirrorNotice: String?
    @ObservationIgnored var mirrorNoticeTask: Task<Void, Never>?
    /// S17: plays the Mac's sound (own stream, MirrorAudioReceiver). Logic
    /// in ControlSessionModel+Audio.swift.
    @ObservationIgnored let mirrorAudio = MirrorAudioPlayer()

    // MARK: Pairing
    // Approval status, the resync poll, pairing codes and "Forget" (S4).
    // Logic in ControlSessionModel+Pairing.swift (pairing lane).

    /// `true` once a decisive `authorizationStatus` has arrived from the
    /// host. Stops the resync poll.
    @ObservationIgnored var hasReceivedAuthStatus = false
    /// Last status received — keeps a "denied" verdict from being stomped
    /// by a liveness timeout.
    @ObservationIgnored var lastAuthStatus = "pending"
    /// The Mac as its handshake proved it; `nil` until read (or if Loom
    /// couldn't verify it).
    @ObservationIgnored var pairingMac: TrustCandidate?
    /// Whether the Mac said this device is paired during this session, so
    /// a later "not paired" reads as the Mac forgetting it.
    @ObservationIgnored var pairedThisSession = false
    @ObservationIgnored var pairingTasks: [Task<Void, Never>] = []
    @ObservationIgnored var pairingSessionToken: UUID?

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

    // MARK: iOS interaction
    // Clipboard sync (S10). Logic: ControlSessionModel+Input.swift.

    /// What came from the Mac's clipboard and the last Paste to Mac.
    let clipboard = RemoteClipboard()
    /// Read for Share Clipboard when the Mac's text arrives.
    @ObservationIgnored weak var interactionSettings: DeckHandSettings?

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
        mirrorSettings = settings
        capture.sender = s
        await s.setSendRate(hz: settings.inputSendRate.rawValue)
        // Load cached app list for instant display
        if let cached = Self.loadCachedAppList() {
            installedApps = cached
        }
        // Then request fresh list from Mac
        Task { await s.requestAppList() }

        // ── Pairing: approval resync poll, Mac identity, QR invite ──
        // See ControlSessionModel+Pairing.swift.
        startPairing(sender: s)
        defer { stopPairing() }

        // ── Network: heartbeat, keep-alive tick, link ──────────
        // See ControlSessionModel+Network.swift. Structured with this
        // .task: everything stops when the view goes away.
        let liveness = startNetwork(sender: s)
        defer { stopNetwork() }

        // The mirror's binary stream has its own reader, and its stats go
        // back to the Mac once a second while the mirror runs.
        let mirror = Task { [weak self] in await self?.runMirrorReceiver() }
        let mirrorStats = Task { [weak self] in await self?.runMirrorStatsLoop() }
        defer {
            mirror.cancel()
            mirrorStats.cancel()
        }

        // Clipboard sync on/off to the Mac (ControlSessionModel+Input.swift).
        let interaction = Task { [weak self] in await self?.runInteraction(sender: s, settings: settings) }
        defer { interaction.cancel() }

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
            if case .diagnostics = message {} else {
                print("DeckHandiOS: 📥 \(data.count)B \(messageTypeName(message))")
            }
            #endif
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
            handleAuthorizationStatus(state)

        case let .pairing(.codeResult(result)):
            handleCodeResult(result)

        case let .pairing(.pairedStatus(paired)):
            handlePairedStatus(paired)

        case let .apps(.activeAppUpdate(name, bundleID)):
            withAnimation(.easeInOut(duration: 0.2)) {
                activeAppName = name
                activeBundleID = bundleID
            }

        case let .capture(.screenshotData(requestID, data)):
            capture.handleScreenshotData(requestID: requestID, data: data)

        case let .mirror(.error(message, fallbackDisplayID)):
            handleMirrorError(message, fallbackDisplayID: fallbackDisplayID)

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

        case let .mirror(.displayList(displays, selectedDisplayID, window)):
            handleMirrorDisplayList(displays, selected: selectedDisplayID, window: window)

        case let .mirror(.audioError(message)):
            handleMirrorAudioError(message)

        case let .diagnostics(.mirrorStats(stats)):
            mirrorHostStats = stats

        case let .sharing(m):
            handleSharingMessage(m)

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
