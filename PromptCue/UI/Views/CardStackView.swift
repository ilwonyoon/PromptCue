import SwiftUI

struct CardStackView: View {
    @ObservedObject var model: AppModel
    let onCopyCard: (CaptureCard) -> Void
    let onDeleteCard: (CaptureCard) -> Void

    var body: some View {
        ZStack {
            stackBackdrop

            VStack(alignment: .leading, spacing: PrimitiveTokens.Size.panelSectionSpacing) {
                header

                if model.cards.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: PrimitiveTokens.Size.cardStackSpacing) {
                            ForEach(model.cards) { card in
                                CaptureCardView(
                                    card: card,
                                    onCopy: {
                                        onCopyCard(card)
                                    },
                                    onDelete: {
                                        onDeleteCard(card)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, PrimitiveTokens.Space.xxxs)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, PrimitiveTokens.Space.sm)
            .padding(.top, PrimitiveTokens.Space.sm)
            .padding(.bottom, PrimitiveTokens.Space.md)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: PrimitiveTokens.Space.sm) {
            Text("Prompt Cue")
                .font(PrimitiveTokens.Typography.bodyStrong)
                .foregroundStyle(SemanticTokens.Text.primary)

            Spacer(minLength: PrimitiveTokens.Space.xs)

            if !model.cards.isEmpty {
                Text("\(model.cards.count)")
                    .font(PrimitiveTokens.Typography.meta)
                    .foregroundStyle(SemanticTokens.Text.secondary)
            }
        }
    }

    private var emptyState: some View {
        CardSurface {
            Text("No cues yet")
                .font(PrimitiveTokens.Typography.body)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(maxWidth: .infinity)
                .frame(height: PrimitiveTokens.Size.thumbnailHeight)
        }
    }

    private var stackBackdrop: some View {
        Rectangle()
            .fill(SemanticTokens.MaterialStyle.floatingShell)
            .overlay {
                Rectangle().fill(SemanticTokens.Surface.stackPanelBackdropTint)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        SemanticTokens.Surface.stackPanelGradientTop,
                        .clear,
                        SemanticTokens.Surface.stackPanelGradientBottom,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
    }
}
