import XCTest
@testable import PromptCueCore

final class ContentClassifierTests: XCTestCase {

    // MARK: - Plain

    func testEmptyStringReturnsPlain() {
        let result = ContentClassifier.classify("")
        XCTAssertEqual(result.primaryType, .plain)
        XCTAssertNil(result.span)
    }

    func testWhitespaceOnlyReturnsPlain() {
        let result = ContentClassifier.classify("   \n\t  ")
        XCTAssertEqual(result.primaryType, .plain)
    }

    func testPlainTextReturnsPlain() {
        let result = ContentClassifier.classify("Just a normal sentence about coding")
        XCTAssertEqual(result.primaryType, .plain)
    }

    // MARK: - Path

    func testTildePathDetected() {
        let result = ContentClassifier.classify("~/projects/crest/lib/auth.dart")
        XCTAssertEqual(result.primaryType, .path)
        XCTAssertEqual(result.span?.matchedText, "~/projects/crest/lib/auth.dart")
    }

    func testAbsolutePathDetected() {
        let result = ContentClassifier.classify("/usr/local/bin/thing")
        XCTAssertEqual(result.primaryType, .path)
        XCTAssertEqual(result.span?.matchedText, "/usr/local/bin/thing")
    }

    func testRelativePathDetected() {
        let result = ContentClassifier.classify("./src/components/Button.tsx")
        XCTAssertEqual(result.primaryType, .path)
        XCTAssertEqual(result.span?.matchedText, "./src/components/Button.tsx")
    }

    func testPathInSentence() {
        let result = ContentClassifier.classify("Check the file at ~/Documents/notes.md please")
        XCTAssertEqual(result.primaryType, .path)
        XCTAssertEqual(result.span?.matchedText, "~/Documents/notes.md")
    }

    // MARK: - Link

    func testHttpsLinkDetected() {
        let result = ContentClassifier.classify("https://pub.dev/packages/riverpod")
        XCTAssertEqual(result.primaryType, .link)
        XCTAssertEqual(result.span?.matchedText, "https://pub.dev/packages/riverpod")
    }

    func testHttpLinkDetected() {
        let result = ContentClassifier.classify("http://localhost:3000/api/v1")
        XCTAssertEqual(result.primaryType, .link)
        XCTAssertEqual(result.span?.matchedText, "http://localhost:3000/api/v1")
    }

    func testLinkInSentence() {
        let result = ContentClassifier.classify("Visit https://example.com/docs for more info")
        XCTAssertEqual(result.primaryType, .link)
        XCTAssertEqual(result.span?.matchedText, "https://example.com/docs")
    }

    // MARK: - Secret

    func testAnthropicKeyDetected() {
        let result = ContentClassifier.classify("sk-ant-abc123def456xyz")
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testGitHubTokenDetected() {
        let key = "ghp_" + String(repeating: "a", count: 36)
        let result = ContentClassifier.classify(key)
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testAWSKeyDetected() {
        let result = ContentClassifier.classify("AKIAIOSFODNN7EXAMPLE")
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testStripeLiveKeyDetected() {
        let result = ContentClassifier.classify("sk-live-abc123def456xyz")
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testSlackBotTokenDetected() {
        let result = ContentClassifier.classify("xoxb-123456789-abcdef")
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testOpenAIKeyDetected() {
        let key = "sk-" + String(repeating: "a", count: 48)
        let result = ContentClassifier.classify(key)
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testOpenAIProjKeyDetected() {
        let key = "sk-proj-" + String(repeating: "a", count: 48)
        let result = ContentClassifier.classify(key)
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testVercelTokenDetected() {
        let key = "vc_" + String(repeating: "a", count: 32)
        let result = ContentClassifier.classify(key)
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testSupabaseTokenDetected() {
        let key = "sbp_" + String(repeating: "a", count: 32)
        let result = ContentClassifier.classify(key)
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testNpmTokenDetected() {
        let key = "npm_" + String(repeating: "a", count: 36)
        let result = ContentClassifier.classify(key)
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testJWTDetected() {
        // Realistic JWT with long header/payload/signature segments
        let header = String(repeating: "a", count: 36)
        let payload = String(repeating: "b", count: 80)
        let signature = String(repeating: "c", count: 43)
        let jwt = "eyJ\(header).\(payload).\(signature)"
        let result = ContentClassifier.classify(jwt)
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testShortBase64SegmentsNotDetectedAsJWT() {
        // Short segments (< 36 chars each) should not trigger JWT detection
        let fakeJWT = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0.abc"
        let result = ContentClassifier.classify(fakeJWT)
        XCTAssertNotEqual(result.primaryType, .secret)
    }

    // MARK: - Priority

    func testSecretTakesPriorityOverLink() {
        let text = "https://api.example.com?key=sk-ant-abc123def456xyz"
        let result = ContentClassifier.classify(text)
        XCTAssertEqual(result.primaryType, .secret)
    }

    func testLinkTakesPriorityOverPath() {
        let text = "https://example.com/usr/local/bin"
        let result = ContentClassifier.classify(text)
        XCTAssertEqual(result.primaryType, .link)
    }

    // MARK: - Span Range

    func testSpanRangeIsCorrect() {
        let text = "Check https://example.com for details"
        let result = ContentClassifier.classify(text)
        guard let span = result.span else {
            XCTFail("Expected a span")
            return
        }
        XCTAssertEqual(String(text[span.range]), "https://example.com")
    }
}
