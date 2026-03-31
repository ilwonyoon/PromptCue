import Foundation

public struct CaptureTag: Codable, Hashable, Sendable, Comparable {
    public let name: String

    public init?(rawValue: String) {
        guard let normalized = Self.normalize(rawValue) else {
            return nil
        }

        self.name = normalized
    }

    fileprivate init(normalizedName: String) {
        self.name = normalizedName
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
              Self.isLeadingScalar(firstScalar) else {
            return nil
        }

        // Match the inline parser: ASCII-led tags only allow ASCII body chars,
        // so non-ASCII letters terminate the tag (e.g. "#Bug처리" → "bug").
        // When used as a full-string validator (rawValue input), trailing characters
        // after the truncation point make the overall input invalid (return nil)
        // unless all trailing chars are also non-ASCII letters (valid end-boundary
        // characters like Korean adjacent to the tag). Only pure whitespace or
        // punctuation trailing content causes rejection.
        let asciiLed = Self.isASCIILeadingScalar(firstScalar)
        let bodyScalars = normalized.unicodeScalars.dropFirst()

        if asciiLed {
            // Collect only the leading ASCII-valid body scalars, then verify that
            // anything left over consists solely of non-ASCII letter scalars
            // (i.e. valid adjacent-text boundary chars, not spaces or punctuation).
            var result = String(firstScalar)
            var trailingScalars = bodyScalars.makeIterator()
            while let scalar = trailingScalars.next() {
                guard Self.isASCIIBodyScalar(scalar) else {
                    // Trailing scalar must be a non-ASCII letter (valid boundary);
                    // otherwise the full input is malformed.
                    guard scalar.value > 127 && CharacterSet.letters.contains(scalar) else {
                        return nil
                    }
                    // Verify all remaining scalars are also non-ASCII letters.
                    while let remaining = trailingScalars.next() {
                        guard remaining.value > 127 && CharacterSet.letters.contains(remaining) else {
                            return nil
                        }
                    }
                    break
                }
                result.unicodeScalars.append(scalar)
            }
            return result
        } else {
            // Non-ASCII-led tag: all body scalars must pass the broad check.
            guard bodyScalars.allSatisfy(Self.isBodyScalar) else {
                return nil
            }
            return normalized
        }
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

    /// Returns true for any Unicode letter scalar.
    /// This is intentionally broader than just ASCII or Hangul — it covers CJK, Latin
    /// extended, Cyrillic, and all other script letters recognized by Unicode.
    /// ASCII-led tags apply the narrower `isASCIIBodyScalar` rule instead (see `normalize`).
    fileprivate static func isLeadingScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.letters.contains(scalar)
    }

    fileprivate static func isBodyScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.letters.contains(scalar)
            || CharacterSet.decimalDigits.contains(scalar)
            || scalar.value == 95
            || scalar.value == 45
    }

    /// True for scalars that can extend a tag whose leading char was ASCII.
    /// Non-ASCII letters terminate an ASCII-led tag so that e.g. #Bug처리 → tag is "bug", not "bug처리".
    fileprivate static func isASCIIBodyScalar(_ scalar: UnicodeScalar) -> Bool {
        (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
            || (scalar.value >= 48 && scalar.value <= 57)
            || scalar.value == 95
            || scalar.value == 45
    }

    fileprivate static func isASCIILeadingScalar(_ scalar: UnicodeScalar) -> Bool {
        (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
    }
}

public struct CaptureTagInlineMatch: Equatable, Sendable {
    public let tag: CaptureTag
    public let range: NSRange

    public init(tag: CaptureTag, range: NSRange) {
        self.tag = tag
        self.range = range
    }
}

public struct CaptureTagInlineExtractionResult: Equatable, Sendable {
    public let tags: [CaptureTag]
    public let matches: [CaptureTagInlineMatch]

    public init(tags: [CaptureTag], matches: [CaptureTagInlineMatch]) {
        self.tags = tags
        self.matches = matches
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
    public static func extractCanonicalInlineTags(
        in text: String
    ) -> CaptureTagInlineExtractionResult {
        let matches = canonicalInlineTagMatches(in: text)
        let tags = CaptureTag.deduplicatePreservingOrder(matches.map(\.tag))

        return CaptureTagInlineExtractionResult(tags: tags, matches: matches)
    }

    public static func canonicalInlineTagMatches(in text: String) -> [CaptureTagInlineMatch] {
        let nsText = text as NSString
        let length = nsText.length
        guard length > 0 else {
            return []
        }

        var cursor = 0
        var matches: [CaptureTagInlineMatch] = []

        while cursor < length {
            guard nsText.character(at: cursor) == 35 else {
                cursor += 1
                continue
            }

            let tokenStart = cursor
            if !isValidTagStartBoundary(in: nsText, at: tokenStart) {
                cursor += 1
                continue
            }

            cursor += 1
            guard cursor < length,
                  let leadingScalar = unicodeScalar(in: nsText, at: cursor),
                  CaptureTag.normalize(String(leadingScalar)) != nil else {
                cursor = tokenStart + 1
                continue
            }

            let asciiLed = CaptureTag.isASCIILeadingScalar(leadingScalar)
            cursor += 1
            while cursor < length,
                  let scalar = unicodeScalar(in: nsText, at: cursor),
                  asciiLed ? CaptureTag.isASCIIBodyScalar(scalar) : CaptureTag.isBodyScalar(scalar) {
                cursor += 1
            }

            if let trailingScalar = unicodeScalar(in: nsText, at: cursor),
               !isValidTagEndBoundary(trailingScalar) {
                cursor = tokenStart + 1
                continue
            }

            let tokenRange = NSRange(location: tokenStart, length: cursor - tokenStart)
            let bodyRange = NSRange(location: tokenStart + 1, length: tokenRange.length - 1)
            guard let normalizedName = normalizedTagBody(in: nsText, range: bodyRange) else {
                cursor = tokenStart + 1
                continue
            }

            matches.append(
                CaptureTagInlineMatch(
                    tag: CaptureTag(normalizedName: normalizedName),
                    range: tokenRange
                )
            )
        }

        return matches
    }

    public static func inlineDisplayText(
        tags: [CaptureTag],
        bodyText: String
    ) -> String {
        bodyText
    }

    public static func editorText(
        tags: [CaptureTag],
        bodyText: String
    ) -> String {
        bodyText
    }

    public static func legacyInlineDisplayText(
        tags: [CaptureTag],
        bodyText: String,
        includesTrailingSpaceWhenBodyIsEmpty: Bool = false
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
        let normalizedTags = Set(CaptureTag.deduplicatePreservingOrder(tags))
        guard !normalizedTags.isEmpty else {
            return []
        }

        return canonicalInlineTagMatches(in: bodyText)
            .filter { normalizedTags.contains($0.tag) }
            .map(\.range)
    }

    public static func legacyInlineDisplayTagRanges(
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

            let asciiLed = CaptureTag.isASCIILeadingScalar(leadingScalar)
            cursor += 1
            while cursor < length,
                  let scalar = unicodeScalar(in: nsText, at: cursor),
                  asciiLed ? CaptureTag.isASCIIBodyScalar(scalar) : CaptureTag.isBodyScalar(scalar) {
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
        let nsText = text as NSString
        let length = nsText.length
        let clampedCaret = max(0, min(caretUTF16Offset, length))
        guard let tokenRange = completionTokenRange(
            in: nsText,
            caretUTF16Offset: clampedCaret
        ) else {
            return nil
        }

        let rawToken = nsText.substring(with: tokenRange)
        let bodyStart = tokenRange.location + 1
        let prefixLength = max(0, min(clampedCaret - bodyStart, nsText.length - bodyStart))
        let prefixBody = prefixLength > 0
            ? nsText.substring(with: NSRange(location: bodyStart, length: prefixLength))
            : ""
        let normalizedPrefix: String?
        if prefixBody.isEmpty {
            normalizedPrefix = ""
        } else {
            normalizedPrefix = CaptureTag.normalize(prefixBody) ?? normalizePrefix(prefixBody)
        }

        return CaptureTagCompletionContext(
            rawToken: rawToken,
            normalizedPrefix: normalizedPrefix,
            replacementRange: tokenRange
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
              normalized.unicodeScalars.dropFirst().allSatisfy(CaptureTag.isBodyScalar) else {
            return nil
        }

        return normalized
    }

    private static func normalizedTagBody(
        in text: NSString,
        range: NSRange
    ) -> String? {
        guard range.location != NSNotFound,
              range.length > 0,
              NSMaxRange(range) <= text.length else {
            return nil
        }

        let normalized = text.substring(with: range).lowercased()
        guard let firstScalar = normalized.unicodeScalars.first,
              CaptureTag.isLeadingScalar(firstScalar),
              normalized.unicodeScalars.dropFirst().allSatisfy(CaptureTag.isBodyScalar) else {
            return nil
        }

        return normalized
    }

    private static func isValidTagStartBoundary(in text: NSString, at tokenStart: Int) -> Bool {
        guard tokenStart > 0 else {
            return true
        }

        guard let previousScalar = unicodeScalar(in: text, at: tokenStart - 1) else {
            return true
        }

        return isPermittedAdjacentScalar(previousScalar)
    }

    private static func isValidTagEndBoundary(_ scalar: UnicodeScalar) -> Bool {
        isPermittedAdjacentScalar(scalar)
    }

    private static func isPermittedAdjacentScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 35:
            // Reject doubled hashes like "##tag" and adjacent hashtags without a separator.
            return false
        case 47:
            // Keep URL fragments like "/#section" out of inline tag parsing.
            return false
        default:
            // Non-ASCII letters (e.g. Korean, CJK) are valid boundaries even though they
            // are also valid tag body characters — a Korean word adjacent to #Tag does not
            // merge with the tag.
            if scalar.value > 127 && CharacterSet.letters.contains(scalar) {
                return true
            }
            return !CaptureTag.isBodyScalar(scalar)
        }
    }

    private static func completionTokenRange(
        in text: NSString,
        caretUTF16Offset: Int
    ) -> NSRange? {
        let length = text.length
        guard length > 0 else {
            return nil
        }

        var start = caretUTF16Offset
        while start > 0,
              let scalar = unicodeScalar(in: text, at: start - 1),
              CaptureTag.isBodyScalar(scalar) {
            start -= 1
        }

        guard start > 0,
              text.substring(with: NSRange(location: start - 1, length: 1)) == "#" else {
            return nil
        }

        let tokenStart = start - 1
        guard isValidTagStartBoundary(in: text, at: tokenStart) else {
            return nil
        }

        // Determine script of leading char to apply consistent body scalar set.
        let asciiLed: Bool
        if let leadingScalar = unicodeScalar(in: text, at: start) {
            asciiLed = CaptureTag.isASCIILeadingScalar(leadingScalar)
        } else {
            asciiLed = false
        }

        // Re-anchor start using the correct script-aware body scalar set.
        start = caretUTF16Offset
        while start > 0,
              let scalar = unicodeScalar(in: text, at: start - 1),
              asciiLed ? CaptureTag.isASCIIBodyScalar(scalar) : CaptureTag.isBodyScalar(scalar) {
            start -= 1
        }

        guard start > 0,
              text.substring(with: NSRange(location: start - 1, length: 1)) == "#" else {
            return nil
        }

        var end = caretUTF16Offset
        while end < length,
              let scalar = unicodeScalar(in: text, at: end),
              asciiLed ? CaptureTag.isASCIIBodyScalar(scalar) : CaptureTag.isBodyScalar(scalar) {
            end += 1
        }

        if let trailingScalar = unicodeScalar(in: text, at: end),
           !isValidTagEndBoundary(trailingScalar) {
            return nil
        }

        return NSRange(location: tokenStart, length: end - tokenStart)
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
}
