//
//  LoomConnectionHandle+ControlMessage.swift
//  Pixel Hand – Shared
//
//  Single canonical path for shipping a `ControlMessage` over a Loom
//  connection. The coders themselves live in PixelHandCore
//  (`ControlMessageCoding`), so both apps encode with the same
//  configuration, and the wire format stays under our control even if
//  Loom's default `send<T: Encodable>` overload changes.
//

import Foundation
import LoomKit

public extension LoomConnectionHandle {
    /// Encodes `message` with the shared Pixel Hand encoder and ships it
    /// on the default LoomKit message stream.
    ///
    /// Always prefer this over the generic `send<T: Encodable>` overload —
    /// the generic version constructs a fresh `JSONEncoder` per call, which
    /// (a) is wasteful at 120 Hz and (b) drifts away from the iOS/Mac
    /// inboxes that decode with their own configured `JSONDecoder`.
    func send(_ message: ControlMessage) async throws {
        let data = try ControlMessageCoding.encoder.encode(message)
        try await send(data)
    }
}
