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
        .package(path: "../StoatModels"),
        .package(path: "../StoatAPI")
    ],
    targets: [
        .target(name: "StoatRealtime", dependencies: ["StoatModels", "StoatAPI"]),
        .testTarget(
            name: "StoatRealtimeTests",
            dependencies: ["StoatRealtime"],
            resources: [.process("Fixtures")]
        )
    ]
)
