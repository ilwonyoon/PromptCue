import PromptCueCore
import SwiftUI

struct InteractiveDetectedTextView: View {
    let text: String
    let classification: ContentClassification
    let baseColor: Color
    let highlightedRanges: [NSRange]
    let multilineLineLimit: Int?

    init(
        text: String,
        classification: ContentClassification,
        baseColor: Color,
        highlightedRanges: [NSRange] = [],
        multilineLineLimit: Int? = nil
    ) {
        self.text = text
        self.classification = classification
        self.baseColor = baseColor
        self.highlightedRanges = highlightedRanges
        self.multilineLineLimit = multilineLineLimit
    }

    static func displayConfiguration(
        text: String,
        classification: ContentClassification
    ) -> ContentDisplayConfiguration {
        ContentDisplayFormatter.configuration(for: text, classification: classification)
    }

    private var displayConfiguration: ContentDisplayConfiguration {
        Self.displayConfiguration(text: text, classification: classification)
    }

    var body: some View {
        renderedText
            .lineLimit(displayConfiguration.prefersSingleLine ? 1 : multilineLineLimit)
            .truncationMode(displayConfiguration.swiftUITruncationMode)
            .multilineTextAlignment(.leading)
            .lineSpacing(PrimitiveTokens.Space.xxxs)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func layoutText(text: String, classification: ContentClassification) -> String {
        displayConfiguration(text: text, classification: classification).text
    }

    private var renderedText: Text {
        let displayText = displayConfiguration.text
        var attributedText = AttributedString(displayText)
        attributedText.font = PrimitiveTokens.Typography.body
        attributedText.foregroundColor = baseColor

        let fullRange = NSRange(location: 0, length: (displayText as NSString).length)
        let validRanges = highlightedRanges
            .map { NSIntersectionRange($0, fullRange) }
            .filter { $0.length > 0 }

        for range in validRanges {
            guard let stringRange = Range(range, in: displayText),
                  let attributedRange = Range(stringRange, in: attributedText) else {
                continue
            }

            attributedText[attributedRange].font = PrimitiveTokens.Typography.bodyStrong
            attributedText[attributedRange].foregroundColor = SemanticTokens.Text.accent
        }

        return Text(attributedText)
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
