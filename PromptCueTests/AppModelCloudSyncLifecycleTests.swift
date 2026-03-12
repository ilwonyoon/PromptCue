import Foundation
import XCTest
import PromptCueCore
@testable import Prompt_Cue

@MainActor
final class AppModelCloudSyncLifecycleTests: XCTestCase {
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

    func testStartDoesNotCreateCloudSyncEngineUntilSyncEnabled() async {
        let engine = RecordingCloudSyncEngine()
        var factoryCallCount = 0
        let model = makeModel(cloudSyncEngine: nil) {
            factoryCallCount += 1
            return engine
        }
        defer { model.stop() }

        model.start(startupMode: .deferredMaintenance)
        XCTAssertEqual(factoryCallCount, 0)

        model.setSyncEnabled(true)
        await Task.yield()

        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertEqual(engine.setupCallCount, 1)
        XCTAssertEqual(engine.fetchRemoteChangesCallCount, 1)
    }

    func testDisablingSyncStopsExistingCloudSyncEngine() {
        let engine = RecordingCloudSyncEngine()
        let model = makeModel(cloudSyncEngine: engine)
        defer { model.stop() }

        model.start(startupMode: .deferredMaintenance)
        model.setSyncEnabled(false)

        XCTAssertEqual(engine.stopCallCount, 1)
    }

    func testStopStopsExistingCloudSyncEngine() {
        let engine = RecordingCloudSyncEngine()
        let model = makeModel(cloudSyncEngine: engine)

        model.start(startupMode: .deferredMaintenance)
        model.stop()

        XCTAssertEqual(engine.stopCallCount, 1)
    }

    private func makeModel(
        cloudSyncEngine: (any CloudSyncControlling)?,
        cloudSyncEngineFactory: @escaping @MainActor () -> any CloudSyncControlling = { RecordingCloudSyncEngine() }
    ) -> AppModel {
        AppModel(
            cardStore: CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")),
            attachmentStore: AttachmentStore(
                baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
            ),
            recentScreenshotCoordinator: LifecycleTestRecentScreenshotCoordinator(),
            cloudSyncEngine: cloudSyncEngine,
            cloudSyncEngineFactory: cloudSyncEngineFactory
        )
    }
}

@MainActor
private final class RecordingCloudSyncEngine: CloudSyncControlling {
    weak var delegate: CloudSyncDelegate?

    private(set) var setupCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var fetchRemoteChangesCallCount = 0
    private(set) var handleRemoteNotificationCallCount = 0
    private(set) var pushLocalChangeCallCount = 0
    private(set) var pushDeletionCallCount = 0
    private(set) var pushBatchCallCount = 0

    func setup() async {
        setupCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func fetchRemoteChanges() {
        fetchRemoteChangesCallCount += 1
    }

    func handleRemoteNotification() {
        handleRemoteNotificationCallCount += 1
    }

    func pushLocalChange(card: CaptureCard) {
        pushLocalChangeCallCount += 1
    }

    func pushDeletion(id: UUID) {
        pushDeletionCallCount += 1
    }

    func pushBatch(cards: [CaptureCard], deletions: [UUID]) {
        pushBatchCallCount += 1
    }
}

@MainActor
private final class LifecycleTestRecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var state: RecentScreenshotState = .idle
    var onStateChange: ((RecentScreenshotState) -> Void)?

    func start() {}
    func stop() {}
    func prepareForCaptureSession() {}
    func endCaptureSession() {}
    func refreshNow() {}
    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
    func suspendExpiration() {}
    func resumeExpiration() {}
}
