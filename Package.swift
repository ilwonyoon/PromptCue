// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PromptCue",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "PromptCueCore",
            targets: ["PromptCueCore"]
        ),
    ],
    targets: [
        .target(
            name: "PromptCueCore",
            path: "Sources/PromptCueCore"
        ),
        .testTarget(
            name: "PromptCueCoreTests",
            dependencies: ["PromptCueCore"],
            path: "Tests/PromptCueCoreTests"
        ),
    ]
)
