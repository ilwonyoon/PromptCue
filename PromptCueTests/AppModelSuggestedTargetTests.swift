import Foundation
import PromptCueCore
import XCTest
@testable import Prompt_Cue

@MainActor
final class AppModelSuggestedTargetTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testBeginCaptureSessionDefaultsChooserSelectionToAutomaticTarget() {
        let provider = TestSuggestedTargetProvider(
            latestTarget: makeTarget(
                appName: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                repo: "Backtick",
                branch: "main"
            ),
            availableTargets: [
                makeTarget(
                    appName: "Cursor",
                    bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                    repo: "Backtick",
                    branch: "main"
                ),
                makeTarget(
                    appName: "Xcode",
                    bundleIdentifier: "com.apple.dt.Xcode",
                    repo: "PromptCue",
                    branch: "feature"
                ),
            ]
        )
        let model = makeModel(provider: provider)

        model.start()
        model.beginCaptureSession()

        XCTAssertEqual(model.captureSuggestedTargetChoiceCount, 2)
        XCTAssertEqual(model.captureChooserTarget?.workspaceLabel, "Backtick")
        XCTAssertEqual(model.selectedCaptureSuggestedTargetIndex, 0)
        XCTAssertTrue(model.isCaptureSuggestedTargetAutomatic)
    }

    func testBeginCaptureSessionRefreshesSuggestedTargets() {
        let provider = TestSuggestedTargetProvider(
            latestTarget: makeTarget(
                appName: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                repo: "Backtick",
                branch: "main"
            ),
            availableTargets: []
        )
        let model = makeModel(provider: provider)

        model.start()
        XCTAssertEqual(provider.refreshAvailableSuggestedTargetsCallCount, 0)

        model.beginCaptureSession()

        XCTAssertEqual(provider.refreshAvailableSuggestedTargetsCallCount, 1)
    }

    func testOpeningSuggestedTargetChooserRefreshesTargetsBeforeShowingChooser() {
        let automaticTarget = makeTarget(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            repo: "Backtick",
            branch: "main"
        )
        let provider = TestSuggestedTargetProvider(
            latestTarget: automaticTarget,
            availableTargets: [automaticTarget]
        )
        let model = makeModel(provider: provider)

        model.start()
        model.beginCaptureSession()
        XCTAssertEqual(provider.refreshAvailableSuggestedTargetsCallCount, 1)

        model.toggleCaptureSuggestedTargetChooser()

        XCTAssertTrue(model.isShowingCaptureSuggestedTargetChooser)
        XCTAssertEqual(provider.refreshAvailableSuggestedTargetsCallCount, 2)
    }

    func testSelectingExplicitSuggestedTargetPersistsMetadataOnSubmit() async {
        let automaticTarget = makeTarget(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            repo: "Backtick",
            branch: "main"
        )
        let explicitTarget = makeTarget(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            repo: "PromptCue",
            branch: "feature/chooser-port"
        )
        let provider = TestSuggestedTargetProvider(
            latestTarget: automaticTarget,
            availableTargets: [automaticTarget, explicitTarget]
        )
        let model = makeModel(provider: provider)

        model.start()
        model.beginCaptureSession()
        model.toggleCaptureSuggestedTargetChooser()

        XCTAssertTrue(model.moveCaptureSuggestedTargetSelection(by: 1))
        XCTAssertTrue(model.completeCaptureSuggestedTargetSelection())

        model.draftText = "Ship the chooser safely"
        let didSubmit = await model.submitCapture()

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(model.cards.first?.suggestedTarget, explicitTarget)
        XCTAssertFalse(model.isShowingCaptureSuggestedTargetChooser)
        XCTAssertEqual(model.captureChooserTarget, automaticTarget)
    }

    func testTerminalAutomaticTargetDeduplicatesMatchingAvailableTargetByCanonicalIdentity() {
        let automaticTarget = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "PromptCue — codex",
            sessionIdentifier: "window-482",
            capturedAt: Date(),
            confidence: .low
        )
        let matchingAvailableTarget = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "PromptCue — codex",
            sessionIdentifier: "window-482",
            capturedAt: Date(),
            confidence: .low
        )
        let secondTerminalTarget = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "FocusKnob — codex",
            sessionIdentifier: "window-973",
            capturedAt: Date(),
            confidence: .low
        )
        let provider = TestSuggestedTargetProvider(
            latestTarget: automaticTarget,
            availableTargets: [matchingAvailableTarget, secondTerminalTarget]
        )
        let model = makeModel(provider: provider)

        model.start()
        model.beginCaptureSession()

        XCTAssertEqual(model.captureSuggestedTargetChoiceCount, 2)
        XCTAssertEqual(model.captureChooserTarget?.canonicalIdentityKey, automaticTarget.canonicalIdentityKey)
    }

    func testTerminalSafeWindowIdentifiersKeepDuplicateWindowTitlesDistinctInChooser() {
        let automaticTarget = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "Backtick — codex",
            sessionIdentifier: "window-101",
            capturedAt: Date(),
            confidence: .low
        )
        let secondWindowTarget = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "Backtick — codex",
            sessionIdentifier: "window-202",
            capturedAt: Date(),
            confidence: .low
        )
        let provider = TestSuggestedTargetProvider(
            latestTarget: automaticTarget,
            availableTargets: [automaticTarget, secondWindowTarget]
        )
        let model = makeModel(provider: provider)

        model.start()
        model.beginCaptureSession()

        XCTAssertEqual(model.captureSuggestedTargetChoiceCount, 2)
        XCTAssertNotEqual(automaticTarget.canonicalIdentityKey, secondWindowTarget.canonicalIdentityKey)
    }

    func testCancelCaptureSuggestedTargetSelectionOnlyHidesChooser() {
        let automaticTarget = makeTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            repo: "Backtick",
            branch: "main"
        )
        let provider = TestSuggestedTargetProvider(
            latestTarget: automaticTarget,
            availableTargets: [automaticTarget]
        )
        let model = makeModel(provider: provider)

        model.start()
        model.beginCaptureSession()
        model.toggleCaptureSuggestedTargetChooser()

        XCTAssertTrue(model.cancelCaptureSuggestedTargetSelection())
        XCTAssertFalse(model.isShowingCaptureSuggestedTargetChooser)
        XCTAssertEqual(model.captureChooserTarget, automaticTarget)
    }

    func testAssignSuggestedTargetUpdatesExistingCard() async {
        let initialTarget = makeTarget(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            repo: "Backtick",
            branch: "main"
        )
        let reassignedTarget = makeTarget(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            repo: "PromptCue",
            branch: "feature/reassign"
        )
        let provider = TestSuggestedTargetProvider(
            latestTarget: initialTarget,
            availableTargets: [initialTarget, reassignedTarget]
        )
        let model = makeModel(provider: provider)

        model.start()
        model.draftText = "Card to reassign"
        let didSubmit = await model.submitCapture()

        XCTAssertTrue(didSubmit)
        guard let savedCard = model.cards.first else {
            return XCTFail("Expected saved card")
        }

        model.assignSuggestedTarget(reassignedTarget, to: savedCard)

        XCTAssertEqual(model.cards.first?.suggestedTarget, reassignedTarget)
    }

    private func makeModel(provider: TestSuggestedTargetProvider) -> AppModel {
        AppModel(
            cardStore: CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")),
            attachmentStore: AttachmentStore(baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments")),
            recentScreenshotCoordinator: SilentRecentScreenshotCoordinator(),
            suggestedTargetProvider: provider
        )
    }

    private func makeTarget(
        appName: String,
        bundleIdentifier: String,
        repo: String,
        branch: String
    ) -> CaptureSuggestedTarget {
        CaptureSuggestedTarget(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: "\(repo) window",
            sessionIdentifier: "\(appName)-1",
            currentWorkingDirectory: "/tmp/\(repo)",
            repositoryRoot: "/tmp/\(repo)",
            repositoryName: repo,
            branch: branch,
            capturedAt: Date(),
            confidence: .high
        )
    }
}

@MainActor
private final class TestSuggestedTargetProvider: SuggestedTargetProviding {
    var onChange: (() -> Void)?
    var latestTarget: CaptureSuggestedTarget?
    var targets: [CaptureSuggestedTarget]
    private(set) var refreshAvailableSuggestedTargetsCallCount = 0

    init(latestTarget: CaptureSuggestedTarget?, availableTargets: [CaptureSuggestedTarget]) {
        self.latestTarget = latestTarget
        self.targets = availableTargets
    }

    func start() {
        onChange?()
    }

    func stop() {}

    func currentFreshSuggestedTarget(relativeTo date: Date, freshness: TimeInterval) -> CaptureSuggestedTarget? {
        guard let latestTarget,
              latestTarget.isFresh(relativeTo: date, freshness: freshness) else {
            return nil
        }

        return latestTarget
    }

    func availableSuggestedTargets() -> [CaptureSuggestedTarget] {
        targets
    }

    func refreshAvailableSuggestedTargets() {
        refreshAvailableSuggestedTargetsCallCount += 1
        onChange?()
    }
}

@MainActor
private final class SilentRecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var state: RecentScreenshotState = .idle
    var onStateChange: ((RecentScreenshotState) -> Void)?

    func start() {}
    func stop() {}
    func prepareForCaptureSession() {}
    func refreshNow() {}
    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
}
