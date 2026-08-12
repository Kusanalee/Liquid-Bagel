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
        .package(path: "../StoatUI"),
        .package(path: "../StoatVoice")
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
                "StoatUI",
                "StoatVoice"
            ]
        ),
        .testTarget(name: "StoatFeaturesTests", dependencies: ["StoatFeatures", "StoatAPI", "StoatRealtime", "StoatVoice"])
    ]
)
