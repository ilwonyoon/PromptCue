import XCTest
@testable import PromptCueCore

final class ContentDisplayFormatterTests: XCTestCase {
    func testSecretMaskingPreservesSentenceStructure() {
        let text = "token: sk-ant-abc123def456xyz987"
        let classification = ContentClassifier.classify(text)

        let configuration = ContentDisplayFormatter.configuration(
            for: text,
            classification: classification
        )

        XCTAssertEqual(configuration.text, "token: \(SecretMasker.mask("sk-ant-abc123def456xyz987"))")
        XCTAssertFalse(configuration.prefersSingleLine)
        XCTAssertEqual(configuration.truncation, .none)
    }

    func testStandaloneLinkUsesSingleLineTailTruncation() {
        let text = "https://example.com/a/really/long/link"
        let classification = ContentClassifier.classify(text)

        let configuration = ContentDisplayFormatter.configuration(
            for: text,
            classification: classification
        )

        XCTAssertEqual(configuration.text, text)
        XCTAssertTrue(configuration.prefersSingleLine)
        XCTAssertEqual(configuration.truncation, .tail)
    }

    func testLinkInsideSentenceStaysMultilineBodyText() {
        let text = "Read https://example.com/docs when you have time"
        let classification = ContentClassifier.classify(text)

        let configuration = ContentDisplayFormatter.configuration(
            for: text,
            classification: classification
        )

        XCTAssertEqual(configuration.text, text)
        XCTAssertFalse(configuration.prefersSingleLine)
        XCTAssertEqual(configuration.truncation, .none)
    }

    func testStandalonePathUsesSingleLineHeadTruncation() {
        let text = "~/very/long/workspace/project/src/components/CaptureCardView.swift"
        let classification = ContentClassifier.classify(text)

        let configuration = ContentDisplayFormatter.configuration(
            for: text,
            classification: classification
        )

        XCTAssertEqual(configuration.text, text)
        XCTAssertTrue(configuration.prefersSingleLine)
        XCTAssertEqual(configuration.truncation, .head)
    }

    func testPathInsideSentenceStaysMultilineBodyText() {
        let text = "Check ~/Documents/notes.md before shipping"
        let classification = ContentClassifier.classify(text)

        let configuration = ContentDisplayFormatter.configuration(
            for: text,
            classification: classification
        )

        XCTAssertEqual(configuration.text, text)
        XCTAssertFalse(configuration.prefersSingleLine)
        XCTAssertEqual(configuration.truncation, .none)
    }
}
