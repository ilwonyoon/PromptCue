import AppKit
import PromptCueCore
import SwiftUI

struct InteractiveDetectedTextView: View {
    struct StyledText {
        let displayConfiguration: ContentDisplayConfiguration
        let renderedText: AttributedString
        let measurementText: NSAttributedString
        let cacheSignature: UInt64
        /// Carried separately so the SwiftUI body can re-apply the base
        /// color at draw time (it is *not* baked into `renderedText`).
        let baseColor: Color
    }

    private let styledText: StyledText
    let multilineLineLimit: Int?

    init(
        text: String,
        classification: ContentClassification,
        baseColor: Color,
        highlightedRanges: [NSRange] = [],
        multilineLineLimit: Int? = nil
    ) {
        styledText = Self.styledText(
            text: text,
            classification: classification,
            baseColor: baseColor,
            highlightedRanges: highlightedRanges
        )
        self.multilineLineLimit = multilineLineLimit
    }

    init(
        styledText: StyledText,
        multilineLineLimit: Int? = nil
    ) {
        self.styledText = styledText
        self.multilineLineLimit = multilineLineLimit
    }

    static func displayConfiguration(
        text: String,
        classification: ContentClassification
    ) -> ContentDisplayConfiguration {
        ContentDisplayFormatter.configuration(for: text, classification: classification)
    }

    private var displayConfiguration: ContentDisplayConfiguration {
        styledText.displayConfiguration
    }

    var body: some View {
        Text(styledText.renderedText)
            // Apply base color at the SwiftUI Text level rather than baking
            // it into `renderedText`; SwiftUI re-runs `.foregroundStyle`
            // each redraw, so dynamic-NSColor tokens stay live across
            // light/dark transitions. Highlighted ranges already carry their
            // own per-run foreground attribute and override this default.
            .foregroundStyle(styledText.baseColor)
            .lineLimit(styledText.displayConfiguration.prefersSingleLine ? 1 : multilineLineLimit)
            .truncationMode(styledText.displayConfiguration.swiftUITruncationMode)
            .multilineTextAlignment(.leading)
            .lineSpacing(PrimitiveTokens.Space.xxxs)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func layoutText(text: String, classification: ContentClassification) -> String {
        displayConfiguration(text: text, classification: classification).text
    }

    static func styledText(
        text: String,
        classification: ContentClassification,
        baseColor: Color,
        highlightedRanges: [NSRange] = []
    ) -> StyledText {
        let displayConfiguration = displayConfiguration(text: text, classification: classification)
        let displayText = displayConfiguration.text
        var renderedText = AttributedString(displayText)
        renderedText.font = PrimitiveTokens.Typography.body
        // NOTE: We intentionally do NOT bake the base color into the
        // AttributedString here. SwiftUI resolves a Color into a baked
        // attribute at the moment we assign it to `foregroundColor`, even
        // when the underlying NSColor is a dynamic provider. That captured
        // color survives across system theme changes — the canonical way
        // we kept regressing the Stack card text in dark/light flips.
        // Apply the base color at the SwiftUI Text level instead via
        // `.foregroundStyle(baseColor)` (see body), where SwiftUI re-runs
        // the modifier each redraw.

        let measurementText = NSMutableAttributedString(
            string: displayText,
            attributes: [
                .font: NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.body),
                .paragraphStyle: measurementParagraphStyle,
            ]
        )

        let fullRange = NSRange(location: 0, length: (displayText as NSString).length)
        let validRanges = highlightedRanges
            .map { NSIntersectionRange($0, fullRange) }
            .filter { $0.length > 0 }

        for range in validRanges {
            guard let stringRange = Range(range, in: displayText),
                  let attributedRange = Range(stringRange, in: renderedText) else {
                continue
            }

            renderedText[attributedRange].font = PrimitiveTokens.Typography.bodyStrong
            // Accent color is the system-tinted accent (controlAccentColor
            // under the hood), which AppKit re-resolves for us — safe to
            // bake into the AttributedString.
            renderedText[attributedRange].foregroundColor = SemanticTokens.Text.accent
            measurementText.addAttribute(
                .font,
                value: NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.body, weight: .medium),
                range: range
            )
        }

        return StyledText(
            displayConfiguration: displayConfiguration,
            renderedText: renderedText,
            measurementText: measurementText,
            cacheSignature: styleCacheSignature(for: displayText, highlightedRanges: validRanges),
            baseColor: baseColor
        )
    }

    private static var measurementParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.alignment = .left
        style.lineSpacing = PrimitiveTokens.Space.xxxs
        return style
    }()

    private static func styleCacheSignature(for text: String, highlightedRanges: [NSRange]) -> UInt64 {
        var hash = stableHash(text)
        for range in highlightedRanges {
            hash ^= UInt64(range.location)
            hash &*= 1_099_511_628_211
            hash ^= UInt64(range.length)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

private extension ContentDisplayConfiguration {
    var swiftUITruncationMode: Text.TruncationMode {
        switch truncation {
        case .none, .tail:
            return .tail
        case .head:
            return .head
        }
    }
}
