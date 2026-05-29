// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StoatUI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StoatUI", targets: ["StoatUI"])
    ],
    dependencies: [
        .package(path: "../StoatModels"),
        .package(path: "../StoatDesignSystem")
    ],
    targets: [
        .target(name: "StoatUI", dependencies: ["StoatModels", "StoatDesignSystem"]),
        .testTarget(name: "StoatUITests", dependencies: ["StoatUI"])
    ]
)
