//
//  DiagnosticsMessage.swift
//  PixelHandCore
//
//  Domain: diagnostics. Connection and stream statistics shared between the
//  two ends (for example S6's stats line), and debug reports. Reserved: no
//  messages yet.
//
//  When the first case lands, delete the hand-written `Codable` below and
//  let Swift synthesize it like the other domains, then add its golden
//  fixture.
//

import Foundation

public enum DiagnosticsMessage: Sendable, Equatable {}

extension DiagnosticsMessage: Codable {
    public init(from decoder: Decoder) throws {
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "No diagnostics messages are defined in protocol version \(PixelHandProtocol.version)"
        ))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {}
    }
}
