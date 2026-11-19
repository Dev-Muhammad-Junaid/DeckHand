// Linux type-check stubs for DeckHand/Scripts/linux-typecheck/run.sh.
// Signatures are copied from the real Mac/iOS sources: when a real
// signature changes, change it here too, or the check reports a false error.
import Foundation
@_exported import PixelHandCore

typealias ScrollPhase = PixelHandCore.ScrollPhase
typealias Action = PixelHandCore.Action
typealias CGDirectDisplayID = UInt32

// MARK: Loom
public final class LoomMultiplexedStream: @unchecked Sendable {
    public let id: UInt16 = 0
    public let label: String? = nil
    public let incomingBytes: AsyncStream<Data> = AsyncStream { _ in }
    public func send(_ data: Data) async throws {}
    public func close() async throws {}
}
public protocol LoomSessionProtocol: Sendable {
    func makeIncomingStreamObserver() -> AsyncStream<LoomMultiplexedStream>
    func makePathObserver() async -> AsyncStream<LoomSessionNetworkPathSnapshot>
    var context: LoomAuthenticatedSessionContext? { get async }
}
final class StubSession: LoomSessionProtocol {
    func makeIncomingStreamObserver() -> AsyncStream<LoomMultiplexedStream> { AsyncStream { _ in } }
    func makePathObserver() async -> AsyncStream<LoomSessionNetworkPathSnapshot> { AsyncStream { _ in } }
    var context: LoomAuthenticatedSessionContext? { get async { nil } }
}
public actor LoomAuthenticatedSession: LoomSessionProtocol {
    public nonisolated func makeIncomingStreamObserver() -> AsyncStream<LoomMultiplexedStream> { AsyncStream { _ in } }
    public func makePathObserver() -> AsyncStream<LoomSessionNetworkPathSnapshot> { AsyncStream { _ in } }
    public var context: LoomAuthenticatedSessionContext? { nil }
    public var backendRemoteEndpoint: LoomNetworkEndpoint? { nil }
}
public struct LoomOverlaySeed: Hashable, Sendable {
    public let host: String
    public let probePort: UInt16?
    public init(host: String, probePort: UInt16? = nil) { self.host = host; self.probePort = probePort }
}
public struct LoomOverlayDirectoryConfiguration: Sendable {
    public typealias SeedProvider = @Sendable () async throws -> [LoomOverlaySeed]
    public init(probePort: UInt16? = nil, refreshInterval: Duration = .seconds(30), probeTimeout: Duration = .seconds(2), probeAttempts: Int, probeRetryDelay: Duration = .zero, seedProvider: @escaping SeedProvider) {}
    public init(probePort: UInt16? = nil, refreshInterval: Duration = .seconds(30), probeTimeout: Duration = .seconds(2), seedProvider: @escaping SeedProvider) {}
}
public actor LoomConnectionHandle {
    public nonisolated let id: UUID = UUID()
    public nonisolated let messages: AsyncStream<Data> = AsyncStream { _ in }
    public nonisolated let networkPathUpdates: AsyncStream<LoomSessionNetworkPathSnapshot> = AsyncStream { _ in }
    // Cross-module, the real `let` needs `await`; this mirrors that.
    public var session: any LoomSessionProtocol { get async { StubSession() } }
    public func send(_ data: Data) async throws {}
    public func disconnect() async {}
    public func openStream(label: String) async throws -> LoomMultiplexedStream { LoomMultiplexedStream() }
}

public struct LoomNetworkHost: Sendable, Hashable { public let rawValue: String }
public enum LoomNetworkEndpoint: Sendable, Hashable {
    case hostPort(host: LoomNetworkHost, port: UInt16)
    case opaque(description: String)
    public var hostPort: (host: LoomNetworkHost, port: UInt16)? {
        guard case let .hostPort(host, port) = self else { return nil }
        return (host, port)
    }
}
public struct LoomNetworkInterface: Sendable, Hashable {
    public let name: String
    public let index: Int?
}
public struct LoomSessionNetworkPathSnapshot: Sendable, Equatable {
    public let interfaceNames: [String]
    public let interfaces: [LoomNetworkInterface]
    public var primaryInterface: LoomNetworkInterface? { interfaces.first }
    public let usesWiFi: Bool
    public let usesWiredEthernet: Bool
    public let usesCellular: Bool
    public let usesLoopback: Bool
    public let usesOther: Bool
    public let backendLocalEndpoint: LoomNetworkEndpoint?
    public let backendRemoteEndpoint: LoomNetworkEndpoint?
}

// MARK: os.Logger stand-in
struct LogMessage: ExpressibleByStringInterpolation {
    struct Interp: StringInterpolationProtocol {
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ s: String) {}
        mutating func appendInterpolation<T>(_ v: @autoclosure () -> T, privacy: Privacy = .auto) {}
        mutating func appendInterpolation(_ v: @autoclosure () -> Double, format: Format, privacy: Privacy = .auto) {}
        mutating func appendInterpolation(_ v: @autoclosure () -> Float, format: Format, privacy: Privacy = .auto) {}
    }
    init(stringLiteral: String) {}
    init(stringInterpolation: Interp) {}
    enum Privacy { case `public`, `private`, auto }
    enum Format { case fixed(precision: Int) }
}
struct Logger: Sendable {
    func info(_ m: LogMessage) {}
    func debug(_ m: LogMessage) {}
    func error(_ m: LogMessage) {}
    func fault(_ m: LogMessage) {}
}
enum DeckHandLog {
    static let input = Logger()
    static let connection = Logger()
    static let app = Logger()
    static let trust = Logger()
}

// MARK: Mac services
enum USBNetworkProbe {
    static func isUSBTether(bsdName: String) -> Bool? { nil }
}
let NX_KEYTYPE_PLAY: Int32 = 16
let NX_KEYTYPE_NEXT: Int32 = 17
let NX_KEYTYPE_PREVIOUS: Int32 = 18
func CGPreflightScreenCaptureAccess() -> Bool { true }
struct CGError: Equatable { static let success = CGError() }
func CGGetActiveDisplayList(_ max: UInt32, _ ids: UnsafeMutablePointer<CGDirectDisplayID>?, _ count: UnsafeMutablePointer<UInt32>) -> CGError { .success }

@MainActor final class InputInjector {
    static let shared = InputInjector()
    var isAccessibilityGranted: Bool { true }
    func moveCursor(dx: Float, dy: Float) {}
    func scroll(dx: Float, dy: Float, phase: ScrollPhase) {}
    enum ScrollPhase: Sendable { case begin, changed, end, momentumBegin, momentumChanged, momentumEnd }
    func click(button: MouseButton, double: Bool = false) {}
    func sendShortcut(keys: [String]) {}
    func sendMediaKey(_ keyType: Int32) {}
    func moveCursorToMenuBar(ofDisplay displayID: CGDirectDisplayID) {}
    func moveCursorToCenter(ofDisplay displayID: CGDirectDisplayID) {}
    func cursorPosition() -> CGPoint { .zero }
    func moveCursor(to point: CGPoint) {}
    func displayIDUnderCursor() -> CGDirectDisplayID { 0 }
    // iOS interaction lane
    private(set) var heldButtons: Set<MouseButton> = []
    func mouseDown(button: MouseButton) {}
    func mouseUp(button: MouseButton) {}
    func typeKey(_ stroke: LayoutKeyStroke) {}
    func typeNamedKey(_ name: String) {}
    func typeUnicode(_ text: String) {}
}
// iOS interaction lane (Carbon / AppKit inside; their callers are checked)
@MainActor final class KeyboardLayoutMap {
    static let shared = KeyboardLayoutMap()
    func stroke(for character: Character) -> LayoutKeyStroke? { nil }
    func refreshIfNeeded() {}
}
@MainActor final class MacClipboardSync {
    static let shared = MacClipboardSync()
    func setSync(_ enabled: Bool, for handle: LoomConnectionHandle, id: UUID) {}
    func setClipboard(_ text: String, paste: Bool, from id: UUID) {}
    func removeConnection(id: UUID) {}
}
@MainActor final class AppLauncher {
    static let shared = AppLauncher()
    @discardableResult func launch(bundleID: String) async -> Bool { true }
    func activateAndWait(bundleID: String, timeout: TimeInterval = 1.0, settleDelay: TimeInterval = 0.08) async {}
}
@MainActor final class ContextObserver {
    static let shared = ContextObserver()
    func contextVisibilityChanged() {}
    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {}
    func removeConnection(id: UUID) {}
    func hasAction(id: String) -> Bool { true }
    func performAction(id: String) {}
}
@MainActor final class ActiveAppMonitor {
    static let shared = ActiveAppMonitor()
    func contextVisibilityChanged() {}
    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {}
    func removeConnection(id: UUID) {}
}
@MainActor final class RunningAppMonitor {
    static let shared = RunningAppMonitor()
    func contextVisibilityChanged() {}
    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {}
    func removeConnection(id: UUID) {}
}
@MainActor final class MirrorStreamService {
    static let shared = MirrorStreamService()
    func start(subscriberID: UUID, handle: LoomConnectionHandle, fps: Int, maxWidth: Int, displayID: UInt32?, codec: MirrorCodec, windowID: UInt32? = nil) async {}
    func stop(subscriberID: UUID) async {}
    func requestKeyFrame(subscriberID: UUID) {}
    var lastHostStats: [UUID: MirrorHostStats] = [:]
}
// Mac Audio/MirrorAudioCapture.swift (ScreenCaptureKit) can't build here (S17).
final class MirrorAudioCapture: @unchecked Sendable {
    var onPacket: (@Sendable (MirrorAudioFormat, MirrorAudioPacket, UInt64) -> Void)?
    var onFailure: (@Sendable (String) -> Void)?
    func start() async throws {}
    func stop() async {}
}
// iOS Mirror/MirrorHEVCSampleBuilder.swift (CoreMedia) can't build here.
final class CMSampleBuffer {}
enum MirrorVideoEvent: @unchecked Sendable {
    case parameterSets(valid: Bool, dimensions: CGSize?)
    case frame(kind: MirrorVideoWatchdog.FrameKind, afterDrop: Bool, sample: CMSampleBuffer?)
}
final class MirrorHEVCSampleBuilder {
    var dimensions: CGSize? { nil }
    func setParameterSets(_ payload: Data) -> Bool { false }
    func sampleBuffer(payload: Data, isKeyFrame: Bool, presentationTimeMicros: UInt64) -> CMSampleBuffer? { nil }
}

// Mac Mirror/MirrorHEVCEncoder.swift (VideoToolbox) can't build here.
struct MirrorHEVCEncodedFrame: Sendable {
    let isKeyFrame: Bool
    let parameterSets: Data?
    let payload: Data
    let presentationTimeMicros: UInt64
    let encodeSeconds: Double
    let width: Int
    let height: Int
}
@MainActor final class ScreenCaptureService {
    static let shared = ScreenCaptureService()
    enum CaptureError: Error { case permissionDenied, noDisplay, windowNotFound, captureFailed(String), encodeFailed }
    func captureMainDisplayJPEG(maxWidth: CGFloat = 1920, quality: CGFloat = 0.75) async throws -> Data { Data() }
    func captureRegion(normalizedRect: CGRect, maxWidth: CGFloat = 2400) async throws -> Data { Data() }
    func captureWindowJPEG(windowID: UInt32, maxWidth: CGFloat = 2400) async throws -> Data { Data() }
    func enumerateWindows() async throws -> [WindowInfo] { [] }
}
@MainActor final class InstalledAppScanner {
    static let shared = InstalledAppScanner()
    func installedApps() -> [InstalledAppInfo] { [] }
}
enum MenuShortcutDiscovery {
    @MainActor static func discover(bundleID: String, launcher: AppLauncher) async -> [AppShortcutBinding] { [] }
}
@MainActor final class CursorLocator {
    static let shared = CursorLocator()
    func ping() {}
}
@MainActor final class SystemActionTrigger {
    static let shared = SystemActionTrigger()
    @discardableResult func run(_ macro: SystemMacro) async -> Bool { true }
}
// Mac system control lane
@MainActor final class SymbolicHotKeys {
    static let shared = SymbolicHotKeys()
    @discardableResult func perform(_ action: HotKeyAction) async -> Bool { true }
}
@MainActor final class SpacesMonitor {
    static let shared = SpacesMonitor()
    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {}
    func removeConnection(id: UUID) {}
    func noteCursorActivity() {}
    func scheduleBroadcast() {}
    func send(to handle: LoomConnectionHandle) {}
    func currentLayout() -> DisplayLayout { DisplayLayout(displays: [], cursorDisplayID: nil, spacesKnown: false, separateSpaces: true) }
}
@MainActor final class MacLockMonitor {
    static let shared = MacLockMonitor()
    private(set) var state: MacLockState = .unlocked
    var connectionHandles: [UUID: LoomConnectionHandle] { [:] }
    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {}
    func removeConnection(id: UUID) {}
}
@MainActor final class DisplayWake {
    static let shared = DisplayWake()
    func note(_ trigger: DisplayWakeTrigger, lock: MacLockState) {}
}
final class NSWorkspace: @unchecked Sendable {
    static let shared = NSWorkspace()
    let notificationCenter = NotificationCenter()
    static let activeSpaceDidChangeNotification = Notification.Name("activeSpaceDidChange")
}

// MARK: iOS
func CACurrentMediaTime() -> Double { 0 }
final class UIImage: @unchecked Sendable {
    init?(data: Data) {}
    func preparingForDisplay() -> UIImage? { self }
}
// iOS interaction lane
final class UIPasteboard: @unchecked Sendable {
    static let general = UIPasteboard()
    var string: String?
}

enum TrackpadGestureKind { enum ThreeFingerDirection { case left, right, up, down } }

// MARK: Loom identity and trust (pairing lane)
public enum DeviceType: String, Codable, Sendable { case mac, iPad, iPhone, vision, unknown }
public struct LoomPeerIdentity: Sendable, Equatable {
    public let deviceID: UUID
    public let name: String
    public let deviceType: DeviceType
    public let iCloudUserID: String?
    public let identityKeyID: String?
    public let identityPublicKey: Data?
    public let isIdentityAuthenticated: Bool
    public let advertisementMetadata: [String: String]
    public let endpoint: String
}
public struct LoomAuthenticatedSessionContext: Sendable, Equatable {
    public let peerIdentity: LoomPeerIdentity
}
public enum LoomTrustDecision: Sendable, Equatable { case trusted, requiresApproval, denied, unavailable(String) }
public struct LoomTrustEvaluation: Sendable, Equatable {
    public let decision: LoomTrustDecision
    public let shouldShowAutoTrustNotice: Bool
    public init(decision: LoomTrustDecision, shouldShowAutoTrustNotice: Bool) {
        self.decision = decision
        self.shouldShowAutoTrustNotice = shouldShowAutoTrustNotice
    }
}
public protocol LoomTrustProvider: AnyObject, Sendable {
    @MainActor func evaluateTrust(for peer: LoomPeerIdentity) async -> LoomTrustDecision
    @MainActor func evaluateTrustOutcome(for peer: LoomPeerIdentity) async -> LoomTrustEvaluation
    @MainActor func grantTrust(to peer: LoomPeerIdentity) async throws
    @MainActor func revokeTrust(for deviceID: UUID) async throws
}
public struct LoomAccountIdentity: Sendable { public let keyID: String; public let publicKey: Data }
@MainActor public final class LoomIdentityManager {
    public static let shared = LoomIdentityManager()
    public func currentIdentity() throws -> LoomAccountIdentity { LoomAccountIdentity(keyID: "", publicKey: Data()) }
    public nonisolated static func keyID(for publicKey: Data) -> String { "" }
}
public enum LoomSharedDeviceID {
    public static func getOrCreate(suiteName: String? = nil, key: String = "") -> UUID { UUID() }
}
public struct LoomPeerID: Codable, Hashable, Sendable {
    public let deviceID: UUID
    public init(deviceID: UUID, appID: String? = nil) { self.deviceID = deviceID }
    public var uuidString: String { deviceID.uuidString }
}
public enum LoomTransportKind: String, Sendable { case tcp, udp, quic }
public struct LoomConnectionSnapshot: Sendable, Identifiable {
    public enum State: Sendable { case connecting, connected, stale, disconnecting, disconnected, failed, reconnecting }
    public let id: UUID
    public let peerID: LoomPeerID
    public let peerName: String
    public let state: State
    public let transportKind: LoomTransportKind
    public let connectedAt: Date
    public let lastError: String?
}
public struct LoomConnectionDismissal: Sendable, Identifiable {
    public let id: UUID
    public let peerID: LoomPeerID
    public let peerName: String
}
@MainActor public final class LoomContext {
    public private(set) var connections: [LoomConnectionSnapshot] = []
    public func disconnect(_ connection: LoomConnectionSnapshot) async {}
    public func connect(_ peer: LoomPeerSnapshot) async throws -> LoomConnectionHandle { LoomConnectionHandle() }
    public func connect(_ peer: LoomPeerSnapshot, pinnedIdentity: LoomPeerIdentityPin) async throws -> LoomConnectionHandle { LoomConnectionHandle() }
}

// MARK: Loom remote access (S15)
public struct LoomPeerIdentityPin: Hashable, Sendable {
    public let identityKeyID: String
    public let identityPublicKey: Data?
    public init?(identityKeyID: String, identityPublicKey: Data? = nil) {
        guard !identityKeyID.isEmpty else { return nil }
        self.identityKeyID = identityKeyID
        self.identityPublicKey = identityPublicKey
    }
}
public struct LoomPeerAdvertisement: Sendable, Hashable {
    public let deviceID: UUID?
    public let identityKeyID: String?
}
public struct LoomPeerSnapshot: Identifiable, Hashable, Sendable {
    public let id: LoomPeerID
    public let name: String
    public let isNearby: Bool
    public let advertisement: LoomPeerAdvertisement
    public var deviceID: UUID { id.deviceID }
}
public struct LoomPeer: Sendable {
    public let id: LoomPeerID
    public let advertisement: LoomPeerAdvertisement
    public var deviceID: UUID { id.deviceID }
}
@MainActor public final class LoomOverlayDirectory {
    public private(set) var discoveredPeers: [LoomPeer] = []
    public init(configuration: LoomOverlayDirectoryConfiguration, localDeviceID: UUID? = nil) {}
    public func refresh() async {}
    public func stop() {}
}

// MARK: Combine stand-in
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    var projectedValue: PublishedPublisher<Value> { PublishedPublisher() }
}
struct PublishedPublisher<Value> {
    func dropFirst() -> PublishedPublisher<Value> { self }
    func sink(receiveValue: @escaping (Value) -> Void) -> AnyCancellable { AnyCancellable() }
}
final class AnyCancellable {}

// MARK: UserNotifications stand-in
struct UNNotificationActionOptions: OptionSet, Sendable {
    let rawValue: Int
    static let foreground = UNNotificationActionOptions(rawValue: 1)
    static let destructive = UNNotificationActionOptions(rawValue: 2)
}
struct UNNotificationCategoryOptions: OptionSet, Sendable { let rawValue: Int }
struct UNAuthorizationOptions: OptionSet, Sendable {
    let rawValue: Int
    static let alert = UNAuthorizationOptions(rawValue: 1)
    static let sound = UNAuthorizationOptions(rawValue: 2)
}
enum UNAuthorizationStatus: Sendable { case notDetermined, denied, authorized, provisional, ephemeral }
final class UNNotificationSettings: @unchecked Sendable { var authorizationStatus: UNAuthorizationStatus { .authorized } }
final class UNNotificationAction: @unchecked Sendable {
    init(identifier: String, title: String, options: UNNotificationActionOptions) {}
}
final class UNNotificationCategory: Hashable, @unchecked Sendable {
    init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], options: UNNotificationCategoryOptions) {}
    static func == (a: UNNotificationCategory, b: UNNotificationCategory) -> Bool { a === b }
    func hash(into hasher: inout Hasher) {}
}
class UNNotificationContent: @unchecked Sendable { var userInfo: [AnyHashable: Any] = [:] }
final class UNMutableNotificationContent: UNNotificationContent, @unchecked Sendable {
    var title = ""
    var body = ""
    var sound: UNNotificationSound?
    var categoryIdentifier = ""
}
final class UNNotificationSound: @unchecked Sendable { static let `default` = UNNotificationSound() }
final class UNNotificationTrigger: @unchecked Sendable {}
final class UNNotificationRequest: @unchecked Sendable {
    let content: UNNotificationContent
    init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) { self.content = content }
}
final class UNNotification: @unchecked Sendable { var request: UNNotificationRequest { fatalError() } }
final class UNNotificationResponse: @unchecked Sendable {
    var actionIdentifier: String { "" }
    var notification: UNNotification { fatalError() }
}
protocol UNUserNotificationCenterDelegate: AnyObject {}
final class UNUserNotificationCenter: @unchecked Sendable {
    static func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }
    weak var delegate: UNUserNotificationCenterDelegate?
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func getNotificationSettings(completionHandler: @escaping @Sendable (UNNotificationSettings) -> Void) {}
    func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping @Sendable (Bool, Error?) -> Void) {}
    func add(_ request: UNNotificationRequest, withCompletionHandler: (@Sendable (Error?) -> Void)? = nil) {}
    func removePendingNotificationRequests(withIdentifiers: [String]) {}
    func removeDeliveredNotifications(withIdentifiers: [String]) {}
}

// MARK: Deck 2 (DeckHandMac/Deck/MenuCommandPresser.swift reads AX, so it is stubbed)
enum MenuCommandPresser {
    enum Result: Equatable, Sendable { case pressed, appNotRunning, notFound(level: Int), disabled, gaveUp, pressFailed }
    @MainActor static func press(bundleID: String, path: [String], launcher: AppLauncher) async -> Result { .pressed }
    static func outcome(_ result: Result, path: [String]) -> ActionOutcome { .completed }
}
