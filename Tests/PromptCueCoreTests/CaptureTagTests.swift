import Foundation
import Testing
@testable import PromptCueCore

struct CaptureTagTests {
    @Test
    func captureTagNormalizesHashAndCase() {
        let tag = CaptureTag(rawValue: "#Bug_Fix")

        #expect(tag?.name == "bug_fix")
        #expect(tag?.displayText == "#bug_fix")
    }

    @Test
    func captureTagRejectsInvalidNames() {
        #expect(CaptureTag(rawValue: "#123") == nil)
        #expect(CaptureTag(rawValue: "#bug fix") == nil)
        #expect(CaptureTag(rawValue: "#") == nil)
        #expect(CaptureTag(rawValue: "#한글") == nil)
        #expect(CaptureTag(rawValue: "#ㅠㅕbug") == nil)
    }

    @Test
    func editorTextSerializesTagsBeforeBody() {
        let tags = [
            CaptureTag(rawValue: "bug"),
            CaptureTag(rawValue: "ui"),
        ].compactMap { $0 }

        let editorText = CaptureTagText.editorText(
            tags: tags,
            bodyText: "Fix the capture panel"
        )

        #expect(editorText == "#bug #ui Fix the capture panel")
    }

    @Test
    func inlineDisplayTextSerializesTagsWithoutTrailingWhitespace() {
        let tags = [
            CaptureTag(rawValue: "bug"),
            CaptureTag(rawValue: "ui"),
        ].compactMap { $0 }

        let inlineText = CaptureTagText.inlineDisplayText(
            tags: tags,
            bodyText: "Fix the capture panel"
        )

        #expect(inlineText == "#bug #ui Fix the capture panel")
        #expect(CaptureTagText.inlineDisplayText(tags: tags, bodyText: "") == "#bug #ui")
    }

    @Test
    func inlineDisplayTagRangesCoverEachStructuredTagPrefix() {
        let tags = [
            CaptureTag(rawValue: "bug"),
            CaptureTag(rawValue: "ui"),
        ].compactMap { $0 }

        #expect(
            CaptureTagText.inlineDisplayTagRanges(
                tags: tags,
                bodyText: "Fix the capture panel"
            ) == [
                NSRange(location: 0, length: 4),
                NSRange(location: 5, length: 3),
            ]
        )
        #expect(
            CaptureTagText.inlineDisplayTagRanges(tags: tags, bodyText: "") == [
                NSRange(location: 0, length: 4),
                NSRange(location: 5, length: 3),
            ]
        )
    }

    @Test
    func parseCommittedPrefixExtractsLeadingTagsAndBody() {
        let result = CaptureTagText.parseCommittedPrefix(in: "#bug #ui Fix the capture panel")

        #expect(result.tags.map(\.name) == ["bug", "ui"])
        #expect(result.bodyText == "Fix the capture panel")
        #expect(result.committedTokenRanges == [
            NSRange(location: 0, length: 4),
            NSRange(location: 5, length: 3),
        ])
    }

    @Test
    func parseCommittedPrefixLeavesUncommittedHashInBody() {
        let result = CaptureTagText.parseCommittedPrefix(in: "#bug")

        #expect(result.tags.isEmpty)
        #expect(result.bodyText == "#bug")
        #expect(result.bodyStartUTF16Offset == 0)
    }

    @Test
    func parseCommittedPrefixLeavesMixedScriptPrefixInBody() {
        let result = CaptureTagText.parseCommittedPrefix(in: "#ㅠㅕbug Fix capture")

        #expect(result.tags.isEmpty)
        #expect(result.bodyText == "#ㅠㅕbug Fix capture")
        #expect(result.bodyStartUTF16Offset == 0)
    }

    @Test
    func completionContextFindsLeadingTagPrefix() {
        let text = "#bug #bu"
        let result = CaptureTagText.completionContext(
            in: text,
            caretUTF16Offset: (text as NSString).length
        )

        #expect(result?.rawToken == "#bu")
        #expect(result?.normalizedPrefix == "bu")
        #expect(result?.replacementRange == NSRange(location: 5, length: 3))
    }

    @Test
    func decodeJSONArrayFiltersInvalidAndMixedScriptTags() {
        let decoded = CaptureTag.decodeJSONArray(#"["bug","ㅠㅕbug","mcp"]"#)

        #expect(decoded.map(\.name) == ["bug", "mcp"])
    }

    @Test
    func captureCardVisibleBodyTextHidesLeadingTagPrefixWhenTagsExist() {
        let card = CaptureCard(
            text: "#bug #ui Fix the capture panel",
            tags: [
                CaptureTag(rawValue: "bug"),
                CaptureTag(rawValue: "ui"),
            ].compactMap { $0 },
            createdAt: .now
        )

        #expect(card.visibleBodyText == "Fix the capture panel")
    }

    @Test
    func captureCardVisibleBodyTextPreservesPlainTextWhenTagsAreAbsent() {
        let card = CaptureCard(
            text: "#ship this is plain text",
            createdAt: .now
        )

        #expect(card.visibleBodyText == "#ship this is plain text")
    }

    @Test
    func captureCardVisibleBodyTextPreservesHashPrefixedBodyWhenItDoesNotMatchStoredTags() {
        let card = CaptureCard(
            text: "#ship this is actual body text",
            tags: [
                CaptureTag(rawValue: "bug"),
            ].compactMap { $0 },
            createdAt: .now
        )

        #expect(card.visibleBodyText == "#ship this is actual body text")
    }

    @Test
    func captureCardVisibleInlineTextPrefixesStructuredTagsForStackDisplay() {
        let card = CaptureCard(
            text: "Fix the capture panel",
            tags: [
                CaptureTag(rawValue: "bug"),
                CaptureTag(rawValue: "ui"),
            ].compactMap { $0 },
            createdAt: .now
        )

        #expect(card.visibleInlineText == "#bug #ui Fix the capture panel")
    }

    @Test
    func captureCardVisibleInlineTagRangesFollowStructuredTags() {
        let card = CaptureCard(
            text: "Fix the capture panel",
            tags: [
                CaptureTag(rawValue: "bug"),
                CaptureTag(rawValue: "ui"),
            ].compactMap { $0 },
            createdAt: .now
        )

        #expect(card.visibleInlineTagRanges == [
            NSRange(location: 0, length: 4),
            NSRange(location: 5, length: 3),
        ])
    }

    @Test
    func captureCardVisibleInlineTextPreservesLegacyPrefixedTextWithoutDuplication() {
        let card = CaptureCard(
            text: "#bug #ui Fix the capture panel",
            tags: [
                CaptureTag(rawValue: "bug"),
                CaptureTag(rawValue: "ui"),
            ].compactMap { $0 },
            createdAt: .now
        )

        #expect(card.visibleInlineText == "#bug #ui Fix the capture panel")
    }

    @Test
    func captureCardVisibleInlineTagRangesIgnoreMismatchedLeadingHashBody() {
        let card = CaptureCard(
            text: "#ship this is actual body text",
            tags: [
                CaptureTag(rawValue: "bug"),
            ].compactMap { $0 },
            createdAt: .now
        )

        #expect(card.visibleInlineTagRanges.isEmpty)
    }

    @Test
    func captureCardVisibleInlineTextPreservesMismatchedLeadingHashBody() {
        let card = CaptureCard(
            text: "#ship this is actual body text",
            tags: [
                CaptureTag(rawValue: "bug"),
            ].compactMap { $0 },
            createdAt: .now
        )

        #expect(card.visibleInlineText == "#ship this is actual body text")
    }
}
