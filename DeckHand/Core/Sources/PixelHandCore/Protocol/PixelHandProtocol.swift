//
//  PixelHandProtocol.swift
//  PixelHandCore
//
//  The app protocol's version, and how a device announces it before anyone
//  connects.
//
//  Two versions are in play on every connection:
//
//  - Loom's own `Loom.protocolVersion`, in the Bonjour TXT key `proto`.
//    Loom's handshake refuses a mismatch.
//  - This app protocol's `PixelHandProtocol.version`, in the TXT key
//    `ph-proto`. Every `ControlMessage` carries it in its envelope (`v`),
//    and a message with any other version fails to decode.
//
//  `PeerCompatibility` compares both before dialling, so the picker can say
//  "Please update Pixel Hand on your Mac" instead of connecting and then
//  dropping every message.
//
//  Rules for changing the protocol are in `Core/PROTOCOL.md`.
//

import Foundation

public enum PixelHandProtocol {
    /// The wire version this build speaks.
    ///
    /// - 1: the flat `ControlMessage` before the foundation work (no
    ///   envelope, no version field, never advertised).
    /// - 2: one envelope over per-domain messages, typed actions with
    ///   receipts, `hostStatus`, `mirror.error`.
    /// - 3: `session.tick` (Wi-Fi keep-alive) and `session.link(kind:)`.
    /// - 4: `system.displayState` (displays, Spaces, pointer display) and
    ///   `system.lockState`; `RefusalReason.macLocked`.
    /// - 5: mirror frames and the cursor move to the binary mirror stream
    ///   (`mirror.frame` removed); `diagnostics` carries mirror stats.
    /// - 6: HEVC mirror (S5): `mirror.start` gains `codec`, new
    ///   `mirror.requestKeyFrame`; the `hevc*` binary frame kinds are used.
    /// - 7: `input.typeText`, `input.mouseDown` / `mouseUp` (click-drag);
    ///   `sharing` domain for clipboard text.
    /// - 8: persistent pairing (S4): `pairing.submitCode`, `codeResult`,
    ///   `pairedStatus` and `forget`.
    /// - 9: single-window mirror (S14): `mirror.start` gains `windowID`.
    /// - 10: remote access over a VPN (S15): `session.remoteHosts`.
    /// - 11: the Mac's sound while mirroring (S17): `mirror.audio(enabled:)`,
    ///   `mirror.audioError`, the `audioFormat` / `audioPacket` frames on
    ///   `PixelHandStream.audio`, audio fields in the mirror stats.
    /// - 12: Deck 2 actions (`menuCommand`, `macShortcut`, `sequence`).
    /// - 13: transfers (S1): `sharing.transferStatus`; bytes through Loom's
    ///   transfer engine with a `TransferManifest` in the offer.
    public static let version = 13

    /// Bonjour TXT key carrying `version`. Short, because TXT keys should
    /// stay under 9 bytes.
    public static let advertisementKey = "ph-proto"

    /// What each app passes as `LoomContainerConfiguration.advertisementMetadata`.
    public static var advertisementMetadata: [String: String] {
        [advertisementKey: String(version)]
    }

    /// The app protocol version a peer advertised, or `nil` when it didn't
    /// say (a build from before version 2, or a peer seen only through a
    /// source that carries no TXT record).
    public static func advertisedVersion(in metadata: [String: String]) -> Int? {
        guard let raw = metadata[advertisementKey]?.trimmingCharacters(in: .whitespaces),
              let value = Int(raw), value > 0 else { return nil }
        return value
    }
}

/// Everything that can go wrong decoding a `ControlMessage` envelope.
public enum ProtocolError: Error, Equatable, Sendable {
    /// The envelope's `v` is not this build's `PixelHandProtocol.version`.
    case unsupportedVersion(Int)
    /// No known domain key in the envelope.
    case unknownDomain
    /// More than one domain key in the envelope.
    case multipleDomains([String])
    /// The encoded message is larger than the receiver accepts.
    case messageTooLarge(bytes: Int, limit: Int)
}

/// Size limits applied to messages from the network.
public enum ProtocolLimits {
    /// Largest encoded message the Mac accepts from a remote. Remotes only
    /// send small requests and input; screenshots and frames travel the
    /// other way.
    public static let maxRemoteMessageBytes = 256 * 1024
    /// Longest string field accepted from a remote.
    public static let maxStringLength = 64 * 1024
    /// Most elements accepted in an array from a remote.
    public static let maxArrayCount = 5_000
    /// Most keys in one chord. Real chords have at most 6.
    public static let maxChordKeys = 16
}
