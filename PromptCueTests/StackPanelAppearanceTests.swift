import AppKit
import PromptCueCore
import XCTest
@testable import Prompt_Cue

@MainActor
final class StackPanelAppearanceTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func tearDown() {
        NSApp.appearance = nil
        super.tearDown()
    }

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

    func testInheritedThemeRefreshKeepsStackPanelFreeOfLocalOverrides() throws {
        let controller = makeController()
        controller.prepareForFirstPresentation()

        let panel = try XCTUnwrap(stackPanel(from: controller))
        NSApp.appearance = NSAppearance(named: .darkAqua)
        panel.appearance = NSAppearance(named: .darkAqua)
        controller.refreshForInheritedAppearanceChange()

        XCTAssertNil(panel.appearance)
        XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        XCTAssertNil(panel.contentView?.appearance)
        XCTAssertNil(panel.contentViewController?.view.appearance)
    }

    func testMarkAppearanceDirtyFlushesOnShow() throws {
        let controller = makeController()
        controller.prepareForFirstPresentation()

        let panel = try XCTUnwrap(stackPanel(from: controller))

        // Simulate: panel is hidden, system switches to dark mode.
        // The distributed notification calls markAppearanceDirty()
        // before effectiveAppearance has propagated.
        NSApp.appearance = NSAppearance(named: .aqua)
        panel.appearance = NSAppearance(named: .aqua)
        controller.refreshForInheritedAppearanceChange()

        // Now theme flips while panel is NOT visible.
        panel.orderOut(nil)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        controller.markAppearanceDirty()

        // On show(), the pending flag should trigger a refresh that
        // clears any stale local overrides.
        panel.appearance = NSAppearance(named: .aqua) // stale override
        controller.show()

        XCTAssertNil(panel.appearance, "show() must clear stale local appearance override")
        XCTAssertNil(panel.contentView?.appearance)
        XCTAssertNil(panel.contentViewController?.view.appearance)
    }

    func testInheritedThemeRefreshClearsHostedLayerContentsWhenThemeChanges() throws {
        let controller = makeController()
        controller.prepareForFirstPresentation()

        let panel = try XCTUnwrap(stackPanel(from: controller))
        NSApp.appearance = NSAppearance(named: .aqua)
        panel.appearance = NSAppearance(named: .aqua)
        controller.refreshForInheritedAppearanceChange()
        let hostedView = try XCTUnwrap(hostedSwiftUIView(in: panel.contentViewController?.view))
        hostedView.wantsLayer = true
        hostedView.layer?.contents = NSImage(size: NSSize(width: 4, height: 4))

        NSApp.appearance = NSAppearance(named: .darkAqua)
        panel.appearance = NSAppearance(named: .darkAqua)
        controller.refreshForInheritedAppearanceChange()

        XCTAssertNil(panel.appearance)
        XCTAssertNil(hostedView.layer?.contents)
        XCTAssertEqual(hostedView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        XCTAssertNil(hostedView.appearance)
    }

    private func makeController() -> StackPanelController {
        let store = CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite"))
        let model = AppModel(
            cardStore: store,
            attachmentStore: AttachmentStore(
                baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
            ),
            recentScreenshotCoordinator: StackPanelAppearanceRecentScreenshotCoordinator()
        )
        model.cards = [
            CaptureCard(
                text: "Theme flip regression coverage for the stack panel should keep resting cards synced with the inherited system appearance.",
                createdAt: Date(),
                lastCopiedAt: nil,
                sortOrder: 100
            )
        ]
        return StackPanelController(model: model)
    }

    private func stackPanel(from controller: StackPanelController) -> NSPanel? {
        Mirror(reflecting: controller)
            .children
            .first { $0.label == "panel" }?
            .value as? NSPanel
    }

    private func hostedSwiftUIView(in rootView: NSView?) -> NSView? {
        guard let rootView else {
            return nil
        }

        if NSStringFromClass(type(of: rootView)).contains("NSHosting") {
            return rootView
        }

        for subview in rootView.subviews {
            if let hostedView = hostedSwiftUIView(in: subview) {
                return hostedView
            }
        }

        return nil
    }
}

@MainActor
private final class StackPanelAppearanceRecentScreenshotCoordinator: RecentScreenshotCoordinating {
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
