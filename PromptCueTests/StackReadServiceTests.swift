import Foundation
import XCTest
@testable import Prompt_Cue
import PromptCueCore

@MainActor
final class StackReadServiceTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }

        tempDirectoryURL = nil
        databaseURL = nil
        try super.tearDownWithError()
    }

    func testListNotesSeparatesActiveAndCopiedUsingStackOrdering() throws {
        let activeNewest = CaptureCard(
            id: UUID(),
            text: "Newest active",
            createdAt: Date(timeIntervalSinceReferenceDate: 300),
            sortOrder: 30
        )
        let activeOlder = CaptureCard(
            id: UUID(),
            text: "Older active",
            createdAt: Date(timeIntervalSinceReferenceDate: 200),
            sortOrder: 20
        )
        let copiedEarlier = CaptureCard(
            id: UUID(),
            text: "Copied earlier",
            createdAt: Date(timeIntervalSinceReferenceDate: 150),
            lastCopiedAt: Date(timeIntervalSinceReferenceDate: 350),
            sortOrder: 15
        )
        let copiedLatest = CaptureCard(
            id: UUID(),
            text: "Copied latest",
            createdAt: Date(timeIntervalSinceReferenceDate: 250),
            lastCopiedAt: Date(timeIntervalSinceReferenceDate: 400),
            sortOrder: 25
        )
        try saveCards([copiedEarlier, activeOlder, copiedLatest, activeNewest])

        let service = makeService()

        let allNotes = try service.listNotes()
        let activeNotes = try service.listNotes(scope: .active)
        let copiedNotes = try service.listNotes(scope: .copied)

        XCTAssertEqual(allNotes.map(\.id), [activeNewest.id, activeOlder.id, copiedLatest.id, copiedEarlier.id])
        XCTAssertEqual(activeNotes.map(\.id), [activeNewest.id, activeOlder.id])
        XCTAssertEqual(copiedNotes.map(\.id), [copiedLatest.id, copiedEarlier.id])
    }

    func testNoteDetailIncludesCopyEventHistoryInReverseChronologicalOrder() throws {
        let card = CaptureCard(
            id: UUID(),
            text: "Investigate export regression",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            lastCopiedAt: Date(timeIntervalSinceReferenceDate: 150),
            sortOrder: 10
        )
        let olderEvent = CopyEvent(
            id: UUID(),
            noteID: card.id,
            sessionID: "run-1",
            copiedAt: Date(timeIntervalSinceReferenceDate: 140),
            copiedVia: .clipboard,
            copiedBy: .user
        )
        let newerEvent = CopyEvent(
            id: UUID(),
            noteID: card.id,
            sessionID: "run-2",
            copiedAt: Date(timeIntervalSinceReferenceDate: 145),
            copiedVia: .agentRun,
            copiedBy: .mcp
        )
        try saveCards([card])
        try saveCopyEvents([olderEvent, newerEvent])

        let service = makeService()
        let detail = try XCTUnwrap(service.noteDetail(id: card.id))

        XCTAssertEqual(detail.note, card)
        XCTAssertEqual(detail.copyEvents, [newerEvent, olderEvent])
    }

    func testNoteDetailAllowsCopiedNoteWithoutCopyEventRows() throws {
        let card = CaptureCard(
            id: UUID(),
            text: "Already sent to agent",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            lastCopiedAt: Date(timeIntervalSinceReferenceDate: 150),
            sortOrder: 10
        )
        try saveCards([card])

        let service = makeService()
        let detail = try XCTUnwrap(service.noteDetail(id: card.id))

        XCTAssertEqual(detail.note, card)
        XCTAssertTrue(detail.copyEvents.isEmpty)
    }

    func testNoteDetailReturnsNilForMissingNote() throws {
        let service = makeService()

        XCTAssertNil(try service.note(id: UUID()))
        XCTAssertNil(try service.noteDetail(id: UUID()))
    }

    private func makeService() -> StackReadService {
        let database = PromptCueDatabase(databaseURL: databaseURL)
        return StackReadService(
            cardStore: CardStore(database: database),
            copyEventStore: CopyEventStore(database: database)
        )
    }

    private func saveCards(_ cards: [CaptureCard]) throws {
        try CardStore(databaseURL: databaseURL).save(cards)
    }

    private func saveCopyEvents(_ copyEvents: [CopyEvent]) throws {
        try CopyEventStore(databaseURL: databaseURL).recordCopyEvents(copyEvents)
    }
}
