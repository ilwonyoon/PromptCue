import Foundation
import XCTest
@testable import Prompt_Cue

final class ScreenshotDirectoryResolverTests: XCTestCase {
    private static let bookmarkDataKey = "com.promptcue.preferredScreenshotDirectoryBookmarkData"
    private static let legacyPreferredPathKey = "preferredScreenshotDirectoryPath"

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "ScreenshotDirectoryResolverTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }

        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }

        defaults = nil
        suiteName = nil
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testShouldPresentOnboardingForPristineDefaults() {
        XCTAssertTrue(ScreenshotDirectoryResolver.shouldPresentOnboarding(using: defaults))
    }

    func testBootstrapLegacyDirectoryMarksOnboardingHandled() {
        let legacyDirectoryURL = tempDirectoryURL.appendingPathComponent("LegacyShots", isDirectory: true)
        defaults.set(legacyDirectoryURL.path, forKey: Self.legacyPreferredPathKey)

        ScreenshotDirectoryResolver.bootstrapPreferredDirectoryIfNeeded(defaults: defaults)

        XCTAssertFalse(ScreenshotDirectoryResolver.shouldPresentOnboarding(using: defaults))
    }

    func testSaveAuthorizedDirectoryMarksOnboardingHandledAndKeepsOnboardingSuppressedAfterClear() throws {
        let authorizedDirectoryURL = tempDirectoryURL.appendingPathComponent("Authorized", isDirectory: true)
        try FileManager.default.createDirectory(at: authorizedDirectoryURL, withIntermediateDirectories: true)

        try ScreenshotDirectoryResolver.saveAuthorizedDirectory(authorizedDirectoryURL, defaults: defaults)
        XCTAssertFalse(ScreenshotDirectoryResolver.shouldPresentOnboarding(using: defaults))

        ScreenshotDirectoryResolver.clearAuthorizedDirectory(defaults: defaults)

        XCTAssertFalse(ScreenshotDirectoryResolver.shouldPresentOnboarding(using: defaults))
    }

    func testPersistedBookmarkHistorySuppressesFirstRunOnboardingEvenWhenBookmarkCannotResolve() {
        defaults.set(Data("invalid-bookmark".utf8), forKey: Self.bookmarkDataKey)

        XCTAssertFalse(ScreenshotDirectoryResolver.shouldPresentOnboarding(using: defaults))
    }
}
