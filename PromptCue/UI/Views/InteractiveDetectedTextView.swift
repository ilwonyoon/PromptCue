import PromptCueCore
import SwiftUI

struct InteractiveDetectedTextView: View {
    let text: String
    let classification: ContentClassification
    let baseColor: Color

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
        Text(displayConfiguration.text)
            .font(PrimitiveTokens.Typography.body)
            .foregroundStyle(baseColor)
            .lineLimit(displayConfiguration.prefersSingleLine ? 1 : nil)
            .truncationMode(displayConfiguration.swiftUITruncationMode)
            .multilineTextAlignment(.leading)
            .lineSpacing(PrimitiveTokens.Space.xxxs)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func layoutText(text: String, classification: ContentClassification) -> String {
        displayConfiguration(text: text, classification: classification).text
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
