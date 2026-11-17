// Linux type-check stubs for DeckHand/Scripts/linux-typecheck/run.sh.
// Signatures are copied from the real Mac/iOS sources: when a real
// signature changes, change it here too, or the check reports a false error.
import Foundation
@_exported import PixelHandCore

typealias ScrollPhase = PixelHandCore.ScrollPhase
typealias Action = PixelHandCore.Action
typealias CGDirectDisplayID = UInt32

// MARK: Loom
public actor LoomConnectionHandle {
    public nonisolated let id: UUID = UUID()
    public nonisolated let messages: AsyncStream<Data> = AsyncStream { _ in }
    public func send(_ data: Data) async throws {}
    public func disconnect() async {}
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
let NX_KEYTYPE_PLAY: Int32 = 16
let NX_KEYTYPE_NEXT: Int32 = 17
let NX_KEYTYPE_PREVIOUS: Int32 = 18
func CGPreflightScreenCaptureAccess() -> Bool { true }

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
}
@MainActor final class AppLauncher {
    static let shared = AppLauncher()
    @discardableResult func launch(bundleID: String) async -> Bool { true }
    func activateAndWait(bundleID: String, timeout: TimeInterval = 1.0, settleDelay: TimeInterval = 0.08) async {}
}
@MainActor final class ContextObserver {
    static let shared = ContextObserver()
    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {}
    func removeConnection(id: UUID) {}
    func hasAction(id: String) -> Bool { true }
    func performAction(id: String) {}
}
@MainActor final class ActiveAppMonitor {
    static let shared = ActiveAppMonitor()
    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {}
    func removeConnection(id: UUID) {}
}
@MainActor final class RunningAppMonitor {
    static let shared = RunningAppMonitor()
    func addConnection(_ handle: LoomConnectionHandle, id: UUID) {}
    func removeConnection(id: UUID) {}
}
@MainActor final class MirrorStreamService {
    static let shared = MirrorStreamService()
    func start(subscriberID: UUID, handle: LoomConnectionHandle, fps: Int, maxWidth: Int, displayID: UInt32?) async {}
    func stop(subscriberID: UUID) async {}
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
final class NSWorkspace: @unchecked Sendable {
    static let shared = NSWorkspace()
    let notificationCenter = NotificationCenter()
    static let activeSpaceDidChangeNotification = Notification.Name("activeSpaceDidChange")
}

// MARK: iOS
func CACurrentMediaTime() -> Double { 0 }
enum TrackpadGestureKind { enum ThreeFingerDirection { case left, right, up, down } }
