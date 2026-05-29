// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StoatAPI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StoatAPI", targets: ["StoatAPI"])
    ],
    dependencies: [
        .package(path: "../StoatModels")
    ],
    targets: [
        .target(name: "StoatAPI", dependencies: ["StoatModels"]),
        .testTarget(name: "StoatAPITests", dependencies: ["StoatAPI"])
    ]
)
