import AppKit
import Foundation
import XCTest
@testable import Prompt_Cue

@MainActor
final class RecentClipboardImageMonitorTests: XCTestCase {
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

    func testStartBaselinesExistingClipboardAndDoesNotEmitStaleImage() throws {
        let pasteboard = TestClipboardPasteboard()
        pasteboard.changeCount = 5
        pasteboard.storage[.png] = Data("existing".utf8)

        let monitor = RecentClipboardImageMonitor(
            pasteboard: pasteboard,
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL),
            now: Date.init,
            pollInterval: 0
        )

        monitor.start()

        XCTAssertNil(monitor.recentImage(referenceDate: Date(), maxAge: 30))
    }

    func testRefreshNowDetectsNewPNGImageAndCachesIt() throws {
        let pasteboard = TestClipboardPasteboard()
        let monitor = RecentClipboardImageMonitor(
            pasteboard: pasteboard,
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL),
            now: Date.init,
            pollInterval: 0
        )

        monitor.start()
        pasteboard.changeCount = 1
        pasteboard.storage[.png] = Data("png".utf8)

        monitor.refreshNow()

        guard let image = monitor.recentImage(referenceDate: Date(), maxAge: 30) else {
            return XCTFail("Expected cached clipboard image")
        }

        XCTAssertTrue(image.cacheURL.path.hasPrefix(tempDirectoryURL.path))
        XCTAssertEqual(try Data(contentsOf: image.cacheURL), Data("png".utf8))
    }

    func testRefreshNowDetectsNewTIFFImageAndCachesIt() throws {
        let pasteboard = TestClipboardPasteboard()
        let monitor = RecentClipboardImageMonitor(
            pasteboard: pasteboard,
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL),
            now: Date.init,
            pollInterval: 0
        )

        monitor.start()
        pasteboard.changeCount = 1
        pasteboard.storage[.tiff] = Data("tiff".utf8)

        monitor.refreshNow()

        guard let image = monitor.recentImage(referenceDate: Date(), maxAge: 30) else {
            return XCTFail("Expected cached TIFF clipboard image")
        }

        XCTAssertTrue(image.cacheURL.path.hasPrefix(tempDirectoryURL.path))
        XCTAssertEqual(image.cacheURL.pathExtension, "tiff")
        XCTAssertEqual(try Data(contentsOf: image.cacheURL), Data("tiff".utf8))
    }

    func testDismissSuppressesCurrentChangeCountUntilClipboardChangesAgain() throws {
        let pasteboard = TestClipboardPasteboard()
        let monitor = RecentClipboardImageMonitor(
            pasteboard: pasteboard,
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL),
            now: Date.init,
            pollInterval: 0
        )

        monitor.start()
        pasteboard.changeCount = 1
        pasteboard.storage[.png] = Data("png".utf8)
        monitor.refreshNow()
        XCTAssertNotNil(monitor.recentImage(referenceDate: Date(), maxAge: 30))

        monitor.dismissCurrent()
        XCTAssertNil(monitor.recentImage(referenceDate: Date(), maxAge: 30))

        monitor.refreshNow()
        XCTAssertNil(monitor.recentImage(referenceDate: Date(), maxAge: 30))

        pasteboard.changeCount = 2
        pasteboard.storage[.png] = Data("png2".utf8)
        monitor.refreshNow()

        guard let image = monitor.recentImage(referenceDate: Date(), maxAge: 30) else {
            return XCTFail("Expected clipboard image after new pasteboard change")
        }

        XCTAssertEqual(try Data(contentsOf: image.cacheURL), Data("png2".utf8))
    }

    func testConsumeSuppressesCurrentChangeCountUntilClipboardChangesAgain() throws {
        let pasteboard = TestClipboardPasteboard()
        let monitor = RecentClipboardImageMonitor(
            pasteboard: pasteboard,
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL),
            now: Date.init,
            pollInterval: 0
        )

        monitor.start()
        pasteboard.changeCount = 1
        pasteboard.storage[.png] = Data("png".utf8)
        monitor.refreshNow()
        XCTAssertNotNil(monitor.recentImage(referenceDate: Date(), maxAge: 30))

        monitor.consumeCurrent()
        XCTAssertNil(monitor.recentImage(referenceDate: Date(), maxAge: 30))

        monitor.refreshNow()
        XCTAssertNil(monitor.recentImage(referenceDate: Date(), maxAge: 30))

        pasteboard.changeCount = 2
        pasteboard.storage[.png] = Data("png2".utf8)
        monitor.refreshNow()

        guard let image = monitor.recentImage(referenceDate: Date(), maxAge: 30) else {
            return XCTFail("Expected clipboard image after new pasteboard change")
        }

        XCTAssertEqual(try Data(contentsOf: image.cacheURL), Data("png2".utf8))
    }

    func testNonImageClipboardChangesAreIgnored() throws {
        let pasteboard = TestClipboardPasteboard()
        let monitor = RecentClipboardImageMonitor(
            pasteboard: pasteboard,
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL),
            now: Date.init,
            pollInterval: 0
        )

        monitor.start()
        pasteboard.changeCount = 1
        pasteboard.storage[.string] = Data("hello".utf8)
        monitor.refreshNow()

        XCTAssertNil(monitor.recentImage(referenceDate: Date(), maxAge: 30))
    }
}

private final class TestClipboardPasteboard: ClipboardPasteboardReading {
    var changeCount: Int = 0
    var storage: [NSPasteboard.PasteboardType: Data] = [:]

    func data(for type: NSPasteboard.PasteboardType) -> Data? {
        storage[type]
    }
}
