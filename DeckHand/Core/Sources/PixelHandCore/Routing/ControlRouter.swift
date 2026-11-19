//
//  ControlRouter.swift
//  PixelHandCore
//
//  Sends each inbound `ControlMessage` to the handler for its domain. The
//  Mac builds one router with one handler per domain (all registered in
//  `DeckHandMac/Handlers/MacHandlers.swift`); each lane owns its handler
//  file and never edits the others.
//
//  Generic over the connection type so the routing itself is tested here
//  without Loom: the Mac uses `LoomConnectionHandle`, tests use a stand-in.
//

import Foundation

/// Handles every message of one domain.
@MainActor
public protocol DomainHandler<Message, Connection>: AnyObject {
    associatedtype Message: Sendable
    associatedtype Connection

    /// Handle one message that arrived on `connection`. Messages that only
    /// ever travel the other way are ignored.
    func handle(_ message: Message, from connection: Connection) async
}

@MainActor
public final class ControlRouter<Connection> {
    public let input: any DomainHandler<InputMessage, Connection>
    public let system: any DomainHandler<SystemMessage, Connection>
    public let apps: any DomainHandler<AppsMessage, Connection>
    public let deck: any DomainHandler<DeckMessage, Connection>
    public let mirror: any DomainHandler<MirrorMessage, Connection>
    public let capture: any DomainHandler<CaptureMessage, Connection>
    public let pairing: any DomainHandler<PairingMessage, Connection>
    public let session: any DomainHandler<SessionMessage, Connection>
    public let diagnostics: any DomainHandler<DiagnosticsMessage, Connection>

    public init(
        input: any DomainHandler<InputMessage, Connection>,
        system: any DomainHandler<SystemMessage, Connection>,
        apps: any DomainHandler<AppsMessage, Connection>,
        deck: any DomainHandler<DeckMessage, Connection>,
        mirror: any DomainHandler<MirrorMessage, Connection>,
        capture: any DomainHandler<CaptureMessage, Connection>,
        pairing: any DomainHandler<PairingMessage, Connection>,
        session: any DomainHandler<SessionMessage, Connection>,
        diagnostics: any DomainHandler<DiagnosticsMessage, Connection>
    ) {
        self.input = input
        self.system = system
        self.apps = apps
        self.deck = deck
        self.mirror = mirror
        self.capture = capture
        self.pairing = pairing
        self.session = session
        self.diagnostics = diagnostics
    }

    /// Hands `message` to its domain's handler and waits for it to return.
    /// Handlers start slow work in their own tasks, so this stays quick.
    public func route(_ message: ControlMessage, from connection: Connection) async {
        switch message {
        case let .input(m): await input.handle(m, from: connection)
        case let .system(m): await system.handle(m, from: connection)
        case let .apps(m): await apps.handle(m, from: connection)
        case let .deck(m): await deck.handle(m, from: connection)
        case let .mirror(m): await mirror.handle(m, from: connection)
        case let .capture(m): await capture.handle(m, from: connection)
        case let .pairing(m): await pairing.handle(m, from: connection)
        case let .session(m): await session.handle(m, from: connection)
        case let .diagnostics(m): await diagnostics.handle(m, from: connection)
        // Reserved domains: no messages exist yet. When one gets its first
        // case, add its handler above.
        case .sharing: break
        }
    }
}
