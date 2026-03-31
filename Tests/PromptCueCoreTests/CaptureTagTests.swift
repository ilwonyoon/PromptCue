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
    func captureTagNormalizesMixedCaseTags() {
        #expect(CaptureTag(rawValue: "#HelloWorld")?.name == "helloworld")
        #expect(CaptureTag(rawValue: "#HELLO")?.name == "hello")
        #expect(CaptureTag(rawValue: "#camelCaseTag")?.name == "camelcasetag")
    }

    @Test
    func extractCanonicalInlineTagsHandlesMixedCase() {
        let result = CaptureTagText.extractCanonicalInlineTags(
            in: "Fix #HelloWorld and #HELLO and #camelCaseTag here"
        )

        #expect(result.tags.map(\.name) == ["helloworld", "hello", "camelcasetag"])
    }

    @Test
    func captureTagRejectsInvalidNames() {
        #expect(CaptureTag(rawValue: "#123") == nil)
        #expect(CaptureTag(rawValue: "#bug fix") == nil)
        #expect(CaptureTag(rawValue: "#") == nil)
    }

    @Test
    func captureTagAcceptsKoreanTags() {
        #expect(CaptureTag(rawValue: "#한글")?.name == "한글")
        #expect(CaptureTag(rawValue: "#디자인")?.name == "디자인")
        #expect(CaptureTag(rawValue: "#ㅠㅕbug")?.name == "ㅠㅕbug")
    }

    @Test
    func extractCanonicalInlineTagsFindsInlineHashtagsAnywhere() {
        let result = CaptureTagText.extractCanonicalInlineTags(
            in: "Fix #Bug in the middle, then mention #ui and #bug_fix."
        )

        #expect(result.tags.map(\.name) == ["bug", "ui", "bug_fix"])
        #expect(result.matches.map(\.range) == [
            NSRange(location: 4, length: 4),
            NSRange(location: 37, length: 3),
            NSRange(location: 45, length: 8),
        ])
    }

    @Test
    func extractCanonicalInlineTagsLeavesNonCanonicalHashtagsInText() {
        let result = CaptureTagText.extractCanonicalInlineTags(
            in: "#123 keep this raw"
        )

        #expect(result.tags.isEmpty)
        #expect(result.matches.isEmpty)
    }

    @Test
    func extractCanonicalInlineTagsHandlesKoreanTags() {
        let text = "#디자인 작업 #한글태그 확인"
        let result = CaptureTagText.extractCanonicalInlineTags(in: text)

        #expect(result.tags.map(\.name) == ["디자인", "한글태그"])
    }

    @Test
    func extractCanonicalInlineTagsIgnoresURLFragments() {
        let result = CaptureTagText.extractCanonicalInlineTags(
            in: "See https://example.com/#section before shipping #bug"
        )

        #expect(result.tags.map(\.name) == ["bug"])
        #expect(result.matches.map(\.range) == [
            NSRange(location: 49, length: 4),
        ])
    }

    @Test
    func extractCanonicalInlineTagsSupportsTagsAdjacentToNonLatinText() {
        let result = CaptureTagText.extractCanonicalInlineTags(
            in: "중간#Bug처리와 앞쪽#ui마감"
        )

        #expect(result.tags.map(\.name) == ["bug", "ui"])
        #expect(result.matches.map(\.range) == [
            NSRange(location: 2, length: 4),
            NSRange(location: 12, length: 3),
        ])
    }

    @Test
    func extractCanonicalInlineTagsRejectsDoubleHashPrefixes() {
        let text = "Heading ##bug should stay raw while 중간#ui는 유지"
        let result = CaptureTagText.extractCanonicalInlineTags(in: text)

        #expect(result.tags.map(\.name) == ["ui"])
        #expect(result.matches.map(\.range) == [
            (text as NSString).range(of: "#ui"),
        ])
    }

    @Test
    func editorTextPreservesRawInlineText() {
        let text = "Fix #bug in the capture panel"
        let tags = [CaptureTag(rawValue: "ui")].compactMap { $0 }

        #expect(CaptureTagText.editorText(tags: tags, bodyText: text) == text)
    }

    @Test
    func inlineDisplayTextUsesRawTextBaseline() {
        let text = "Fix #bug in the capture panel"

        #expect(CaptureTagText.inlineDisplayText(tags: [], bodyText: text) == text)
    }

    @Test
    func inlineDisplayTagRangesUseRawTextLocations() {
        let tags = [
            CaptureTag(rawValue: "bug"),
            CaptureTag(rawValue: "ui"),
        ].compactMap { $0 }

        #expect(
            CaptureTagText.inlineDisplayTagRanges(
                tags: tags,
                bodyText: "Fix #bug in #ui panel"
            ) == [
                NSRange(location: 4, length: 4),
                NSRange(location: 12, length: 3),
            ]
        )
    }

    @Test
    func completionContextFindsMidlinePartialTagPrefix() {
        let text = "Fix the #bu capture panel"
        let caret = (text as NSString).range(of: "#bu").location + 3

        let result = CaptureTagText.completionContext(
            in: text,
            caretUTF16Offset: caret
        )

        #expect(result?.rawToken == "#bu")
        #expect(result?.normalizedPrefix == "bu")
        #expect(result?.replacementRange == NSRange(location: 8, length: 3))
    }

    @Test
    func completionContextFindsTagPrefixAdjacentToNonLatinText() {
        let text = "중간#bu처리"
        let caret = (text as NSString).range(of: "#bu").location + 3

        let result = CaptureTagText.completionContext(
            in: text,
            caretUTF16Offset: caret
        )

        #expect(result?.rawToken == "#bu")
        #expect(result?.normalizedPrefix == "bu")
        #expect(result?.replacementRange == NSRange(location: 2, length: 3))
    }

    @Test
    func completionContextRejectsDoubleHashPrefixes() {
        let text = "##bu"
        let caret = text.utf16.count

        let result = CaptureTagText.completionContext(
            in: text,
            caretUTF16Offset: caret
        )

        #expect(result == nil)
    }

    @Test
    func decodeJSONArrayFiltersInvalidTags() {
        let decoded = CaptureTag.decodeJSONArray(#"["bug","123invalid","mcp"]"#)

        #expect(decoded.map(\.name) == ["bug", "mcp"])
    }

    @Test
    func decodeJSONArrayAcceptsKoreanTags() {
        let decoded = CaptureTag.decodeJSONArray(#"["bug","ㅠㅕbug","mcp"]"#)

        #expect(decoded.map(\.name) == ["bug", "ㅠㅕbug", "mcp"])
    }

    @Test
    func captureCardDerivesTagsFromRawInlineTextAndPreservesText() {
        let card = CaptureCard(
            text: "Fix #bug and #ui in the capture panel",
            createdAt: .now
        )

        #expect(card.text == "Fix #bug and #ui in the capture panel")
        #expect(card.tags.map(\.name) == ["bug", "ui"])
        #expect(card.visibleBodyText == "Fix #bug and #ui in the capture panel")
        #expect(card.visibleInlineText == "Fix #bug and #ui in the capture panel")
        #expect(card.visibleInlineTagRanges == [
            NSRange(location: 4, length: 4),
            NSRange(location: 13, length: 3),
        ])
    }

    @Test
    func captureCardLeavesNonCanonicalHashtagsInTextAndOutOfTags() {
        let card = CaptureCard(
            text: "#123 keep this raw",
            createdAt: .now
        )

        #expect(card.tags.isEmpty)
        #expect(card.visibleInlineText == "#123 keep this raw")
        #expect(card.visibleInlineTagRanges.isEmpty)
    }

    @Test
    func captureCardUsesLegacyFallbackOnlyForBodyOnlyStoredTags() {
        let card = CaptureCard(
            text: "legacy body only",
            tags: [
                CaptureTag(rawValue: "bug"),
                CaptureTag(rawValue: "ui"),
            ].compactMap { $0 },
            createdAt: .now
        )

        #expect(card.visibleInlineText == "#bug #ui legacy body only")
        #expect(card.visibleInlineTagRanges == [
            NSRange(location: 0, length: 4),
            NSRange(location: 5, length: 3),
        ])
    }

    @Test
    func captureCardMergesInlineAndExplicitCanonicalTags() {
        let card = CaptureCard(
            text: "Fix #bug before handoff",
            tags: [
                CaptureTag(rawValue: "ui"),
                CaptureTag(rawValue: "bug"),
            ].compactMap { $0 },
            createdAt: .now
        )

        #expect(card.tags.map(\.name) == ["bug", "ui"])
        #expect(card.visibleInlineText == "Fix #bug before handoff")
        #expect(card.visibleInlineTagRanges == [
            NSRange(location: 4, length: 4),
        ])
    }

    @Test
    func captureCardJSONCodecRoundTrip() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastCopiedAt = Date(timeIntervalSince1970: 1_700_001_000)
        let original = CaptureCard(
            id: id,
            text: "round-trip test with #bug",
            createdAt: createdAt,
            screenshotPath: "/tmp/screenshot.png",
            lastCopiedAt: lastCopiedAt,
            sortOrder: 42.0
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CaptureCard.self, from: data)

        #expect(decoded == original)
        #expect(decoded.id == id)
        #expect(decoded.text == "round-trip test with #bug")
        #expect(decoded.tags.map(\.name) == ["bug"])
        #expect(decoded.createdAt == createdAt)
        #expect(decoded.screenshotPath == "/tmp/screenshot.png")
        #expect(decoded.lastCopiedAt == lastCopiedAt)
        #expect(decoded.sortOrder == 42.0)
    }

    @Test
    func captureCardJSONCodecRoundTripMinimalFields() throws {
        let original = CaptureCard(
            text: "minimal card",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CaptureCard.self, from: data)

        #expect(decoded == original)
        #expect(decoded.tags.isEmpty)
        #expect(decoded.screenshotPath == nil)
        #expect(decoded.lastCopiedAt == nil)
        #expect(decoded.sortOrder == original.createdAt.timeIntervalSinceReferenceDate)
    }

    @Test
    func captureCardDecodesCanonicalTagsFromRawTextWhenTagsFieldIsMissing() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "text": "legacy card with #bug and #ui",
            "createdAt": \(createdAt.timeIntervalSinceReferenceDate)
        }
        """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CaptureCard.self, from: Data(json.utf8))

        #expect(decoded.id == id)
        #expect(decoded.text == "legacy card with #bug and #ui")
        #expect(decoded.tags.map(\.name) == ["bug", "ui"])
        #expect(decoded.sortOrder == createdAt.timeIntervalSinceReferenceDate)
    }

    @Test
    func captureCardDecodesWithMissingSortOrderFallback() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "text": "legacy card",
            "createdAt": \(createdAt.timeIntervalSinceReferenceDate)
        }
        """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CaptureCard.self, from: Data(json.utf8))

        #expect(decoded.id == id)
        #expect(decoded.text == "legacy card")
        #expect(decoded.tags.isEmpty)
        #expect(decoded.sortOrder == createdAt.timeIntervalSinceReferenceDate)
    }
}
