import Foundation

public struct ExportSuffix: Equatable, Sendable {
    public static let off = ExportSuffix(nil)

    public let rawValue: String?

    public init(_ rawValue: String?) {
        self.rawValue = rawValue
    }

    var normalizedValue: String? {
        guard let rawValue else {
            return nil
        }

        let normalizedLineEndings = rawValue
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedLineEndings.isEmpty == false else {
            return nil
        }

        return normalizedLineEndings
    }
}

public enum ExportFormatter {
    private static let standaloneEmailPattern =
        #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,63}$"#
    private static let standaloneLocalhostPattern =
        #"^(?:(?:https?)://)?localhost(?::\d{1,5})?(?:/[^\s?#]*)?(?:\?[^\s#]*)?(?:#[^\s]*)?$"#

    public static func string(for cards: [CaptureCard]) -> String {
        string(for: cards, suffix: .off)
    }

    public static func clipboardString(for cards: [CaptureCard], suffix: ExportSuffix) -> String {
        clipboardString(for: cards, suffix: suffix, attachmentFlags: nil)
    }

    /// Build clipboard text with optional per-card `[Image]` markers.
    /// `attachmentFlags` must match `cards` count when provided.
    public static func clipboardString(
        for cards: [CaptureCard],
        suffix: ExportSuffix,
        attachmentFlags: [Bool]?
    ) -> String {
        if let rawStandalonePayload = rawStandalonePayload(for: cards) {
            let hasAttachment = attachmentFlags?.first ?? false
            return hasAttachment ? "[Image] \(rawStandalonePayload)" : rawStandalonePayload
        }

        return string(for: cards, suffix: suffix, attachmentFlags: attachmentFlags)
    }

    public static func string(for cards: [CaptureCard], suffix: ExportSuffix) -> String {
        string(for: cards, suffix: suffix, attachmentFlags: nil)
    }

    public static func string(
        for cards: [CaptureCard],
        suffix: ExportSuffix,
        attachmentFlags: [Bool]?
    ) -> String {
        let basePayload = cards.enumerated()
            .map { index, card in
                let hasAttachment = attachmentFlags.map { index < $0.count && $0[index] } ?? false
                let imageTag = hasAttachment ? "[Image] " : ""
                return "\u{2022} \(imageTag)\(card.text)"
            }
            .joined(separator: "\n")

        guard let normalizedSuffix = suffix.normalizedValue, basePayload.isEmpty == false else {
            return basePayload
        }

        return basePayload + "\n\n" + normalizedSuffix
    }

    public static func string(for cards: [CaptureCard], suffix: String?) -> String {
        string(for: cards, suffix: ExportSuffix(suffix))
    }

    private static func rawStandalonePayload(for cards: [CaptureCard]) -> String? {
        guard cards.count == 1, let card = cards.first else {
            return nil
        }

        let trimmedText = card.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if matches(trimmedText, pattern: standaloneEmailPattern) ||
            matches(trimmedText, pattern: standaloneLocalhostPattern) {
            return trimmedText
        }

        let classification = ContentClassifier.classify(card.text)
        guard let span = classification.span else {
            return nil
        }

        guard trimmedText == span.matchedText else {
            return nil
        }

        switch classification.primaryType {
        case .link, .path, .secret:
            return span.matchedText
        case .plain:
            return nil
        }
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
