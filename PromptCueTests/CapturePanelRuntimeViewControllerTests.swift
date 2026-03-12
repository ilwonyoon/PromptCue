import Foundation
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

    private func makeModel() -> AppModel {
        AppModel(
            cardStore: CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")),
            attachmentStore: AttachmentStore(
                baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
            ),
            recentScreenshotCoordinator: TestRuntimeRecentScreenshotCoordinator()
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
