import Foundation

public enum ContentDisplayTruncation: String, Equatable, Sendable {
    case none
    case head
    case tail
}

public struct ContentDisplayConfiguration: Equatable, Sendable {
    public let text: String
    public let prefersSingleLine: Bool
    public let truncation: ContentDisplayTruncation
    public let layoutVariant: Int

    public init(
        text: String,
        prefersSingleLine: Bool,
        truncation: ContentDisplayTruncation,
        layoutVariant: Int
    ) {
        self.text = text
        self.prefersSingleLine = prefersSingleLine
        self.truncation = truncation
        self.layoutVariant = layoutVariant
    }
}

public enum ContentDisplayFormatter {
    public static func configuration(
        for text: String,
        classification: ContentClassification
    ) -> ContentDisplayConfiguration {
        guard let span = classification.span else {
            return .init(
                text: text,
                prefersSingleLine: false,
                truncation: .none,
                layoutVariant: 0
            )
        }

        switch classification.primaryType {
        case .secret:
            return .init(
                text: replacingSpan(in: text, span: span, with: SecretMasker.mask(span.matchedText)),
                prefersSingleLine: false,
                truncation: .none,
                layoutVariant: 1
            )
        case .link:
            guard isStandaloneSpan(text: text, span: span) else {
                return .init(
                    text: text,
                    prefersSingleLine: false,
                    truncation: .none,
                    layoutVariant: 0
                )
            }

            return .init(
                text: span.matchedText,
                prefersSingleLine: true,
                truncation: .tail,
                layoutVariant: 2
            )
        case .path:
            guard isStandaloneSpan(text: text, span: span) else {
                return .init(
                    text: text,
                    prefersSingleLine: false,
                    truncation: .none,
                    layoutVariant: 0
                )
            }

            return .init(
                text: span.matchedText,
                prefersSingleLine: true,
                truncation: .head,
                layoutVariant: 3
            )
        case .plain:
            return .init(
                text: text,
                prefersSingleLine: false,
                truncation: .none,
                layoutVariant: 0
            )
        }
    }

    private static func isStandaloneSpan(text: String, span: DetectedSpan) -> Bool {
        let prefix = text[text.startIndex..<span.range.lowerBound]
        let suffix = text[span.range.upperBound..<text.endIndex]
        let whitespace = CharacterSet.whitespacesAndNewlines

        return String(prefix).trimmingCharacters(in: whitespace).isEmpty
            && String(suffix).trimmingCharacters(in: whitespace).isEmpty
    }

    private static func replacingSpan(
        in text: String,
        span: DetectedSpan,
        with replacement: String
    ) -> String {
        let prefix = text[text.startIndex..<span.range.lowerBound]
        let suffix = text[span.range.upperBound..<text.endIndex]
        return String(prefix) + replacement + String(suffix)
    }
}
