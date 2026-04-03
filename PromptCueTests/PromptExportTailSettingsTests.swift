import AppKit
import Foundation
import XCTest
@testable import Prompt_Cue
import PromptCueCore

@MainActor
final class PromptExportTailSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var tempDirectoryURL: URL!

    override func setUp() {
        super.setUp()
        suiteName = "PromptExportTailSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        defaults = nil
        suiteName = nil
        tempDirectoryURL = nil
        super.tearDown()
    }

    func testLoadDefaultsToDisabledWithDefaultTemplate() {
        let state = PromptExportTailPreferences.load(defaults: defaults)

        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.suffixText, PromptExportTailPreferences.defaultSuffixText)
        XCTAssertEqual(state.exportSuffix, .off)
    }

    func testSaveRoundTripsEnabledSuffixState() {
        let expected = PromptExportTailState(
            isEnabled: true,
            suffixText: "\n\nRun root-cause analysis first.\n"
        )

        PromptExportTailPreferences.save(expected, defaults: defaults)
        let loaded = PromptExportTailPreferences.load(defaults: defaults)

        XCTAssertEqual(loaded.isEnabled, true)
        XCTAssertEqual(loaded.suffixText, expected.suffixText)
        XCTAssertEqual(
            ExportFormatter.string(
                for: [CaptureCard(text: "One", createdAt: .now)],
                suffix: loaded.exportSuffix
            ),
            """
            • One

            Run root-cause analysis first.
            """
        )
    }

    func testResetDisablesSuffixAndRestoresTemplate() {
        PromptExportTailPreferences.save(
            PromptExportTailState(isEnabled: true, suffixText: "Custom"),
            defaults: defaults
        )

        let resetState = PromptExportTailPreferences.reset(defaults: defaults)

        XCTAssertFalse(resetState.isEnabled)
        XCTAssertEqual(resetState.suffixText, PromptExportTailPreferences.defaultSuffixText)
    }

    func testClipboardFormatterSkipsExportTailForStandaloneLink() {
        let payload = ClipboardFormatter.string(
            for: [CaptureCard(text: "https://example.com/docs", createdAt: .now)],
            suffix: ExportSuffix("Run root-cause analysis first.")
        )

        XCTAssertEqual(payload, "https://example.com/docs")
    }

    func testClipboardFormatterSkipsExportTailForStandaloneSecret() {
        let payload = ClipboardFormatter.string(
            for: [CaptureCard(text: "sk-ant-abc123def456xyz987", createdAt: .now)],
            suffix: ExportSuffix("Run root-cause analysis first.")
        )

        XCTAssertEqual(payload, "sk-ant-abc123def456xyz987")
    }

    func testClipboardFormatterSkipsExportTailForStandaloneEmail() {
        let payload = ClipboardFormatter.string(
            for: [CaptureCard(text: "dev@example.com", createdAt: .now)],
            suffix: ExportSuffix("Run root-cause analysis first.")
        )

        XCTAssertEqual(payload, "dev@example.com")
    }

    func testClipboardFormatterSkipsExportTailForStandaloneLocalhostLink() {
        let payload = ClipboardFormatter.string(
            for: [CaptureCard(text: "localhost:3000/api/v1?draft=1", createdAt: .now)],
            suffix: ExportSuffix("Run root-cause analysis first.")
        )

        XCTAssertEqual(payload, "localhost:3000/api/v1?draft=1")
    }

    func testClipboardImageDataPreservesOriginalPNGBytes() throws {
        let pngURL = tempDirectoryURL.appendingPathComponent("clipboard-source.png")
        let sourcePNGData = try makeTestPNGData(fill: NSColor.systemOrange)
        try sourcePNGData.write(to: pngURL)

        let imageData = ClipboardFormatter.clipboardImageData(for: pngURL)

        XCTAssertNotNil(imageData.tiff)
        XCTAssertEqual(imageData.png, sourcePNGData)
    }

    func testClipboardFormatterPlacesAttachmentPathBeforeBodyAndSuffix() throws {
        let attachmentStore = AttachmentStore()
        let sourcePNGURL = tempDirectoryURL.appendingPathComponent("ordered-source.png")
        let sourcePNGData = try makeTestPNGData(fill: NSColor.systemBlue)
        try sourcePNGData.write(to: sourcePNGURL)
        let managedURL = try attachmentStore.importScreenshot(from: sourcePNGURL, ownerID: UUID())
        defer {
            try? attachmentStore.removeManagedFile(at: managedURL)
        }

        let card = CaptureCard(
            text: "Body text",
            createdAt: .now,
            screenshotPath: managedURL.path
        )

        let payload = ClipboardFormatter.string(
            for: [card],
            suffix: ExportSuffix("Analyze notes above.")
        )

        XCTAssertEqual(
            payload,
            """
            Attached image path:
            \(managedURL.path)

            • Body text

            Analyze notes above.
            """
        )
    }

    func testClipboardFormatterPlacesAttachmentPathBeforeBodyAndSuffixWhenDebugFallbackEnabled() throws {
        let defaults = UserDefaults.standard
        let pathDefaultsKey = ClipboardFormatter.debugIncludeAttachmentPathsDefaultsKey
        let originalPathOverride = defaults.object(forKey: pathDefaultsKey)
        defaults.set(true, forKey: pathDefaultsKey)
        defer {
            if let originalPathOverride {
                defaults.set(originalPathOverride, forKey: pathDefaultsKey)
            } else {
                defaults.removeObject(forKey: pathDefaultsKey)
            }
        }

        let attachmentStore = AttachmentStore()
        let sourcePNGURL = tempDirectoryURL.appendingPathComponent("ordered-source-debug.png")
        let sourcePNGData = try makeTestPNGData(fill: NSColor.systemBlue)
        try sourcePNGData.write(to: sourcePNGURL)
        let managedURL = try attachmentStore.importScreenshot(from: sourcePNGURL, ownerID: UUID())
        defer {
            try? attachmentStore.removeManagedFile(at: managedURL)
        }

        let card = CaptureCard(
            text: "Body text",
            createdAt: .now,
            screenshotPath: managedURL.path
        )

        let payload = ClipboardFormatter.string(
            for: [card],
            suffix: ExportSuffix("Analyze notes above.")
        )

        XCTAssertEqual(
            payload,
            """
            Attached image path:
            \(managedURL.path)

            • Body text

            Analyze notes above.
            """
        )
    }

    private func makeTestPNGData(fill: NSColor) throws -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let rep else {
            throw TestError.failedToCreateBitmapRep
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw TestError.failedToCreateGraphicsContext
        }

        NSGraphicsContext.current = context
        fill.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill()

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw TestError.failedToEncodePNG
        }

        return pngData
    }

    private enum TestError: Error {
        case failedToCreateBitmapRep
        case failedToCreateGraphicsContext
        case failedToEncodePNG
    }
}
