import AppKit
import PromptCueCore
import SwiftUI
import XCTest
@testable import Prompt_Cue

@MainActor
final class CaptureCardRenderingTests: XCTestCase {
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

    func testRenderLightModeScreenshotCardSnapshot() throws {
        let imageURL = tempDirectoryURL.appendingPathComponent("snapshot-source.png")
        try makeFixtureImage(at: imageURL, size: NSSize(width: 1200, height: 800))

        let card = CaptureCard(
            text: "지금 copied stacked card를 열었더니 레이아웃도 깨졌음. 이미지가 카드 컨테이너 안에서 안정적으로 보여야 함.",
            createdAt: Date(),
            screenshotPath: imageURL.path,
            lastCopiedAt: nil,
            sortOrder: 100
        )

        let view = CaptureCardView(
            card: card,
            isSelected: false,
            selectionMode: false,
            isExpanded: false,
            onCopy: {},
            onToggleSelection: {},
            onToggleExpansion: {},
            onDelete: {}
        )
        .environment(\.colorScheme, .light)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 260)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor.white
        window.contentView = hostingView
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let outputURL = URL(fileURLWithPath: "/tmp/PromptCueCaptureCardSnapshot.png")
        try renderPNG(of: hostingView, to: outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testLongCardExpandedStateGrowsRelativeToRestingState() throws {
        let text = Array(
            repeating: "Backtick keeps Stack scannable while still letting long cues reveal more context on demand.",
            count: 18
        )
        .joined(separator: " ")

        let card = CaptureCard(
            text: text,
            createdAt: Date(),
            screenshotPath: nil,
            lastCopiedAt: nil,
            sortOrder: 101
        )

        let collapsedView = NSHostingView(
            rootView: CaptureCardView(
                card: card,
                isSelected: false,
                selectionMode: false,
                isExpanded: false,
                onCopy: {},
                onToggleSelection: {},
                onToggleExpansion: {},
                onDelete: {}
            )
            .environment(\.colorScheme, .light)
        )
        collapsedView.frame = NSRect(x: 0, y: 0, width: 360, height: 800)
        collapsedView.layoutSubtreeIfNeeded()

        let expandedView = NSHostingView(
            rootView: CaptureCardView(
                card: card,
                isSelected: false,
                selectionMode: false,
                isExpanded: true,
                onCopy: {},
                onToggleSelection: {},
                onToggleExpansion: {},
                onDelete: {}
            )
            .environment(\.colorScheme, .light)
        )
        expandedView.frame = NSRect(x: 0, y: 0, width: 360, height: 1200)
        expandedView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(expandedView.fittingSize.height, collapsedView.fittingSize.height)
    }

    func testTaggedCardRendersWithStyledMeasurementContract() {
        let card = CaptureCard(
            text: "Polish the stack rail before launch",
            tags: [
                CaptureTag(rawValue: "stack")!,
                CaptureTag(rawValue: "launch")!,
            ],
            createdAt: Date(),
            screenshotPath: nil,
            lastCopiedAt: nil,
            sortOrder: 103
        )

        let view = NSHostingView(
            rootView: CaptureCardView(
                card: card,
                isSelected: false,
                selectionMode: false,
                isExpanded: false,
                onCopy: {},
                onToggleSelection: {},
                onToggleExpansion: {},
                onDelete: {}
            )
            .environment(\.colorScheme, .light)
        )
        view.frame = NSRect(x: 0, y: 0, width: 360, height: 400)
        view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(view.fittingSize.height, 0)
    }

    func testSecretClassificationUsesMaskedLayoutHeight() throws {
        let text = "sk-ant-api03-plsA-whwgZpvfyNc8M1s9ZcBzMbb83HB1f-HAv5nXS1yvLJqlEG7zLJyMksg4KYkoQ3UNhj0_qeMYWPyhNwG7Q-9O_6gAAA"
        let card = CaptureCard(
            text: text,
            createdAt: Date(),
            screenshotPath: nil,
            lastCopiedAt: nil,
            sortOrder: 102
        )

        let plainView = NSHostingView(
            rootView: CaptureCardView(
                card: card,
                classification: .plain,
                isSelected: false,
                selectionMode: false,
                isExpanded: false,
                onCopy: {},
                onToggleSelection: {},
                onToggleExpansion: {},
                onDelete: {}
            )
            .environment(\.colorScheme, .light)
        )
        plainView.frame = NSRect(x: 0, y: 0, width: 360, height: 400)
        plainView.layoutSubtreeIfNeeded()

        let secretView = NSHostingView(
            rootView: CaptureCardView(
                card: card,
                classification: ContentClassifier.classify(text),
                isSelected: false,
                selectionMode: false,
                isExpanded: false,
                onCopy: {},
                onToggleSelection: {},
                onToggleExpansion: {},
                onDelete: {}
            )
            .environment(\.colorScheme, .light)
        )
        secretView.frame = NSRect(x: 0, y: 0, width: 360, height: 400)
        secretView.layoutSubtreeIfNeeded()

        XCTAssertLessThan(secretView.fittingSize.height, plainView.fittingSize.height)
    }

    private func renderPNG(of view: NSView, to url: URL) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            XCTFail("Could not create bitmap image rep")
            return
        }

        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode PNG")
            return
        }

        try data.write(to: url)
    }

    private func makeFixtureImage(at url: URL, size: NSSize) throws {
        let image = NSImage(size: size)
        image.lockFocus()

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.38, green: 0.52, blue: 0.82, alpha: 1),
        ])!
        gradient.draw(in: NSRect(origin: .zero, size: size), angle: -35)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 54, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
            .paragraphStyle: paragraph,
        ]

        let text = NSString(string: "Prompt Cue\nScreenshot Card")
        text.draw(
            in: NSRect(x: 72, y: 120, width: size.width - 144, height: size.height - 240),
            withAttributes: attributes
        )

        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "CaptureCardRenderingTests", code: 1)
        }

        try png.write(to: url)
    }
}
