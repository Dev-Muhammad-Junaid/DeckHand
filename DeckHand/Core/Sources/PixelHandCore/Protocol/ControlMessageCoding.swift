//
//  ControlMessageCoding.swift
//  PixelHandCore
//

import Foundation

/// Shared coding utilities for the `ControlMessage` wire format.
///
/// Both apps encode and decode every message with these two instances, so
/// the Mac and the remote can't drift on encoder configuration. At 120 Hz
/// input rates a fresh `JSONDecoder` per frame is measurable allocator
/// churn on the hottest path in the app. Encode and decode state is per
/// call, so sharing them is safe.
public enum ControlMessageCoding {
    /// One `JSONEncoder` reused for every outbound `ControlMessage`.
    /// Sorted keys make the bytes deterministic on every platform (Linux's
    /// Foundation otherwise orders keys differently from run to run), which
    /// the golden fixtures and byte-level tests rely on.
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    /// One `JSONDecoder` reused for every inbound `ControlMessage`.
    public static let decoder = JSONDecoder()
}
