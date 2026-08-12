// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StoatVoice",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StoatVoice", targets: ["StoatVoice"])
    ],
    dependencies: [
        .package(path: "../StoatModels"),
        // Official LiveKit Swift SDK. The backend's real-time voice transport is confirmed to be
        // LiveKit (see StoatConfig.features.livekit), so this is the SDK that actually matches
        // what the server speaks rather than a hand-rolled WebRTC/signaling stack.
        .package(url: "https://github.com/livekit/client-sdk-swift.git", .upToNextMajor(from: "2.16.0"))
    ],
    targets: [
        .target(
            name: "StoatVoice",
            dependencies: [
                "StoatModels",
                .product(name: "LiveKit", package: "client-sdk-swift")
            ]
        ),
        .testTarget(name: "StoatVoiceTests", dependencies: ["StoatVoice"])
    ]
)
