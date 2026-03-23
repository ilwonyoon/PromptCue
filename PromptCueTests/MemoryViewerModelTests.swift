import XCTest
import AppKit
import PromptCueCore
@testable import Prompt_Cue

@MainActor
final class MemoryViewerModelTests: XCTestCase {
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
        if let tempDirectoryURL,
           FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testRefreshGroupsProjectsAndLoadsFirstDocument() throws {
        let store = try makeStore()
        let baseDate = Date(timeIntervalSince1970: 1_000)
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "brief",
            documentType: .reference,
            content: sampleContent(title: "Brief"),
            now: baseDate
        )
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "warm-memory",
            documentType: .decision,
            content: sampleContent(title: "Warm Memory"),
            now: baseDate.addingTimeInterval(10)
        )
        _ = try store.saveDocument(
            project: "Second Project",
            topic: "brief",
            documentType: .reference,
            content: sampleContent(title: "Second"),
            now: baseDate.addingTimeInterval(20)
        )

        let model = MemoryViewerModel(store: store)

        XCTAssertEqual(model.projects, ["Second Project", "Backtick"])
        XCTAssertEqual(model.selectedProject, "Second Project")
        XCTAssertEqual(model.selectedDocumentKey?.project, "Second Project")
        XCTAssertEqual(model.selectedDocumentKey?.topic, "brief")
        XCTAssertTrue(model.selectedDocument?.content.contains("Second") == true)
    }

    func testSelectionPersistsAcrossSupersedingRefreshByKey() throws {
        let store = try makeStore()
        let originalDate = Date(timeIntervalSince1970: 2_000)
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "warm-memory",
            documentType: .decision,
            content: sampleContent(title: "Initial"),
            now: originalDate
        )

        let model = MemoryViewerModel(store: store)
        XCTAssertEqual(model.selectedDocumentKey?.topic, "warm-memory")
        XCTAssertTrue(model.selectedDocument?.content.contains("Initial") == true)

        _ = try store.updateDocument(
            project: "Backtick",
            topic: "warm-memory",
            documentType: .decision,
            action: .append,
            section: nil,
            content: "## Later\n\nUpdated after supersession with a newer active version.",
            now: originalDate.addingTimeInterval(30)
        )

        model.refresh()

        XCTAssertEqual(model.selectedDocumentKey?.topic, "warm-memory")
        XCTAssertTrue(model.selectedDocument?.content.contains("## Later") == true)
        XCTAssertEqual(model.summaries(for: "Backtick").count, 1)
    }

    func testSaveSelectedDocumentContentSupersedesCurrentDocument() throws {
        let store = try makeStore()
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "brief",
            documentType: .reference,
            content: sampleContent(title: "Initial Brief")
        )

        let model = MemoryViewerModel(store: store)
        let updatedContent = sampleContent(title: "Updated Brief")

        XCTAssertEqual(model.saveSelectedDocumentContent(updatedContent), .saved)
        XCTAssertTrue(model.selectedDocument?.content.contains("Updated Brief") == true)
        XCTAssertEqual(model.summaries(for: "Backtick").count, 1)
    }

    func testSaveDocumentDoesNotIncreaseRecallMetrics() throws {
        let store = try makeStore()
        let baseDate = Date(timeIntervalSince1970: 2_500)
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "brief",
            documentType: .reference,
            content: sampleContent(title: "Initial Brief"),
            now: baseDate
        )

        let recalled = try XCTUnwrap(store.recordRecall(
            project: "Backtick",
            topic: "brief",
            documentType: .reference,
            now: baseDate.addingTimeInterval(86_400)
        ))
        let saved = try store.saveDocument(
            project: "Backtick",
            topic: "brief",
            documentType: .reference,
            content: sampleContent(title: "Updated Brief"),
            now: baseDate.addingTimeInterval(2 * 86_400)
        )

        XCTAssertEqual(saved.recallCount, recalled.recallCount)
        XCTAssertEqual(saved.lastRecalledAt, recalled.lastRecalledAt)
        XCTAssertEqual(saved.stability, recalled.stability, accuracy: 0.001)
    }

    func testDeleteSelectedDocumentPrefersNextDocumentInSameProject() throws {
        let store = try makeStore()
        let baseDate = Date(timeIntervalSince1970: 3_000)
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "alpha",
            documentType: .reference,
            content: sampleContent(title: "Alpha"),
            now: baseDate
        )
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "beta",
            documentType: .reference,
            content: sampleContent(title: "Beta"),
            now: baseDate.addingTimeInterval(10)
        )
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "gamma",
            documentType: .reference,
            content: sampleContent(title: "Gamma"),
            now: baseDate.addingTimeInterval(20)
        )

        let model = MemoryViewerModel(store: store)
        model.selectedDocumentKey = ProjectDocumentKey(
            project: "Backtick",
            topic: "beta",
            documentType: .reference
        )

        XCTAssertTrue(model.deleteSelectedDocument())
        XCTAssertEqual(model.selectedDocumentKey?.topic, "alpha")
        XCTAssertEqual(model.summaries(for: "Backtick").map(\.topic), ["gamma", "alpha"])
    }

    func testDeleteSelectedDocumentFallsBackToFirstRemainingDocumentInSameProject() throws {
        let store = try makeStore()
        let baseDate = Date(timeIntervalSince1970: 4_000)
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "alpha",
            documentType: .reference,
            content: sampleContent(title: "Alpha"),
            now: baseDate
        )
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "beta",
            documentType: .reference,
            content: sampleContent(title: "Beta"),
            now: baseDate.addingTimeInterval(10)
        )
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "gamma",
            documentType: .reference,
            content: sampleContent(title: "Gamma"),
            now: baseDate.addingTimeInterval(20)
        )

        let model = MemoryViewerModel(store: store)
        model.selectedDocumentKey = ProjectDocumentKey(
            project: "Backtick",
            topic: "alpha",
            documentType: .reference
        )

        XCTAssertTrue(model.deleteSelectedDocument())
        XCTAssertEqual(model.selectedDocumentKey?.topic, "gamma")
        XCTAssertEqual(model.summaries(for: "Backtick").map(\.topic), ["gamma", "beta"])
    }

    func testDeleteSelectedDocumentFallsBackToAnotherProjectWhenProjectBecomesEmpty() throws {
        let store = try makeStore()
        let baseDate = Date(timeIntervalSince1970: 5_000)
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "brief",
            documentType: .reference,
            content: sampleContent(title: "Backtick Brief"),
            now: baseDate.addingTimeInterval(20)
        )
        _ = try store.saveDocument(
            project: "Second Project",
            topic: "overview",
            documentType: .reference,
            content: sampleContent(title: "Second Overview"),
            now: baseDate
        )

        let model = MemoryViewerModel(store: store)

        XCTAssertEqual(model.selectedProject, "Backtick")
        XCTAssertTrue(model.deleteSelectedDocument())
        XCTAssertEqual(model.selectedProject, "Second Project")
        XCTAssertEqual(model.selectedDocumentKey?.topic, "overview")
    }

    func testDeleteProjectRemovesAllActiveDocumentsFromViewer() throws {
        let store = try makeStore()
        let baseDate = Date(timeIntervalSince1970: 6_000)
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "brief",
            documentType: .reference,
            content: sampleContent(title: "Brief"),
            now: baseDate.addingTimeInterval(20)
        )
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "plan",
            documentType: .plan,
            content: sampleContent(title: "Plan"),
            now: baseDate.addingTimeInterval(10)
        )
        _ = try store.saveDocument(
            project: "Second Project",
            topic: "reference",
            documentType: .reference,
            content: sampleContent(title: "Reference"),
            now: baseDate
        )

        let model = MemoryViewerModel(store: store)

        XCTAssertTrue(model.deleteProject("Backtick"))
        XCTAssertEqual(model.projects, ["Second Project"])
        XCTAssertEqual(model.selectedProject, "Second Project")
        XCTAssertEqual(model.summaries(for: "Backtick"), [])
    }

    func testCreateDocumentSelectsNewlyCreatedDocument() throws {
        let store = try makeStore()
        let model = MemoryViewerModel(store: store)

        XCTAssertTrue(
            model.createDocument(
                project: "Backtick",
                topic: "roadmap",
                documentType: .plan,
                content: sampleContent(title: "Roadmap")
            )
        )
        XCTAssertEqual(model.selectedProject, "Backtick")
        XCTAssertEqual(model.selectedDocumentKey?.topic, "roadmap")
        XCTAssertEqual(model.selectedDocumentKey?.documentType, .plan)
        XCTAssertTrue(model.selectedDocument?.content.contains("Roadmap") == true)
    }

    func testCreateDocumentRejectsDuplicateActiveKeyWithoutOverwriting() throws {
        let store = try makeStore()
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "roadmap",
            documentType: .plan,
            content: sampleContent(title: "Original Roadmap")
        )

        let model = MemoryViewerModel(store: store)

        XCTAssertFalse(
            model.createDocument(
                project: "Backtick",
                topic: "roadmap",
                documentType: .plan,
                content: sampleContent(title: "Replacement Roadmap")
            )
        )
        XCTAssertEqual(
            model.storageErrorMessage,
            "A document with this project, topic, and type already exists."
        )
        XCTAssertEqual(model.summaries(for: "Backtick").count, 1)
        XCTAssertTrue(model.selectedDocument?.content.contains("Original Roadmap") == true)
    }

    func testSaveSelectedDocumentContentTreatsWhitespaceOnlyAsDeleteIntent() throws {
        let store = try makeStore()
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "brief",
            documentType: .reference,
            content: sampleContent(title: "Brief")
        )

        let model = MemoryViewerModel(store: store)

        XCTAssertEqual(model.saveSelectedDocumentContent("   \n\t"), .deleteIntent)
        XCTAssertEqual(model.summaries(for: "Backtick").count, 1)
        XCTAssertEqual(model.selectedDocumentKey?.topic, "brief")
    }

    func testPrepareNewDocumentDraftFromClipboardWrapsPlainTextAndUsesSelectedProject() throws {
        let store = try makeStore()
        _ = try store.saveDocument(
            project: "Backtick",
            topic: "brief",
            documentType: .reference,
            content: sampleContent(title: "Brief")
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("Plain clipboard note for the memory panel.", forType: .string)

        let model = MemoryViewerModel(store: store, pasteboard: pasteboard)
        let draft = model.prepareNewDocumentDraft(fromClipboard: true)

        XCTAssertEqual(draft.project, "Backtick")
        XCTAssertEqual(draft.documentType, .discussion)
        XCTAssertTrue(draft.content.contains("## Overview"))
        XCTAssertTrue(draft.content.contains("Plain clipboard note for the memory panel."))
        XCTAssertTrue(draft.content.contains("## Details"))
        XCTAssertNoThrow(try ProjectDocumentStore.validateContent(draft.content))
        XCTAssertTrue(
            model.createDocument(
                project: draft.project,
                topic: "clipboard-note",
                documentType: draft.documentType,
                content: draft.content
            )
        )
    }

    private func makeStore() throws -> ProjectDocumentStore {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        return ProjectDocumentStore(databaseURL: databaseURL)
    }

    private func sampleContent(title: String) -> String {
        """
        ## \(title)

        This is durable test content for the memory viewer model and it is intentionally long enough to pass validation.

        ## Details

        More durable project context lives here so the document clearly exceeds the minimum stored content threshold.
        """
    }
}
