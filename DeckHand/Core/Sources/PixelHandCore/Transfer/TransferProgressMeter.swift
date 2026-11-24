//
//  TransferProgressMeter.swift
//  PixelHandCore
//
//  S1: progress as both apps show it: fraction, a smoothed rate and the
//  time left, from the byte counts Loom's progress events report.
//

import Foundation

public struct TransferProgressMeter: Equatable, Sendable {
    public let totalBytes: UInt64
    public private(set) var bytes: UInt64
    /// Smoothed bytes per second; `nil` until two samples are far enough
    /// apart.
    public private(set) var bytesPerSecond: Double?
    private var lastSampleAt: TimeInterval?
    private var lastSampleBytes: UInt64

    /// Weight of the newest rate sample.
    static let smoothing = 0.3
    /// Samples closer than this are folded into the next one.
    static let minInterval: TimeInterval = 0.25

    public init(totalBytes: UInt64, startingAt bytes: UInt64 = 0) {
        self.totalBytes = totalBytes
        self.bytes = min(bytes, totalBytes)
        self.lastSampleBytes = self.bytes
    }

    public var fraction: Double {
        guard totalBytes > 0 else { return bytes > 0 ? 1 : 0 }
        return min(1, Double(bytes) / Double(totalBytes))
    }

    /// Records `bytes` transferred so far at `time` (seconds, any clock).
    public mutating func update(bytes newBytes: UInt64, at time: TimeInterval) {
        bytes = min(newBytes, totalBytes)
        guard let last = lastSampleAt else {
            lastSampleAt = time
            lastSampleBytes = bytes
            return
        }
        let interval = time - last
        guard interval >= Self.minInterval else { return }
        // A resume can move the count backwards; restart the rate then.
        guard bytes >= lastSampleBytes else {
            lastSampleAt = time
            lastSampleBytes = bytes
            bytesPerSecond = nil
            return
        }
        let sample = Double(bytes - lastSampleBytes) / interval
        bytesPerSecond = bytesPerSecond.map { $0 + Self.smoothing * (sample - $0) } ?? sample
        lastSampleAt = time
        lastSampleBytes = bytes
    }

    /// Seconds left at the current rate; `nil` while unknown.
    public var secondsLeft: Double? {
        guard let rate = bytesPerSecond, rate > 1 else { return nil }
        return Double(totalBytes - bytes) / rate
    }

    /// "12.4 MB of 200 MB · 8 s left" (time only once known).
    public var caption: String {
        var text = "\(Self.size(bytes)) of \(Self.size(totalBytes))"
        if let left = secondsLeft, bytes < totalBytes {
            text += " · " + Self.duration(left) + " left"
        }
        return text
    }

    /// A byte count the way Finder shows it (decimal units).
    public static func size(_ bytes: UInt64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        if bytes < 1000 { return bytes == 1 ? "1 byte" : "\(bytes) bytes" }
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let rounded = value < 10 ? (value * 10).rounded() / 10 : value.rounded()
        let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "\(number) \(units[unit])"
    }

    /// "8 s", "3 min", "1 h 5 min".
    public static func duration(_ seconds: Double) -> String {
        let s = max(1, Int(seconds.rounded()))
        if s < 60 { return "\(s) s" }
        let minutes = (s + 30) / 60
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}
