//
//  AppIconEncoder.swift
//  DeckHandMac
//
//  App icons for the iPhone and iPad, with their transparency (owner
//  testing, build 24, OT-1). They used to go as 64 × 64 JPEG, which has no
//  alpha, so every icon sat on a white or black square in the dock.
//
//  Each icon is drawn into an sRGB bitmap with alpha at
//  `AppIconPolicy.pixelSide` (2× the dock's icon), then encoded as PNG and
//  as HEIC; Core's `AppIconPolicy.choose` keeps the smaller one that really
//  kept its alpha (the HEIC is decoded back to check: a writer without
//  alpha support drops it silently). An icon over the per-icon budget is
//  drawn again at the fallback size. Results are cached by the app's path
//  and modification date, so a rescan only encodes apps that changed.
//
//  The iOS side decodes with `UIImage(data:)` as before: PNG and HEIC both
//  decode there, and `InstalledAppInfo.iconData` is still plain `Data`, so
//  the protocol is unchanged.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum AppIconEncoder {
    /// Encoded icons by path, size and modification date. `NSCache` is
    /// thread-safe, so the window list can use it off the main actor.
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    /// The app's icon with transparency, at `pixelSide` pixels (falling
    /// back to `AppIconPolicy.fallbackPixelSide` when it's over budget), or
    /// `nil` when it can't be drawn.
    static func icon(for appURL: URL, pixelSide: Int = AppIconPolicy.pixelSide) -> Data? {
        let modified = (try? appURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let key = "\(appURL.path)|\(pixelSide)|\(modified)" as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }

        var data = encode(appURL, side: pixelSide)
        if let encoded = data, encoded.count > AppIconPolicy.maximumBytesPerIcon, pixelSide > AppIconPolicy.fallbackPixelSide {
            data = encode(appURL, side: AppIconPolicy.fallbackPixelSide) ?? encoded
        }
        if let data { cache.setObject(data as NSData, forKey: key, cost: data.count) }
        return data
    }

    // MARK: Drawing and encoding

    private static func encode(_ appURL: URL, side: Int) -> Data? {
        guard let image = render(appURL, side: side) else { return nil }
        var candidates: [(AppIconPolicy.Encoded, Data)] = []
        if let png = write(image, type: .png) {
            // PNG keeps the bitmap's alpha channel as drawn.
            candidates.append((AppIconPolicy.Encoded(format: .png, byteCount: png.count, keepsAlpha: true), png))
        }
        if let heic = write(image, type: .heic, quality: 0.8) {
            candidates.append((AppIconPolicy.Encoded(format: .heic, byteCount: heic.count, keepsAlpha: decodesWithAlpha(heic)), heic))
        }
        guard let chosen = AppIconPolicy.choose(candidates.map(\.0)) else { return nil }
        return candidates.first { $0.0 == chosen }?.1
    }

    /// The icon drawn into a clear sRGB bitmap with premultiplied alpha.
    private static func render(_ appURL: URL, side: Int) -> CGImage? {
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        // Ask for the representation closest to the pixel size (the icon
        // file has 16 … 1024 px renditions).
        var proposed = CGRect(x: 0, y: 0, width: side, height: side)
        let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
        guard let source = icon.cgImage(forProposedRect: &proposed, context: nil, hints: hints) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static func write(_ image: CGImage, type: UTType, quality: Double? = nil) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length > 0 else { return nil }
        return data as Data
    }

    /// Whether `data` decodes to an image with an alpha channel.
    private static func decodesWithAlpha(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return false }
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }
}
