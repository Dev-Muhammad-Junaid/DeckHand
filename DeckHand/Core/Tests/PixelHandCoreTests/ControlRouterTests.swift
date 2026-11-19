//
//  ControlRouterTests.swift
//  PixelHandCoreTests
//
//  PH-005: the Mac's one dispatch switch became a router over per-domain
//  handlers. Every message must reach its own domain's handler, unchanged,
//  with the connection it came from, and no other handler.
//

import Foundation
import PixelHandCore
import Testing

/// A stand-in for `LoomConnectionHandle`.
private struct FakeConnection: Equatable {
    let id: Int
}

@MainActor
private final class Recorder<Message: Sendable>: DomainHandler {
    let domain: ProtocolDomain
    let log: RouteLog
    init(_ domain: ProtocolDomain, log: RouteLog) {
        self.domain = domain
        self.log = log
    }

    func handle(_ message: Message, from connection: FakeConnection) async {
        log.entries.append((domain, String(describing: message), connection))
    }
}

@MainActor
private final class RouteLog {
    var entries: [(ProtocolDomain, String, FakeConnection)] = []
}

@MainActor
@Suite struct ControlRouterTests {

    private func makeRouter(_ log: RouteLog) -> ControlRouter<FakeConnection> {
        ControlRouter(
            input: Recorder<InputMessage>(.input, log: log),
            system: Recorder<SystemMessage>(.system, log: log),
            apps: Recorder<AppsMessage>(.apps, log: log),
            deck: Recorder<DeckMessage>(.deck, log: log),
            mirror: Recorder<MirrorMessage>(.mirror, log: log),
            capture: Recorder<CaptureMessage>(.capture, log: log),
            pairing: Recorder<PairingMessage>(.pairing, log: log),
            session: Recorder<SessionMessage>(.session, log: log),
            sharing: Recorder<SharingMessage>(.sharing, log: log),
            diagnostics: Recorder<DiagnosticsMessage>(.diagnostics, log: log)
        )
    }

    /// The inner message, as the domain handler sees it.
    private func inner(_ message: ControlMessage) -> String {
        switch message {
        case let .input(m): String(describing: m)
        case let .system(m): String(describing: m)
        case let .apps(m): String(describing: m)
        case let .deck(m): String(describing: m)
        case let .mirror(m): String(describing: m)
        case let .capture(m): String(describing: m)
        case let .pairing(m): String(describing: m)
        case let .session(m): String(describing: m)
        case let .sharing(m): String(describing: m)
        case let .diagnostics(m): String(describing: m)
        }
    }

    @Test("Every message reaches its own domain's handler, once, with its connection")
    func everyMessageReachesItsHandler() async {
        for (index, sample) in ProtocolContractTests.samples.enumerated() {
            let log = RouteLog()
            let router = makeRouter(log)
            let connection = FakeConnection(id: index)
            await router.route(sample.message, from: connection)
            #expect(log.entries.count == 1, "\(sample.name)")
            guard let entry = log.entries.first else { continue }
            #expect(entry.0 == sample.message.domain, "\(sample.name)")
            #expect(entry.1 == inner(sample.message), "\(sample.name)")
            #expect(entry.2 == connection, "\(sample.name)")
        }
    }

    @Test("Messages are handled in the order they are routed")
    func orderIsKept() async {
        let log = RouteLog()
        let router = makeRouter(log)
        let messages: [ControlMessage] = [
            .session(.ping(seq: 1)),
            .input(.mouseDelta(dx: 1, dy: 1)),
            .input(.mouseClick(button: .left)),
            .system(.run(action: .showDesktop)),
        ]
        for message in messages {
            await router.route(message, from: FakeConnection(id: 0))
        }
        #expect(log.entries.map(\.0) == [.session, .input, .input, .system])
    }
}
