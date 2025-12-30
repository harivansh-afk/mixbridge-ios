// swift-tools-version: 5.9
// MixbridgeMixCore - Pure Swift mix logic (no AVFoundation)

import PackageDescription

let package = Package(
    name: "MixbridgeMixCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "MixbridgeMixCore",
            targets: ["MixbridgeMixCore"]
        )
    ],
    targets: [
        .target(
            name: "MixbridgeMixCore",
            dependencies: [],
            path: "Sources/MixbridgeMixCore"
        ),
        .testTarget(
            name: "MixbridgeMixCoreTests",
            dependencies: ["MixbridgeMixCore"],
            path: "Tests/MixbridgeMixCoreTests"
        )
    ]
)
