//
//  RemoteHost.swift
//  PixelHandCore
//
//  S15: an address a paired Mac can be reached at when Bonjour can't see
//  it (Tailscale, WireGuard, another VPN, or an SSH tunnel). Either typed
//  by the user in Settings › Remote Access or reported by the Mac itself
//  while both are on the same network (`session.remoteHosts`).
//
//  Everything that reaches Loom's overlay probe as a host goes through
//  `RemoteHost.parse(_:)` first: one host name or IP literal, nothing else.
//  No scheme, path, port, user name, spaces or zone, nothing that can't be
//  routed through a tunnel (loopback, link-local, multicast, unspecified).
//

import Foundation

public struct RemoteHost: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Longest DNS name (RFC 1035), and so the longest host accepted.
    public static let maxLength = 253

    /// The canonical form: lower case, no brackets, no trailing dot.
    public let value: String
    public let kind: Kind

    public var description: String { value }

    public enum Kind: String, Codable, Sendable {
        /// 100.64.0.0/10: Tailscale's addresses (shared address space).
        case tailscaleIPv4
        /// fd7a:115c:a1e0::/48: Tailscale's IPv6 range.
        case tailscaleIPv6
        /// A MagicDNS name under `.ts.net`.
        case magicDNS
        /// 10/8, 172.16/12, 192.168/16: a VPN or LAN address.
        case privateIPv4
        /// fc00::/7 outside Tailscale's range.
        case uniqueLocalIPv6
        /// Any other routable IP literal.
        case publicIP
        /// Any other DNS name.
        case hostname

        /// Addresses that only exist on an overlay network: a connection
        /// from one is never a LAN connection.
        public var isOverlay: Bool {
            self == .tailscaleIPv4 || self == .tailscaleIPv6 || self == .magicDNS
        }

        public var isIPLiteral: Bool {
            self != .magicDNS && self != .hostname
        }
    }

    public enum Rejection: Error, Equatable, Sendable {
        case empty
        case tooLong
        /// A scheme, path, query, port, user name, zone or space.
        case notAHost
        /// Not a valid IP literal or DNS name.
        case malformed
        /// 127/8, ::1, `localhost`.
        case loopback
        /// 169.254/16, fe80::/10: not routable through a tunnel.
        case linkLocal
        /// 0.0.0.0, ::, multicast, broadcast.
        case unusable

        /// One line for Settings.
        public var message: String {
            switch self {
            case .empty: "Enter a host name or IP address."
            case .tooLong: "That name is too long."
            case .notAHost: "Enter only the host, for example 100.101.102.103 or my-mac.tail1234.ts.net (no http://, port or path)."
            case .malformed: "That isn’t a valid host name or IP address."
            case .loopback: "That address points back at this device."
            case .linkLocal: "Link-local addresses (169.254.x.x, fe80::) only work on the same network."
            case .unusable: "That address can’t reach a Mac."
            }
        }
    }

    /// Validates and normalises one host. Surrounding spaces and one
    /// trailing dot are dropped, IPv6 brackets are removed, case folds.
    public static func parse(_ input: String) -> Result<RemoteHost, Rejection> {
        var host = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty { return .failure(.empty) }
        if host.utf8.count > maxLength + 2 { return .failure(.tooLong) }
        if host.hasPrefix("["), host.hasSuffix("]"), host.count > 2 {
            host = String(host.dropFirst().dropLast())
        }
        if host.hasSuffix("."), !host.hasSuffix("..") { host = String(host.dropLast()) }
        host = host.lowercased()
        if host.isEmpty { return .failure(.empty) }
        if host.utf8.count > maxLength { return .failure(.tooLong) }

        let forbidden: Set<Character> = ["/", "?", "#", "@", "%", "[", "]", "\\", " ", "\t", "\n", "\r", ",", ";", "\""]
        if host.contains(where: { forbidden.contains($0) }) || host.contains("://") {
            return .failure(.notAHost)
        }
        // Everything left must be ASCII: IDNs have to be typed as punycode.
        guard host.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }) else {
            return .failure(.malformed)
        }

        if host.contains(":") {
            // A colon with dots and no second colon is `host:port`.
            if host.filter({ $0 == ":" }).count == 1 { return .failure(.notAHost) }
            guard let groups = IPv6.parse(host) else { return .failure(.malformed) }
            return classifyIPv6(groups).map { RemoteHost(value: IPv6.format(groups), kind: $0) }
        }
        if let octets = IPv4.parse(host) {
            return classifyIPv4(octets).map { RemoteHost(value: octets.map(String.init).joined(separator: "."), kind: $0) }
        }
        // All digits and dots but not a valid quad (`1.2.3`, `300.1.1.1`).
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return .failure(.malformed) }
        guard isValidHostname(host) else { return .failure(.malformed) }
        if host == "localhost" || host.hasSuffix(".localhost") { return .failure(.loopback) }
        let kind: Kind = host.hasSuffix(".ts.net") ? .magicDNS : .hostname
        return .success(RemoteHost(value: host, kind: kind))
    }

    /// `parse` for callers that only need a yes/no.
    public init?(_ input: String) {
        guard case let .success(host) = Self.parse(input) else { return nil }
        self = host
    }

    private init(value: String, kind: Kind) {
        self.value = value
        self.kind = kind
    }

    /// Re-validates on decode, so a tampered store can't smuggle in a host
    /// `parse` would refuse.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch Self.parse(raw) {
        case let .success(host): self = host
        case let .failure(rejection):
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid remote host (\(rejection))"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }

    // MARK: - Address checks without parsing errors

    /// Whether `address` (as a socket reports it, `%zone` allowed) belongs
    /// to an overlay network (Tailscale's ranges). Used to tell a tunnel
    /// connection from a LAN one when the interface name isn't known.
    public static func isOverlayAddress(_ address: String?) -> Bool {
        guard let address else { return false }
        let h = LinkJudge.unscoped(address)
        if let octets = IPv4.parse(h) { return isTailscaleIPv4(octets) }
        if let mapped = IPv6.parse(h) {
            if let v4 = IPv6.mappedIPv4(mapped) { return isTailscaleIPv4(v4) }
            return isTailscaleIPv6(mapped)
        }
        return false
    }

    // MARK: - Classification

    private static func isTailscaleIPv4(_ o: [UInt8]) -> Bool {
        o[0] == 100 && (o[1] & 0xC0) == 64
    }

    private static func isTailscaleIPv6(_ g: [UInt16]) -> Bool {
        g[0] == 0xFD7A && g[1] == 0x115C && g[2] == 0xA1E0
    }

    private static func classifyIPv4(_ o: [UInt8]) -> Result<Kind, Rejection> {
        switch o[0] {
        case 127: return .failure(.loopback)
        case 0: return .failure(.unusable)
        case 224...255: return .failure(.unusable) // multicast, reserved, broadcast
        default: break
        }
        if o[0] == 169 && o[1] == 254 { return .failure(.linkLocal) }
        if isTailscaleIPv4(o) { return .success(.tailscaleIPv4) }
        if o[0] == 10 || (o[0] == 172 && (o[1] & 0xF0) == 16) || (o[0] == 192 && o[1] == 168) {
            return .success(.privateIPv4)
        }
        return .success(.publicIP)
    }

    private static func classifyIPv6(_ g: [UInt16]) -> Result<Kind, Rejection> {
        if g.allSatisfy({ $0 == 0 }) { return .failure(.unusable) }
        if g.dropLast().allSatisfy({ $0 == 0 }) && g[7] == 1 { return .failure(.loopback) }
        if let v4 = IPv6.mappedIPv4(g) { return classifyIPv4(v4) }
        if (g[0] & 0xFFC0) == 0xFE80 { return .failure(.linkLocal) }
        if (g[0] & 0xFF00) == 0xFF00 { return .failure(.unusable) }
        if isTailscaleIPv6(g) { return .success(.tailscaleIPv6) }
        if (g[0] & 0xFE00) == 0xFC00 { return .success(.uniqueLocalIPv6) }
        return .success(.publicIP)
    }

    private static func isValidHostname(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        for label in labels {
            guard (1...63).contains(label.utf8.count),
                  label.first != "-", label.last != "-",
                  label.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }) else {
                return false
            }
        }
        // The top-level label of a DNS name is never all digits.
        return !(labels.last?.allSatisfy(\.isNumber) ?? true)
    }
}

// MARK: - IP literal parsing (strict, no inet_pton: same answer on every platform)

enum IPv4 {
    /// Four decimal octets, no leading zeros (`010` is ambiguous: octal to
    /// some parsers), each 0–255.
    static func parse(_ s: String) -> [UInt8]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [UInt8] = []
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part.count == 1 || part.first != "0",
                  let value = UInt8(part) else { return nil }
            octets.append(value)
        }
        return octets
    }
}

enum IPv6 {
    /// Eight 16-bit groups. Accepts `::` once and a trailing dotted IPv4.
    static func parse(_ s: String) -> [UInt16]? {
        guard s.utf8.count <= 45, !s.isEmpty else { return nil }
        let halves = s.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }

        func groups(_ part: String, allowIPv4Tail: Bool) -> [UInt16]? {
            if part.isEmpty { return [] }
            var result: [UInt16] = []
            let fields = part.split(separator: ":", omittingEmptySubsequences: false)
            for (index, field) in fields.enumerated() {
                if allowIPv4Tail, index == fields.count - 1, field.contains(".") {
                    guard let v4 = IPv4.parse(String(field)) else { return nil }
                    result.append(UInt16(v4[0]) << 8 | UInt16(v4[1]))
                    result.append(UInt16(v4[2]) << 8 | UInt16(v4[3]))
                    continue
                }
                guard (1...4).contains(field.count), field.allSatisfy(\.isHexDigit),
                      let value = UInt16(field, radix: 16) else { return nil }
                result.append(value)
            }
            return result
        }

        if halves.count == 1 {
            guard let all = groups(halves[0], allowIPv4Tail: true), all.count == 8 else { return nil }
            return all
        }
        guard let head = groups(halves[0], allowIPv4Tail: false),
              let tail = groups(halves[1], allowIPv4Tail: true),
              head.count + tail.count <= 7 else { return nil }
        return head + Array(repeating: 0, count: 8 - head.count - tail.count) + tail
    }

    /// `::ffff:a.b.c.d`.
    static func mappedIPv4(_ g: [UInt16]) -> [UInt8]? {
        guard g[0...4].allSatisfy({ $0 == 0 }), g[5] == 0xFFFF else { return nil }
        return [UInt8(g[6] >> 8), UInt8(g[6] & 0xFF), UInt8(g[7] >> 8), UInt8(g[7] & 0xFF)]
    }

    /// RFC 5952 text: lower case, no leading zeros, the longest run of two
    /// or more zero groups as `::`.
    static func format(_ g: [UInt16]) -> String {
        var bestStart = -1, bestLength = 0, runStart = -1
        for i in 0...8 {
            if i < 8, g[i] == 0 {
                if runStart < 0 { runStart = i }
            } else if runStart >= 0 {
                let length = i - runStart
                if length > bestLength, length >= 2 { bestStart = runStart; bestLength = length }
                runStart = -1
            }
        }
        let hex = g.map { String($0, radix: 16) }
        guard bestStart >= 0 else { return hex.joined(separator: ":") }
        let head = hex[..<bestStart].joined(separator: ":")
        let tail = hex[(bestStart + bestLength)...].joined(separator: ":")
        return head + "::" + tail
    }
}
