import XCTest
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

        XCTAssertTrue(model.saveSelectedDocumentContent(updatedContent))
        XCTAssertTrue(model.selectedDocument?.content.contains("Updated Brief") == true)
        XCTAssertEqual(model.summaries(for: "Backtick").count, 1)
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
