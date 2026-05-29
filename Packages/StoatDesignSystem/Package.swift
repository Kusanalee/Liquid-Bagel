// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StoatDesignSystem",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StoatDesignSystem", targets: ["StoatDesignSystem"])
    ],
    targets: [
        .target(name: "StoatDesignSystem"),
        .testTarget(name: "StoatDesignSystemTests", dependencies: ["StoatDesignSystem"])
    ]
)
