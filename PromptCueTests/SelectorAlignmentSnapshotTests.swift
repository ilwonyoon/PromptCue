import AppKit
import SwiftUI
import XCTest
@testable import Prompt_Cue
import PromptCueCore

@MainActor
final class SelectorAlignmentSnapshotTests: XCTestCase {
    func testRenderCaptureAndChooserSelectorAlignmentFixture() throws {
        let targets = sampleTargets
        let artifactURL = try makeArtifactURL(named: "selector-alignment.png")

        let fixture = VStack(spacing: AppUIConstants.captureChooserPanelVerticalSpacing) {
            SearchFieldSurface {
                SuggestedTargetChooserListView(
                    selectedTarget: targets[0],
                    highlightedTarget: targets[0],
                    availableTargets: targets,
                    emptyLabel: "Choose working app",
                    automaticTarget: targets[0],
                    isAutomaticSelectionActive: true,
                    isAutomaticHighlighted: true,
                    onHighlightTarget: nil,
                    onHighlightAutomaticTarget: nil,
                    controlWidth: AppUIConstants.captureSelectorControlWidth,
                    fixedWidth: nil,
                    onRefreshTargets: {},
                    onSelectTarget: { _ in },
                    onUseAutomaticTarget: {}
                )
            }
            .frame(width: AppUIConstants.captureSurfaceWidth, alignment: .center)

            SearchFieldSurface {
                SuggestedTargetOriginButton(
                    currentTarget: targets[0],
                    availableTargets: targets,
                    emptyLabel: "Choose working app",
                    onRefreshTargets: {},
                    onSelectTarget: { _ in },
                    automaticTarget: targets[0],
                    isAutomaticSelectionActive: true,
                    onUseAutomaticTarget: {},
                    onActivateInlineChooser: {},
                    controlWidth: AppUIConstants.captureSelectorControlWidth
                )
            }
            .frame(width: AppUIConstants.captureSurfaceWidth, alignment: .center)
        }
        .padding(24)
        .background(Color.black)
        .frame(width: 520, height: 620, alignment: .top)

        try render(fixture, size: CGSize(width: 520, height: 620), to: artifactURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))
    }

    private var sampleTargets: [CaptureSuggestedTarget] {
        [
            CaptureSuggestedTarget(
                appName: "Terminal",
                bundleIdentifier: "com.apple.Terminal",
                windowTitle: "Muninn",
                sessionIdentifier: "ttys001",
                currentWorkingDirectory: "/Users/ilwon/dev/Muninn",
                repositoryRoot: "/Users/ilwon/dev/Muninn",
                repositoryName: "Muninn",
                branch: "main",
                capturedAt: Date(timeIntervalSince1970: 1_000)
            ),
            CaptureSuggestedTarget(
                appName: "Terminal",
                bundleIdentifier: "com.apple.Terminal",
                windowTitle: "PromptCue-tag-priority-direct-send-to-apps",
                sessionIdentifier: "ttys002",
                currentWorkingDirectory: "/Users/ilwon/dev/PromptCue-tag-priority-direct-send-to-apps",
                repositoryRoot: "/Users/ilwon/dev/PromptCue-tag-priority-direct-send-to-apps",
                repositoryName: "PromptCue-tag-priority-direct-send-to-apps",
                branch: "feat/tag-priority-direct-send-to-apps",
                capturedAt: Date(timeIntervalSince1970: 1_001)
            ),
            CaptureSuggestedTarget(
                appName: "Terminal",
                bundleIdentifier: "com.apple.Terminal",
                windowTitle: "Turtle_neck_detector",
                sessionIdentifier: "ttys003",
                currentWorkingDirectory: "/Users/ilwon/dev/Turtle_neck_detector",
                repositoryRoot: "/Users/ilwon/dev/Turtle_neck_detector",
                repositoryName: "Turtle_neck_detector",
                branch: "main",
                capturedAt: Date(timeIntervalSince1970: 1_002)
            ),
            CaptureSuggestedTarget(
                appName: "Antigravity",
                bundleIdentifier: "com.google.antigravity",
                windowTitle: nil,
                sessionIdentifier: nil,
                currentWorkingDirectory: nil,
                repositoryRoot: nil,
                repositoryName: nil,
                branch: nil,
                capturedAt: Date(timeIntervalSince1970: 1_003),
                confidence: .low
            ),
            CaptureSuggestedTarget(
                appName: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                windowTitle: "PromptCue",
                sessionIdentifier: "tab-1",
                currentWorkingDirectory: nil,
                repositoryRoot: nil,
                repositoryName: nil,
                branch: nil,
                capturedAt: Date(timeIntervalSince1970: 1_004),
                confidence: .low
            ),
        ]
    }

    private func makeArtifactURL(named name: String) throws -> URL {
        let directoryURL: URL
        if ProcessInfo.processInfo.environment["PROMPTCUE_WRITE_SNAPSHOT_ARTIFACTS"] == "1" {
            let repoRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            directoryURL = repoRoot
                .appendingPathComponent(".artifacts", isDirectory: true)
                .appendingPathComponent("selector-alignment-verify", isDirectory: true)
        } else {
            directoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("promptcue-selector-alignment", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent(name)
    }

    private func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Failed to create bitmap for rendered view")
            return
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to encode PNG representation")
            return
        }

        try pngData.write(to: url)
    }
}
