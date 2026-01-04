// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MixBridgeDomain",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MixBridgeDomain",
            targets: ["MixBridgeDomain"]
        ),
    ],
    targets: [
        .target(
            name: "MixBridgeDomain",
            path: "Sources"
        ),
    ]
)
