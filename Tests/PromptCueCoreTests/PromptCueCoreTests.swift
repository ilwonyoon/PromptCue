import Foundation
import Testing
@testable import PromptCueCore

struct PromptCueCoreTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_000)

    @Test
    func emptyDraftHasNoContent() {
        let draft = CaptureDraft()

        #expect(draft.hasContent == false)
    }

    @Test
    func textDraftHasContentWhenTrimmedTextExists() {
        let draft = CaptureDraft(text: "  mobile layout broken  ")

        #expect(draft.hasContent)
    }

    @Test
    func screenshotOnlyDraftHasContent() {
        let draft = CaptureDraft(recentScreenshot: ScreenshotAttachment(path: "/tmp/screenshot.png"))

        #expect(draft.hasContent)
    }

    @Test
    func screenshotAttachmentIdentityTracksFreshness() {
        let date = Date(timeIntervalSince1970: 1_000)
        let older = ScreenshotAttachment(path: "/tmp/screenshot.png", modifiedAt: date)
        let newer = ScreenshotAttachment(path: "/tmp/screenshot.png", modifiedAt: date.addingTimeInterval(1))

        #expect(older.identityKey != newer.identityKey)
    }

    @Test
    func captureCardExpiresAfterDefaultTTL() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let card = CaptureCard(text: "auth redirect incorrect", createdAt: createdAt)
        let justBeforeExpiry = createdAt.addingTimeInterval(CaptureCard.ttl - 1)
        let justAfterExpiry = createdAt.addingTimeInterval(CaptureCard.ttl + 1)

        #expect(card.isExpired(relativeTo: justBeforeExpiry) == false)
        #expect(card.isExpired(relativeTo: justAfterExpiry))
    }

    @Test
    func captureCardBuildsScreenshotURL() {
        let card = CaptureCard(
            text: "screenshot attached",
            createdAt: .now,
            screenshotPath: "/tmp/example.png"
        )

        #expect(card.screenshotURL?.path == "/tmp/example.png")
    }

    @Test
    func captureCardTracksCopiedState() {
        let copiedAt = Date(timeIntervalSince1970: 2_000)
        let card = CaptureCard(text: "copied cue", createdAt: .now)
        let copied = card.markCopied(at: copiedAt)

        #expect(card.isCopied == false)
        #expect(copied.isCopied)
        #expect(copied.lastCopiedAt == copiedAt)
    }

    @Test
    func cardStackOrderingMovesCopiedCardsToBottom() {
        let oldest = Date(timeIntervalSince1970: 1_000)
        let newest = Date(timeIntervalSince1970: 2_000)
        let earlierCopy = Date(timeIntervalSince1970: 3_000)
        let laterCopy = Date(timeIntervalSince1970: 4_000)

        let freshCard = CaptureCard(text: "fresh", createdAt: newest)
        let olderCopiedCard = CaptureCard(
            text: "older copied",
            createdAt: oldest,
            lastCopiedAt: earlierCopy
        )
        let justCopiedCard = CaptureCard(
            text: "just copied",
            createdAt: newest.addingTimeInterval(10),
            lastCopiedAt: laterCopy
        )

        let ordered = CardStackOrdering.sort([justCopiedCard, olderCopiedCard, freshCard])

        #expect(ordered.map(\.text) == ["fresh", "older copied", "just copied"])
    }

    @Test
    func cardStackOrderingRespectsManualSortOrderWithinSection() {
        let top = CaptureCard(text: "top", createdAt: .now, sortOrder: 10)
        let bottom = CaptureCard(text: "bottom", createdAt: .now.addingTimeInterval(-10), sortOrder: 1)

        let ordered = CardStackOrdering.sort([bottom, top])

        #expect(ordered.map(\.text) == ["top", "bottom"])
    }

    @Test
    func exportFormatterBuildsBulletedClipboardPayloadInOrder() {
        let cards = [
            CaptureCard(text: "mobile layout broken", createdAt: .now),
            CaptureCard(text: "auth redirect incorrect", createdAt: .now),
            CaptureCard(text: "screenshot attached", createdAt: .now),
        ]

        let payload = ExportFormatter.string(for: cards)

        #expect(
            payload == """
            • mobile layout broken
            • auth redirect incorrect
            • screenshot attached
            """
        )
    }

    @Test
    func suggestedTargetWorkspaceLabelFallsBackToWindowTitleWhenRepoAndCwdAreMissing() {
        let target = makeSuggestedTarget(
            windowTitle: "PromptCue.swift",
            currentWorkingDirectory: nil,
            repositoryRoot: nil,
            repositoryName: nil
        )

        #expect(target.workspaceLabel == "PromptCue.swift")
    }

    @Test
    func suggestedTargetSourceKindDistinguishesTerminalFromIDEBundleIdentifiers() {
        let terminalTarget = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            capturedAt: referenceDate
        )
        let ideTarget = makeSuggestedTarget()

        #expect(terminalTarget.sourceKind == .terminal)
        #expect(ideTarget.sourceKind == .ide)
    }

    @Test
    func suggestedTargetFallbackDisplayLabelUsesWindowTitleThenAppName() {
        let titledTarget = makeSuggestedTarget(
            windowTitle: "Antigravity Workspace",
            currentWorkingDirectory: nil,
            repositoryRoot: nil,
            repositoryName: nil
        )
        let untitledTarget = makeSuggestedTarget(
            appName: "Antigravity",
            windowTitle: nil,
            currentWorkingDirectory: nil,
            repositoryRoot: nil,
            repositoryName: nil
        )

        #expect(titledTarget.fallbackDisplayLabel == "Antigravity Workspace")
        #expect(untitledTarget.fallbackDisplayLabel == "Antigravity")
    }

    @Test
    func suggestedTargetChooserSectionTitleFollowsSourceKind() {
        let terminalTarget = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            capturedAt: referenceDate
        )
        let ideTarget = makeSuggestedTarget()

        #expect(terminalTarget.chooserSectionTitle == "Open Terminals")
        #expect(ideTarget.chooserSectionTitle == "Open IDEs")
    }

    @Test
    func suggestedTargetWorkspaceLabelFallsBackToAppNameWhenWindowTitleAndPathsAreMissing() {
        let target = makeSuggestedTarget(
            windowTitle: nil,
            currentWorkingDirectory: nil,
            repositoryRoot: nil,
            repositoryName: nil
        )

        #expect(target.workspaceLabel == "Cursor")
    }

    @Test
    func suggestedTargetWorkspaceLabelUsesWorkingDirectoryLeafWhenRepoMetadataIsMissing() {
        let target = makeSuggestedTarget(
            windowTitle: nil,
            currentWorkingDirectory: "/Users/ilwon/dev/PromptCue",
            repositoryRoot: nil,
            repositoryName: nil
        )

        #expect(target.workspaceLabel == "PromptCue")
    }

    @Test
    func suggestedTargetShortBranchLabelUsesLeafAndTruncatesToEighteenCharacters() {
        let target = makeSuggestedTarget(branch: "feature/12345678901234567890")

        #expect(target.shortBranchLabel == "12345678901234567…")
    }

    @Test
    func suggestedTargetChooserSecondaryLabelFallsBackToSessionIdentifierWhenWindowTitleMatchesWorkspaceLabel() {
        let target = makeSuggestedTarget(
            windowTitle: "PromptCue",
            sessionIdentifier: "tab-2",
            currentWorkingDirectory: nil,
            repositoryRoot: nil,
            repositoryName: nil,
            branch: nil
        )

        #expect(target.workspaceLabel == "PromptCue")
        #expect(target.chooserSecondaryLabel == "Cursor · tab-2")
    }

    private func makeSuggestedTarget(
        appName: String = "Cursor",
        windowTitle: String? = "PromptCue",
        sessionIdentifier: String? = "tab-1",
        currentWorkingDirectory: String? = "/Users/ilwon/dev/PromptCue/App",
        repositoryRoot: String? = "/Users/ilwon/dev/PromptCue",
        repositoryName: String? = "PromptCue",
        branch: String? = "feature/initial-work"
    ) -> CaptureSuggestedTarget {
        CaptureSuggestedTarget(
            appName: appName,
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            windowTitle: windowTitle,
            sessionIdentifier: sessionIdentifier,
            currentWorkingDirectory: currentWorkingDirectory,
            repositoryRoot: repositoryRoot,
            repositoryName: repositoryName,
            branch: branch,
            capturedAt: referenceDate
        )
    }
}
