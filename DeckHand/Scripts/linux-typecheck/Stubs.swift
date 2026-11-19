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
}
final class StubSession: LoomSessionProtocol {
    func makeIncomingStreamObserver() -> AsyncStream<LoomMultiplexedStream> { AsyncStream { _ in } }
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
    func start(subscriberID: UUID, handle: LoomConnectionHandle, fps: Int, maxWidth: Int, displayID: UInt32?) async {}
    func stop(subscriberID: UUID) async {}
    var lastHostStats: [UUID: MirrorHostStats] = [:]
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
enum TrackpadGestureKind { enum ThreeFingerDirection { case left, right, up, down } }
