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
        .executable(
            name: "BacktickMCP",
            targets: ["BacktickMCP"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "7.8.0"
        ),
    ],
    targets: [
        .target(
            name: "PromptCueCore",
            path: "Sources/PromptCueCore"
        ),
        .target(
            name: "BacktickMCPServer",
            dependencies: [
                "PromptCueCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: ".",
            exclude: [
                ".github",
                ".swiftpm",
                "AGENTS.md",
                "CLAUDE.md",
                "Config",
                "PromptCue.xcodeproj",
                "PromptCue/App",
                "PromptCue/Domain",
                "PromptCue/PromptCue.entitlements",
                "PromptCue/Resources",
                "PromptCue/UI",
                "PromptCue/Services/ClipboardFormatter.swift",
                "PromptCue/Services/CloudSyncControlling.swift",
                "PromptCue/Services/CloudSyncEngine.swift",
                "PromptCue/Services/HotKeyCenter.swift",
                "PromptCue/Services/ManagedScreenshotAccess.swift",
                "PromptCue/Services/RecentClipboardImageMonitor.swift",
                "PromptCue/Services/RecentScreenshotContracts.swift",
                "PromptCue/Services/RecentScreenshotCoordinator.swift",
                "PromptCue/Services/RecentScreenshotDirectoryObserver.swift",
                "PromptCue/Services/RecentScreenshotLocator.swift",
                "PromptCue/Services/RecentSuggestedAppTargetTracker.swift",
                "PromptCue/Services/ScreenshotAttachmentPersistencePolicy.swift",
                "PromptCue/Services/ScreenshotDirectoryResolver.swift",
                "PromptCue/Services/ScreenshotFolderAccess.swift",
                "PromptCue/Services/TransientScreenshotCache.swift",
                "PromptCueTests",
                "Sources/BacktickMCP",
                "Sources/PromptCueCore",
                "Tests",
                "docs",
                "project.yml",
                "scripts",
            ],
            sources: [
                "PromptCue/Services/AttachmentStore.swift",
                "PromptCue/Services/CardStore.swift",
                "PromptCue/Services/CopyEventStore.swift",
                "PromptCue/Services/PromptCueDatabase.swift",
                "PromptCue/Services/StackExecutionService.swift",
                "PromptCue/Services/StackReadService.swift",
                "PromptCue/Services/StackWriteService.swift",
                "Sources/BacktickMCPServer",
            ]
        ),
        .executableTarget(
            name: "BacktickMCP",
            dependencies: ["BacktickMCPServer"],
            path: "Sources/BacktickMCP"
        ),
        .testTarget(
            name: "PromptCueCoreTests",
            dependencies: ["PromptCueCore"],
            path: "Tests/PromptCueCoreTests"
        ),
        .testTarget(
            name: "BacktickMCPServerTests",
            dependencies: ["BacktickMCPServer"],
            path: "Tests/BacktickMCPServerTests"
        ),
    ]
)
