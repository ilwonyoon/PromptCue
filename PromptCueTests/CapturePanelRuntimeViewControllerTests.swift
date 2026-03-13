import Foundation
import PromptCueCore
import XCTest
@testable import Prompt_Cue

@MainActor
final class CapturePanelRuntimeViewControllerTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testExternalDraftResetCancelsPendingDraftSync() {
        let model = makeModel()
        model.draftText = "Persist me"

        let controller = CapturePanelRuntimeViewController(model: model)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: AppUIConstants.capturePanelWidth, height: 320)
        controller.view.layoutSubtreeIfNeeded()
        controller.prepareForPresentation()

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: AppUIConstants.capturePanelWidth,
                height: controller.currentPreferredPanelHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.layoutIfNeeded()
        window.layoutIfNeeded()

        controller.debugEditorText = "Persist me"
        controller.debugScheduleDraftSync("Persist me")

        model.draftText = ""
        drainMainQueue(seconds: 0.25)

        XCTAssertEqual(model.draftText, "")
        XCTAssertEqual(controller.debugEditorText, "")
    }

    func testInlineTagGhostShowsMostCommonSuggestionForBareHash() throws {
        let model = makeModel(
            cards: [
                makeTaggedCard(text: "First", tags: ["hashtag"]),
                makeTaggedCard(text: "Second", tags: ["hashtag"]),
                makeTaggedCard(text: "Third", tags: ["hello"]),
            ]
        )

        let controller = makePreparedController(model: model)
        controller.debugApplyEditorText("#", selectedLocation: 1)

        XCTAssertEqual(controller.debugInlineCompletionSuffix, "hashtag")
        XCTAssertTrue(controller.debugIsInlineCompletionVisible)
    }

    func testInlineTagGhostShowsRemainingSuffixForPrefixMatch() throws {
        let model = makeModel(
            cards: [
                makeTaggedCard(text: "First", tags: ["hashtag_extension"]),
                makeTaggedCard(text: "Second", tags: ["hello"]),
            ]
        )

        let controller = makePreparedController(model: model)
        controller.debugApplyEditorText("#h", selectedLocation: 2)

        XCTAssertEqual(controller.debugInlineCompletionSuffix, "ashtag_extension")
        XCTAssertTrue(controller.debugIsInlineCompletionVisible)
    }

    private func makeModel(cards: [CaptureCard] = []) -> AppModel {
        let store = CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite"))
        if !cards.isEmpty {
            try? store.save(cards)
        }

        return AppModel(
            cardStore: store,
            attachmentStore: AttachmentStore(
                baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
            ),
            recentScreenshotCoordinator: TestRuntimeRecentScreenshotCoordinator()
        )
    }

    private func makePreparedController(model: AppModel) -> CapturePanelRuntimeViewController {
        model.start()

        let controller = CapturePanelRuntimeViewController(model: model)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: AppUIConstants.capturePanelWidth, height: 320)
        controller.view.layoutSubtreeIfNeeded()
        controller.prepareForPresentation()

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: AppUIConstants.capturePanelWidth,
                height: controller.currentPreferredPanelHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.layoutIfNeeded()
        window.layoutIfNeeded()
        return controller
    }

    private func makeTaggedCard(text: String, tags: [String]) -> CaptureCard {
        CaptureCard(
            id: UUID(),
            text: text,
            tags: tags.compactMap { CaptureTag(rawValue: $0) },
            createdAt: Date(),
            sortOrder: Date().timeIntervalSinceReferenceDate
        )
    }

    private func drainMainQueue(seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

@MainActor
private final class TestRuntimeRecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var state: RecentScreenshotState = .idle
    var onStateChange: ((RecentScreenshotState) -> Void)?

    func start() {}
    func stop() {}
    func prepareForCaptureSession() {}
    func refreshNow() {}
    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
    func suspendExpiration() {}
    func resumeExpiration() {}
}
