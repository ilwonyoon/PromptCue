import Foundation

public struct CaptureTag: Codable, Hashable, Sendable, Comparable {
    public let name: String

    public init?(rawValue: String) {
        guard let normalized = Self.normalize(rawValue) else {
            return nil
        }

        self.name = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let tag = CaptureTag(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid capture tag: \(rawValue)"
            )
        }

        self = tag
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    public var displayText: String {
        "#\(name)"
    }

    public static func < (lhs: CaptureTag, rhs: CaptureTag) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    public static func normalize(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard !body.isEmpty else {
            return nil
        }

        let normalized = body.lowercased()
        guard let firstScalar = normalized.unicodeScalars.first,
              Self.isLeadingScalar(firstScalar),
              normalized.unicodeScalars.dropFirst().allSatisfy(Self.isBodyScalar) else {
            return nil
        }

        return normalized
    }

    public static func deduplicatePreservingOrder(_ tags: [CaptureTag]) -> [CaptureTag] {
        var seen = Set<CaptureTag>()
        return tags.filter { seen.insert($0).inserted }
    }

    public static func canonicalize(rawValues: [String]) -> [CaptureTag] {
        deduplicatePreservingOrder(rawValues.compactMap(CaptureTag.init(rawValue:)))
    }

    public static func encodeJSONArray(_ tags: [CaptureTag]) -> String? {
        let canonicalTags = deduplicatePreservingOrder(tags)
        guard let data = try? JSONEncoder().encode(canonicalTags),
              let json = String(data: data, encoding: .utf8) else {
            assertionFailure("Failed to encode capture tags JSON")
            return "[]"
        }

        return json
    }

    public static func decodeJSONArray(_ json: String?) -> [CaptureTag] {
        guard let json,
              let data = json.data(using: .utf8) else {
            return []
        }

        if let rawValues = try? JSONDecoder().decode([String].self, from: data) {
            return canonicalize(rawValues: rawValues)
        }

        if let tags = try? JSONDecoder().decode([CaptureTag].self, from: data) {
            return deduplicatePreservingOrder(tags)
        }

        return []
    }

    fileprivate static func isLeadingScalar(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 97 && scalar.value <= 122
    }

    fileprivate static func isBodyScalar(_ scalar: UnicodeScalar) -> Bool {
        isLeadingScalar(scalar)
            || (scalar.value >= 48 && scalar.value <= 57)
            || scalar.value == 95
            || scalar.value == 45
    }
}

public struct CaptureTagPrefixParseResult: Equatable, Sendable {
    public let tags: [CaptureTag]
    public let bodyText: String
    public let committedTokenRanges: [NSRange]
    public let bodyStartUTF16Offset: Int

    public init(
        tags: [CaptureTag],
        bodyText: String,
        committedTokenRanges: [NSRange],
        bodyStartUTF16Offset: Int
    ) {
        self.tags = tags
        self.bodyText = bodyText
        self.committedTokenRanges = committedTokenRanges
        self.bodyStartUTF16Offset = bodyStartUTF16Offset
    }
}

public struct CaptureTagCompletionContext: Equatable, Sendable {
    public let rawToken: String
    public let normalizedPrefix: String?
    public let replacementRange: NSRange

    public init(
        rawToken: String,
        normalizedPrefix: String?,
        replacementRange: NSRange
    ) {
        self.rawToken = rawToken
        self.normalizedPrefix = normalizedPrefix
        self.replacementRange = replacementRange
    }
}

public enum CaptureTagText {
    public static func inlineDisplayText(
        tags: [CaptureTag],
        bodyText: String
    ) -> String {
        serializedText(
            tags: tags,
            bodyText: bodyText,
            includesTrailingSpaceWhenBodyIsEmpty: false
        )
    }

    public static func editorText(
        tags: [CaptureTag],
        bodyText: String
    ) -> String {
        serializedText(
            tags: tags,
            bodyText: bodyText,
            includesTrailingSpaceWhenBodyIsEmpty: true
        )
    }

    private static func serializedText(
        tags: [CaptureTag],
        bodyText: String,
        includesTrailingSpaceWhenBodyIsEmpty: Bool
    ) -> String {
        let normalizedTags = CaptureTag.deduplicatePreservingOrder(tags)
        let trimmedBodyText = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTags.isEmpty else {
            return trimmedBodyText
        }

        let tagPrefix = normalizedTags.map(\.displayText).joined(separator: " ")
        guard !trimmedBodyText.isEmpty else {
            return includesTrailingSpaceWhenBodyIsEmpty ? "\(tagPrefix) " : tagPrefix
        }

        return "\(tagPrefix) \(trimmedBodyText)"
    }

    public static func inlineDisplayTagRanges(
        tags: [CaptureTag],
        bodyText: String
    ) -> [NSRange] {
        let normalizedTags = CaptureTag.deduplicatePreservingOrder(tags)
        let trimmedBodyText = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTags.isEmpty else {
            return []
        }

        var ranges: [NSRange] = []
        ranges.reserveCapacity(normalizedTags.count)
        var cursor = 0

        for (index, tag) in normalizedTags.enumerated() {
            let displayText = tag.displayText
            let length = (displayText as NSString).length
            ranges.append(NSRange(location: cursor, length: length))
            cursor += length

            let hasTrailingSeparator = index < normalizedTags.count - 1 || !trimmedBodyText.isEmpty
            if hasTrailingSeparator {
                cursor += 1
            }
        }

        return ranges
    }

    public static func parseCommittedPrefix(in text: String) -> CaptureTagPrefixParseResult {
        let nsText = text as NSString
        let length = nsText.length
        var cursor = 0
        var committedTags: [CaptureTag] = []
        var committedRanges: [NSRange] = []

        while cursor < length {
            guard nsText.substring(with: NSRange(location: cursor, length: 1)) == "#" else {
                break
            }

            let tokenStart = cursor
            cursor += 1
            guard cursor < length else {
                cursor = tokenStart
                break
            }

            let leadingScalar = unicodeScalar(in: nsText, at: cursor)
            guard let leadingScalar,
                  CaptureTag.normalize(String(leadingScalar)) != nil else {
                cursor = tokenStart
                break
            }

            cursor += 1
            while cursor < length,
                  let scalar = unicodeScalar(in: nsText, at: cursor),
                  isTagBodyScalar(scalar) {
                cursor += 1
            }

            guard cursor < length,
                  let separatorScalar = unicodeScalar(in: nsText, at: cursor),
                  CharacterSet.whitespacesAndNewlines.contains(separatorScalar) else {
                cursor = tokenStart
                break
            }

            let tokenRange = NSRange(location: tokenStart, length: cursor - tokenStart)
            if let tag = CaptureTag(rawValue: nsText.substring(with: tokenRange)) {
                committedTags.append(tag)
                committedRanges.append(tokenRange)
            } else {
                cursor = tokenStart
                break
            }

            while cursor < length,
                  let scalar = unicodeScalar(in: nsText, at: cursor),
                  CharacterSet.whitespacesAndNewlines.contains(scalar) {
                cursor += 1
            }
        }

        let deduplicatedTags = CaptureTag.deduplicatePreservingOrder(committedTags)
        let bodyText = cursor < length
            ? nsText.substring(from: cursor)
            : ""

        return CaptureTagPrefixParseResult(
            tags: deduplicatedTags,
            bodyText: bodyText,
            committedTokenRanges: committedRanges,
            bodyStartUTF16Offset: cursor
        )
    }

    public static func completionContext(
        in text: String,
        caretUTF16Offset: Int
    ) -> CaptureTagCompletionContext? {
        let parseResult = parseCommittedPrefix(in: text)
        let nsText = text as NSString
        let length = nsText.length
        let clampedCaret = max(0, min(caretUTF16Offset, length))
        guard clampedCaret >= parseResult.bodyStartUTF16Offset else {
            return nil
        }

        let bodyRange = NSRange(
            location: parseResult.bodyStartUTF16Offset,
            length: length - parseResult.bodyStartUTF16Offset
        )
        let bodyText = nsText.substring(with: bodyRange)
        guard bodyText.hasPrefix("#") else {
            return nil
        }

        let bodyNSString = bodyText as NSString
        var tokenLength = 1
        while tokenLength < bodyNSString.length,
              let scalar = unicodeScalar(in: bodyNSString, at: tokenLength),
              isTagBodyScalar(scalar) {
            tokenLength += 1
        }

        let candidateRange = NSRange(
            location: parseResult.bodyStartUTF16Offset,
            length: tokenLength
        )
        guard NSMaxRange(candidateRange) >= clampedCaret else {
            return nil
        }

        let rawToken = nsText.substring(with: candidateRange)
        let tokenBody = rawToken.hasPrefix("#") ? String(rawToken.dropFirst()) : rawToken
        let normalizedPrefix: String?
        if tokenBody.isEmpty {
            normalizedPrefix = ""
        } else {
            normalizedPrefix = CaptureTag.normalize(tokenBody)
                ?? normalizePrefix(tokenBody)
        }

        return CaptureTagCompletionContext(
            rawToken: rawToken,
            normalizedPrefix: normalizedPrefix,
            replacementRange: candidateRange
        )
    }

    private static func normalizePrefix(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.lowercased()
        guard let firstScalar = normalized.unicodeScalars.first,
              CaptureTag.isLeadingScalar(firstScalar),
              normalized.unicodeScalars.dropFirst().allSatisfy(isTagBodyScalar) else {
            return nil
        }

        return normalized
    }

    private static func unicodeScalar(
        in text: NSString,
        at utf16Offset: Int
    ) -> UnicodeScalar? {
        guard utf16Offset >= 0, utf16Offset < text.length else {
            return nil
        }

        let value = text.character(at: utf16Offset)
        return UnicodeScalar(value)
    }

    private static func isTagBodyScalar(_ scalar: UnicodeScalar) -> Bool {
        CaptureTag.isBodyScalar(scalar)
    }
}
