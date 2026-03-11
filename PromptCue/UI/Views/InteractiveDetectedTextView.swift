import PromptCueCore
import SwiftUI

struct InteractiveDetectedTextView: View {
    let text: String
    let classification: ContentClassification
    let baseColor: Color
    let onInteractionHoverChanged: (Bool) -> Void

    @State private var isSpanHovered = false
    @State private var isCursorPushed = false

    var body: some View {
        if let span = classification.span, classification.primaryType != .plain {
            segmentedText(span: span)
        } else {
            plainText
        }
    }

    private var plainText: some View {
        Text(text)
            .font(PrimitiveTokens.Typography.body)
            .foregroundStyle(baseColor)
            .multilineTextAlignment(.leading)
            .lineSpacing(PrimitiveTokens.Space.xxxs)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func segmentedText(span: DetectedSpan) -> some View {
        let displayText = resolvedDisplayText(for: span)
        let interactive = classification.primaryType == .link || classification.primaryType == .path
        let prefix = text[text.startIndex..<span.range.lowerBound]
        let suffix = text[span.range.upperBound..<text.endIndex]

        let renderedText = textSegment(prefix, color: baseColor)
            + textSegment(displayText, color: interactive ? (isSpanHovered ? spanHoverColor : spanRestingColor) : SemanticTokens.Classification.secretText, underline: interactive && isSpanHovered)
            + textSegment(suffix, color: baseColor)

        if interactive {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                renderedText
                    .font(PrimitiveTokens.Typography.body)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(PrimitiveTokens.Space.xxxs)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSpanHovered {
                    HStack(spacing: PrimitiveTokens.Space.xxs) {
                        Text(openActionLabel)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(PrimitiveTokens.Typography.meta)
                    .foregroundStyle(spanRestingColor)
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    if !isSpanHovered {
                        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                            isSpanHovered = true
                        }
                        onInteractionHoverChanged(true)
                    }
                    if !isCursorPushed {
                        NSCursor.pointingHand.push()
                        isCursorPushed = true
                    }
                case .ended:
                    if isSpanHovered {
                        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                            isSpanHovered = false
                        }
                        onInteractionHoverChanged(false)
                    }
                    if isCursorPushed {
                        NSCursor.pop()
                        isCursorPushed = false
                    }
                }
            }
            .onDisappear {
                onInteractionHoverChanged(false)
                if isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
        } else {
            renderedText
                .font(PrimitiveTokens.Typography.body)
                .multilineTextAlignment(.leading)
                .lineSpacing(PrimitiveTokens.Space.xxxs)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var openActionLabel: String {
        classification.primaryType == .link ? "Open link" : "Reveal in Finder"
    }

    private var spanRestingColor: Color {
        switch classification.primaryType {
        case .link, .path:
            return SemanticTokens.Classification.interactiveText
        case .plain, .secret:
            return baseColor
        }
    }

    private var spanHoverColor: Color {
        switch classification.primaryType {
        case .link, .path:
            return SemanticTokens.Classification.interactiveHoverText
        case .plain, .secret:
            return baseColor
        }
    }

    private func resolvedDisplayText(for span: DetectedSpan) -> String {
        classification.primaryType == .secret ? SecretMasker.mask(span.matchedText) : span.matchedText
    }

    static func layoutText(text: String, classification: ContentClassification) -> String {
        guard let span = classification.span, classification.primaryType == .secret else {
            return text
        }

        let masked = SecretMasker.mask(span.matchedText)
        let prefix = text[text.startIndex..<span.range.lowerBound]
        let suffix = text[span.range.upperBound..<text.endIndex]
        return String(prefix) + masked + String(suffix)
    }

    private func textSegment<S: StringProtocol>(
        _ value: S,
        color: Color,
        underline: Bool = false
    ) -> Text {
        guard !value.isEmpty else {
            return Text("")
        }

        let segment = Text(String(value)).foregroundStyle(color)
        if underline {
            return segment.underline(true, color: SemanticTokens.Classification.interactiveHoverUnderline)
        }

        return segment
    }
}
