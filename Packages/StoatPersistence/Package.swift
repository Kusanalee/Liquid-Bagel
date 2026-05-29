// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StoatPersistence",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StoatPersistence", targets: ["StoatPersistence"])
    ],
    dependencies: [
        .package(path: "../StoatModels")
    ],
    targets: [
        .target(name: "StoatPersistence", dependencies: ["StoatModels"]),
        .testTarget(name: "StoatPersistenceTests", dependencies: ["StoatPersistence"])
    ]
)
