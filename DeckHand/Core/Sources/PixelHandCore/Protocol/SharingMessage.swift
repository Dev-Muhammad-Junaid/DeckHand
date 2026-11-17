//
//  SharingMessage.swift
//  PixelHandCore
//
//  Domain: sharing. Clipboard sync (S10) and, later, files and links
//  between paired devices. Reserved: no messages yet.
//
//  When the first case lands, delete the hand-written `Codable` below and
//  let Swift synthesize it like the other domains, then add its golden
//  fixture. Large payloads go through Loom's transfer engine, not this
//  envelope.
//

import Foundation

public enum SharingMessage: Sendable, Equatable {}

extension SharingMessage: Codable {
    public init(from decoder: Decoder) throws {
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "No sharing messages are defined in protocol version \(PixelHandProtocol.version)"
        ))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {}
    }
}
