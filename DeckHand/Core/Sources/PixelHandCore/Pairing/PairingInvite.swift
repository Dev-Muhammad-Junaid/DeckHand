//
//  PairingInvite.swift
//  PixelHandCore
//
//  What the Mac's pairing QR code holds (S4):
//
//      pixelhand://pair?v=1&code=1234567&mac=<device UUID>&key=<identity key ID>
//
//  - `code`: the `PairingCode` the Mac is showing.
//  - `mac`: the Mac's Loom device ID, so the remote can find it among the
//    Macs it has discovered and dial it without asking.
//  - `key`: the Mac's Loom identity key ID. Once connected, the remote
//    checks the Mac proved this key before sending the code, so a QR code
//    can't steer the code to a different machine that copied the device ID.
//
//  The same URL is what the camera app would open, but the app only reads
//  it from its own scanner; nothing registers the scheme.
//

import Foundation

public struct PairingInvite: Equatable, Sendable {
    public static let scheme = "pixelhand"
    public static let host = "pair"
    public static let formatVersion = 1
    /// Longest payload accepted from a scanner.
    public static let maxPayloadLength = 512

    public let code: PairingCode
    public let macDeviceID: UUID
    public let macIdentityKeyID: String

    public init?(code: PairingCode, macDeviceID: UUID, macIdentityKeyID: String) {
        guard TrustList.isValidIdentityKeyID(macIdentityKeyID) else { return nil }
        self.code = code
        self.macDeviceID = macDeviceID
        self.macIdentityKeyID = macIdentityKeyID
    }

    /// The text to put in the QR code.
    public var payload: String {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [
            URLQueryItem(name: "v", value: String(Self.formatVersion)),
            URLQueryItem(name: "code", value: code.digits),
            URLQueryItem(name: "mac", value: macDeviceID.uuidString),
            URLQueryItem(name: "key", value: macIdentityKeyID),
        ]
        return components.string ?? ""
    }

    /// Reads a scanned payload. `nil` for anything that isn't exactly a
    /// version-1 invite with a valid code, device ID and key ID. Duplicate
    /// or unknown query items are refused rather than guessed at.
    public init?(payload: String) {
        guard payload.utf8.count <= Self.maxPayloadLength,
              let components = URLComponents(string: payload),
              components.scheme?.lowercased() == Self.scheme,
              components.host?.lowercased() == Self.host,
              components.path.isEmpty || components.path == "/",
              let items = components.queryItems else { return nil }

        var values: [String: String] = [:]
        for item in items {
            guard ["v", "code", "mac", "key"].contains(item.name),
                  values[item.name] == nil,
                  let value = item.value else { return nil }
            values[item.name] = value
        }
        guard values["v"] == String(Self.formatVersion),
              let codeText = values["code"],
              let code = PairingCode(codeText),
              let macText = values["mac"],
              let macDeviceID = UUID(uuidString: macText),
              let key = values["key"] else { return nil }
        self.init(code: code, macDeviceID: macDeviceID, macIdentityKeyID: key)
    }
}
