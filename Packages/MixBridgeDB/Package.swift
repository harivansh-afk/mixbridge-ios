// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MixBridgeDB",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MixBridgeDB",
            targets: ["MixBridgeDB"]
        ),
    ],
    dependencies: [
        .package(path: "../MixBridgeDomain"),
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "7.0.0")),
    ],
    targets: [
        .target(
            name: "MixBridgeDB",
            dependencies: [
                "MixBridgeDomain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources"
        ),
    ]
)
