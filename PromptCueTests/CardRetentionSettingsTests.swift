import Foundation
import XCTest
@testable import Prompt_Cue
import PromptCueCore

@MainActor
final class CardRetentionSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var originalStandardState: CardRetentionState!

    override func setUp() {
        super.setUp()
        suiteName = "CardRetentionSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        originalStandardState = CardRetentionPreferences.load()
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        CardRetentionPreferences.save(originalStandardState)
        defaults = nil
        suiteName = nil
        originalStandardState = nil
        super.tearDown()
    }

    func testRetentionDefaultsToAutoExpireDisabled() {
        let state = CardRetentionPreferences.load(defaults: defaults)

        XCTAssertFalse(state.isAutoExpireEnabled)
        XCTAssertNil(state.effectiveTTL)
    }

    func testRetentionStateCanPersistEnabledFlag() {
        CardRetentionPreferences.save(
            CardRetentionState(isAutoExpireEnabled: true),
            defaults: defaults
        )

        let state = CardRetentionPreferences.load(defaults: defaults)

        XCTAssertTrue(state.isAutoExpireEnabled)
        XCTAssertEqual(state.effectiveTTL, PromptCueConstants.defaultTTL)
    }

    func testAppModelKeepsExpiredCardsWhenAutoExpireIsDisabled() throws {
        CardRetentionPreferences.save(CardRetentionState(isAutoExpireEnabled: false))

        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectoryURL) }

        let expiredCard = CaptureCard(
            text: "Keep me",
            createdAt: Date().addingTimeInterval(-(PromptCueConstants.defaultTTL + 60))
        )
        let store = CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite"))
        try store.save([expiredCard])

        let model = AppModel(
            cardStore: store,
            attachmentStore: AttachmentStore(baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments")),
            recentScreenshotCoordinator: TestRetentionRecentScreenshotCoordinator()
        )

        model.reloadCards()

        XCTAssertEqual(model.cards.map(\.text), ["Keep me"])
    }
}

@MainActor
private final class TestRetentionRecentScreenshotCoordinator: RecentScreenshotCoordinating {
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
