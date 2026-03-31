import Foundation

public enum ContentClassifier {
    private static let secretPatterns: [NSRegularExpression] = {
        let patterns = [
            // Anthropic
            #"sk-ant-[A-Za-z0-9_-]{10,}"#,
            // GitHub
            #"ghp_[A-Za-z0-9]{30,}"#,
            #"gho_[A-Za-z0-9]{30,}"#,
            // AWS
            #"AKIA[A-Z0-9]{12,}"#,
            // Stripe
            #"sk-live-[A-Za-z0-9_-]{10,}"#,
            // OpenAI (legacy sk- and new sk-proj- prefix)
            #"sk-proj-[A-Za-z0-9_-]{20,}"#,
            #"sk-[A-Za-z0-9_-]{20,}"#,
            // Slack
            #"xoxb-[A-Za-z0-9-]+"#,
            // GitLab
            #"glpat-[A-Za-z0-9_-]{20,}"#,
            // Vercel
            #"vc_[A-Za-z0-9]{20,}"#,
            // Supabase
            #"sbp_[A-Za-z0-9]{20,}"#,
            // npm automation tokens
            #"npm_[A-Za-z0-9]{20,}"#,
            // JWT: header.payload.signature — require long segments to reduce false positives
            #"eyJ[A-Za-z0-9_-]{36,}\.[A-Za-z0-9_-]{36,}\.[A-Za-z0-9_-]{20,}"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static let linkPatterns: [NSRegularExpression] = {
        [#"https?://[^\s]{1,2048}"#].compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static let pathPatterns: [NSRegularExpression] = {
        let patterns = [
            #"~/[^\s]{1,1024}"#,
            #"\./[^\s]{1,1024}"#,
            #"(?:^|\s)(/[a-zA-Z][^\s]{0,1024}(?:/[^\s]{1,1024})+)"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .anchorsMatchLines) }
    }()

    public static func classify(_ text: String) -> ContentClassification {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .plain
        }

        // Most secret patterns require at least 10 chars (e.g., "xoxb-" + chars)
        // Links require at least 8 ("http://x"), paths at least 4 ("~/ab")
        guard trimmed.count >= 4 else {
            return .plain
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Priority 1: Secret
        for pattern in secretPatterns {
            if let match = pattern.firstMatch(in: text, range: fullRange) {
                return buildClassification(text: text, matchRange: match.range, type: .secret)
            }
        }

        // Priority 2: Link
        for pattern in linkPatterns {
            if let match = pattern.firstMatch(in: text, range: fullRange) {
                return buildClassification(text: text, matchRange: match.range, type: .link)
            }
        }

        // Priority 3: Path
        for pattern in pathPatterns {
            if let match = pattern.firstMatch(in: text, range: fullRange) {
                let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                let resolvedRange = captureRange.location != NSNotFound ? captureRange : match.range
                return buildClassification(text: text, matchRange: resolvedRange, type: .path)
            }
        }

        return .plain
    }

    private static func buildClassification(
        text: String,
        matchRange: NSRange,
        type: ContentType
    ) -> ContentClassification {
        guard let swiftRange = Range(matchRange, in: text) else {
            return .plain
        }

        let matchedText = String(text[swiftRange])
        let span = DetectedSpan(range: swiftRange, matchedText: matchedText, type: type)

        return ContentClassification(primaryType: type, span: span)
    }
}
