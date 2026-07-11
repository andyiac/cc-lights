// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "cc-status",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "StatusLightCore",
            targets: ["StatusLightCore"]
        ),
        .executable(
            name: "ClaudeCodeStatusLight",
            targets: ["ClaudeCodeStatusLight"]
        ),
        .executable(
            name: "cc-lights",
            targets: ["CCLights"]
        )
    ],
    targets: [
        .target(
            name: "StatusLightCore"
        ),
        .executableTarget(
            name: "ClaudeCodeStatusLight",
            dependencies: ["StatusLightCore"]
        ),
        .executableTarget(
            name: "CCLights",
            dependencies: ["StatusLightCore"]
        ),
        .testTarget(
            name: "StatusLightCoreTests",
            dependencies: ["StatusLightCore"]
        )
    ]
)
