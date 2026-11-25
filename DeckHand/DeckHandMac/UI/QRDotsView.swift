//
//  QRDotsView.swift
//  DeckHandMac – UI
//
//  A QR code drawn in the app's dots (`06-Pixel-Identity.md` §4 "Pairing
//  code"): data modules are round dots, the three finder squares stay
//  square so scanners still lock on, and the icon's hand tile sits on the
//  centre module, inside level H's error correction. The cleared
//  centre and finder rules are Core's `QRDotPlan`.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code's modules, row by row from the top.
struct QRMatrix: Equatable {
    let size: Int
    let dark: [Bool]

    subscript(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < size, y < size else { return false }
        return dark[y * size + x]
    }

    /// Level H (30 %) so the centre tile never costs a scan.
    static func make(_ text: String) -> QRMatrix? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }

        // One pixel per module. A bitmap context's memory starts at the
        // image's top row, so rows come out top first.
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        // Trim the quiet zone, whatever Core Image put there.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxX - minX == maxY - minY else { return nil }
        let size = maxX - minX + 1
        var dark = [Bool](repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                dark[y * size + x] = pixels[(y + minY) * width + (x + minX)] < 128
            }
        }
        var matrix = QRMatrix(size: size, dark: dark)
        // Belt and braces: the finder-free corner must be bottom-right. If
        // the rows came out bottom first, flip them back.
        if !matrix.hasFinder(atX: 0, y: size - 7), matrix.hasFinder(atX: size - 7, y: size - 7) {
            matrix = matrix.flippedVertically()
        }
        return matrix
    }

    /// Whether a finder's dark 7-module outer ring starts at (x, y).
    func hasFinder(atX x: Int, y: Int) -> Bool {
        (0..<7).allSatisfy { self[x + $0, y] && self[x + $0, y + 6] && self[x, y + $0] && self[x + 6, y + $0] }
    }

    func flippedVertically() -> QRMatrix {
        var flipped = [Bool](repeating: false, count: dark.count)
        for y in 0..<size {
            for x in 0..<size { flipped[y * size + x] = self[x, size - 1 - y] }
        }
        return QRMatrix(size: size, dark: flipped)
    }
}

struct QRDotsView: View {
    let matrix: QRMatrix
    var side: CGFloat = 184
    /// Light quiet zone around the code, in modules.
    var quietModules = 2

    var body: some View {
        let matrix = self.matrix
        let n = matrix.size
        let module = side / CGFloat(n + 2 * quietModules)
        let inset = module * CGFloat(quietModules)
        let ink = PixelHandTheme.Brand.screen

        ZStack {
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .fill(Color.white)
            Canvas { context, _ in
                for y in 0..<n {
                    for x in 0..<n {
                        let rect = CGRect(
                            x: inset + CGFloat(x) * module,
                            y: inset + CGFloat(y) * module,
                            width: module, height: module
                        )
                        switch QRDotPlan.module(x: x, y: y, modules: n, dark: matrix[x, y]) {
                        case .empty, .cleared:
                            continue
                        case .finder:
                            // Slight overlap so neighbouring squares join.
                            context.fill(Path(rect.insetBy(dx: -0.25, dy: -0.25)), with: .color(ink))
                        case .dot:
                            let d = module * 0.86
                            context.fill(
                                Path(ellipseIn: CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)),
                                with: .color(ink)
                            )
                        }
                    }
                }
            }
            // The icon's hand tile, a whole odd number of modules placed on
            // the centre module's centre (OR-10): it used to be sized from
            // the cleared square less a module and centred by its canvas,
            // which left the art off the code's centre.
            if let tile = QRCentreTile.frame(modules: n, moduleSide: Double(module), quietModules: quietModules) {
                let centre = CGFloat(QRCentreTile.centreModuleCentre(modules: n, moduleSide: Double(module), quietModules: quietModules))
                MacHandTile(size: CGFloat(tile.side))
                    .position(x: centre, y: centre)
            }
        }
        .frame(width: side, height: side)
        // A light plate in both appearances: scanners need dark on light.
        .environment(\.colorScheme, .light)
        .accessibilityElement()
        .accessibilityLabel("Pairing QR code")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("ph.mac.pairingQRCode")
        .accessibilityHint("Scan it with the camera in Pixel Hand on your iPhone or iPad.")
    }
}
