//
//  ControlMessage.swift
//  PixelHandCore
//
//  The one envelope every message between the Mac and a remote travels in.
//
//  On the wire a message is a JSON object with the protocol version and
//  exactly one domain key:
//
//      {"input":{"mouseDelta":{"dx":1.5,"dy":-2}},"v":2}
//
//  Each domain's cases live in their own file (`InputMessage.swift`,
//  `MirrorMessage.swift`, …) and use Swift's synthesized `Codable`, so a
//  lane adds a message by adding a case to its own domain file, plus a
//  golden fixture. This file only changes when a whole new domain appears.
//
//  Bulk binary data (mirror video, later) does not belong here: it goes on
//  its own Loom stream with `BinaryFrameHeader` framing. See
//  `BinaryFrame.swift`.
//

import Foundation

public enum ControlMessage: Sendable, Equatable {
    /// Pointer, scroll, clicks, keys and media keys. Remote → Mac.
    case input(InputMessage)
    /// Mission Control, Spaces, Show Desktop and other system actions. Remote → Mac.
    case system(SystemMessage)
    /// Apps, the frontmost app and its interactable context. Both ways.
    case apps(AppsMessage)
    /// Shortcut chips, menu import, and tracked action runs with receipts. Both ways.
    case deck(DeckMessage)
    /// The live mirror and the display list. Both ways.
    case mirror(MirrorMessage)
    /// Screenshots, region and window captures. Both ways.
    case capture(CaptureMessage)
    /// The approval handshake (and persistent pairing later). Both ways.
    case pairing(PairingMessage)
    /// Liveness and what the host can do. Both ways.
    case session(SessionMessage)
    /// Clipboard text sync (S10); files later. Both ways.
    case sharing(SharingMessage)
    /// Stream stats (S6). Both ways.
    case diagnostics(DiagnosticsMessage)

    /// The domain this message belongs to.
    public var domain: ProtocolDomain {
        switch self {
        case .input: .input
        case .system: .system
        case .apps: .apps
        case .deck: .deck
        case .mirror: .mirror
        case .capture: .capture
        case .pairing: .pairing
        case .session: .session
        case .sharing: .sharing
        case .diagnostics: .diagnostics
        }
    }
}

/// The envelope's domain keys.
public enum ProtocolDomain: String, CaseIterable, Codable, Sendable {
    case input, system, apps, deck, mirror, capture, pairing, session, sharing, diagnostics
}

// MARK: - Codable

extension ControlMessage: Codable {
    private enum Key: String, CodingKey {
        case v
        case input, system, apps, deck, mirror, capture, pairing, session, sharing, diagnostics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let version = try c.decode(Int.self, forKey: .v)
        guard version == PixelHandProtocol.version else {
            throw ProtocolError.unsupportedVersion(version)
        }
        let domains = c.allKeys.filter { $0 != .v }
        guard let key = domains.first else { throw ProtocolError.unknownDomain }
        guard domains.count == 1 else {
            throw ProtocolError.multipleDomains(domains.map(\.stringValue).sorted())
        }
        switch key {
        case .input: self = .input(try c.decode(InputMessage.self, forKey: key))
        case .system: self = .system(try c.decode(SystemMessage.self, forKey: key))
        case .apps: self = .apps(try c.decode(AppsMessage.self, forKey: key))
        case .deck: self = .deck(try c.decode(DeckMessage.self, forKey: key))
        case .mirror: self = .mirror(try c.decode(MirrorMessage.self, forKey: key))
        case .capture: self = .capture(try c.decode(CaptureMessage.self, forKey: key))
        case .pairing: self = .pairing(try c.decode(PairingMessage.self, forKey: key))
        case .session: self = .session(try c.decode(SessionMessage.self, forKey: key))
        case .sharing: self = .sharing(try c.decode(SharingMessage.self, forKey: key))
        case .diagnostics: self = .diagnostics(try c.decode(DiagnosticsMessage.self, forKey: key))
        // `v` is filtered out above; listed so the switch is exhaustive.
        case .v: throw ProtocolError.unknownDomain
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(PixelHandProtocol.version, forKey: .v)
        switch self {
        case let .input(message): try c.encode(message, forKey: .input)
        case let .system(message): try c.encode(message, forKey: .system)
        case let .apps(message): try c.encode(message, forKey: .apps)
        case let .deck(message): try c.encode(message, forKey: .deck)
        case let .mirror(message): try c.encode(message, forKey: .mirror)
        case let .capture(message): try c.encode(message, forKey: .capture)
        case let .pairing(message): try c.encode(message, forKey: .pairing)
        case let .session(message): try c.encode(message, forKey: .session)
        case let .sharing(message): try c.encode(message, forKey: .sharing)
        case let .diagnostics(message): try c.encode(message, forKey: .diagnostics)
        }
    }
}
