// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StoatRealtime",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StoatRealtime", targets: ["StoatRealtime"])
    ],
    dependencies: [
        .package(path: "../StoatModels")
    ],
    targets: [
        .target(name: "StoatRealtime", dependencies: ["StoatModels"]),
        .testTarget(name: "StoatRealtimeTests", dependencies: ["StoatRealtime"])
    ]
)
