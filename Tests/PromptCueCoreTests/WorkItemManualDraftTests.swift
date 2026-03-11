import XCTest
@testable import PromptCueCore

final class WorkItemManualDraftTests: XCTestCase {
    func testManualDraftBuildsUserOwnedOpenItemFromSingleCard() {
        let card = CaptureCard(
            text: "settings sync edge case",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        let draft = WorkItem.manualDraft(
            from: [card],
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(draft?.title, "settings sync edge case")
        XCTAssertNil(draft?.summary)
        XCTAssertEqual(draft?.status, .open)
        XCTAssertEqual(draft?.createdBy, .user)
        XCTAssertEqual(draft?.sourceNoteCount, 1)
    }

    func testManualDraftPreservesCommonRepoContextAndAddsMultiSourceSummary() {
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let target = CaptureSuggestedTarget(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            repositoryRoot: "/Users/me/PromptCue",
            repositoryName: "PromptCue",
            branch: "backtick-mcp",
            capturedAt: capturedAt
        )
        let cards = [
            CaptureCard(
                text: "retry logic needs review",
                suggestedTarget: target,
                createdAt: capturedAt
            ),
            CaptureCard(
                text: "loading state race condition suspected",
                suggestedTarget: target,
                createdAt: capturedAt.addingTimeInterval(10)
            ),
        ]

        let draft = WorkItem.manualDraft(from: cards)

        XCTAssertEqual(draft?.title, "retry logic needs review + 1 more")
        XCTAssertEqual(
            draft?.summary,
            "retry logic needs review\n\nloading state race condition suspected"
        )
        XCTAssertEqual(draft?.repoName, "PromptCue")
        XCTAssertEqual(draft?.branchName, "backtick-mcp")
    }

    func testManualDraftDropsMixedRepoContext() {
        let cards = [
            CaptureCard(
                text: "settings sync",
                suggestedTarget: CaptureSuggestedTarget(
                    appName: "Cursor",
                    bundleIdentifier: "cursor",
                    repositoryName: "PromptCue",
                    branch: "main",
                    capturedAt: Date(timeIntervalSince1970: 1_000)
                ),
                createdAt: Date(timeIntervalSince1970: 1_000)
            ),
            CaptureCard(
                text: "analytics missing event",
                suggestedTarget: CaptureSuggestedTarget(
                    appName: "Cursor",
                    bundleIdentifier: "cursor",
                    repositoryName: "BacktickWeb",
                    branch: "main",
                    capturedAt: Date(timeIntervalSince1970: 1_010)
                ),
                createdAt: Date(timeIntervalSince1970: 1_010)
            ),
        ]

        let draft = WorkItem.manualDraft(from: cards)

        XCTAssertNil(draft?.repoName)
        XCTAssertEqual(draft?.branchName, "main")
    }

    func testManualDraftFallsBackToCapturedNoteForEmptyText() {
        let card = CaptureCard(
            text: "   ",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        let draft = WorkItem.manualDraft(from: [card])

        XCTAssertEqual(draft?.title, "Captured note")
        XCTAssertNil(draft?.summary)
    }
}
