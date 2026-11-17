// swift-tools-version: 6.0
//
//  Best-effort Linux type check for app files that cloud sessions can't
//  compile with Xcode. See run.sh.
//
import PackageDescription

let package = Package(
    name: "AppTypeCheck",
    dependencies: [.package(path: "../../Core")],
    targets: [
        .target(
            name: "AppTypeCheck",
            dependencies: [.product(name: "PixelHandCore", package: "Core")],
            path: "Work"
        ),
    ]
)
