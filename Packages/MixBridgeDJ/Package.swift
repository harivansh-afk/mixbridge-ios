// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MixBridgeDJ",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MixBridgeDJ",
            targets: ["MixBridgeDJ"]
        )
    ],
    targets: [
        .target(
            name: "MixBridgeDJ",
            dependencies: []
        )
    ]
)
