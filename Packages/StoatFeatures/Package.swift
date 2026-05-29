// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StoatFeatures",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StoatFeatures", targets: ["StoatFeatures"])
    ],
    dependencies: [
        .package(path: "../StoatAPI"),
        .package(path: "../StoatDesignSystem"),
        .package(path: "../StoatModels"),
        .package(path: "../StoatPersistence"),
        .package(path: "../StoatRealtime"),
        .package(path: "../StoatUI")
    ],
    targets: [
        .target(
            name: "StoatFeatures",
            dependencies: [
                "StoatAPI",
                "StoatDesignSystem",
                "StoatModels",
                "StoatPersistence",
                "StoatRealtime",
                "StoatUI"
            ]
        ),
        .testTarget(name: "StoatFeaturesTests", dependencies: ["StoatFeatures", "StoatAPI", "StoatRealtime"])
    ]
)
