// swift-tools-version: 6.0
//
//  PixelHandCore: the platform-independent logic shared by the Pixel Hand
//  Mac and iOS apps. Foundation only: no Loom, SwiftUI, AppKit, UIKit,
//  CoreGraphics or CryptoKit, so it builds and tests on Linux.
//
//      swift test --package-path DeckHand/Core
//
//  This is a separate package from the Loom package at the repository root,
//  so Loom stays product-agnostic.
//

import PackageDescription

let package = Package(
    name: "PixelHandCore",
    platforms: [
        .macOS(.v14),
        .iOS("17.4"),
    ],
    products: [
        .library(name: "PixelHandCore", targets: ["PixelHandCore"]),
    ],
    targets: [
        .target(name: "PixelHandCore"),
        .testTarget(
            name: "PixelHandCoreTests",
            dependencies: ["PixelHandCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
