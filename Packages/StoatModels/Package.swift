// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StoatModels",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StoatModels", targets: ["StoatModels"])
    ],
    targets: [
        .target(name: "StoatModels"),
        .testTarget(name: "StoatModelsTests", dependencies: ["StoatModels"])
    ]
)
