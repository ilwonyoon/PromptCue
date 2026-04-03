import SwiftUI

struct CardSurface<Content: View>: View {
    let backgroundFill: Color
    let borderColor: Color
    let borderLineWidth: CGFloat
    let contentPadding: EdgeInsets
    let cornerRadius: CGFloat
    @ViewBuilder private var content: Content

    init(
        isSelected: Bool = false,
        backgroundFill: Color? = nil,
        borderColor: Color? = nil,
        borderLineWidth: CGFloat? = nil,
        contentPadding: EdgeInsets? = nil,
        cornerRadius: CGFloat = PrimitiveTokens.Radius.md,
        @ViewBuilder content: () -> Content
    ) {
        self.backgroundFill = backgroundFill ?? (isSelected ? SemanticTokens.Surface.accentFill : SemanticTokens.Surface.cardFill)
        self.borderColor = borderColor ?? (isSelected ? SemanticTokens.Border.emphasis : SemanticTokens.Border.subtle)
        self.borderLineWidth = borderLineWidth ?? (isSelected ? PrimitiveTokens.Stroke.emphasis : PrimitiveTokens.Stroke.subtle)
        self.contentPadding = contentPadding ?? EdgeInsets(
            top: PrimitiveTokens.Size.cardPadding,
            leading: PrimitiveTokens.Size.cardPadding,
            bottom: PrimitiveTokens.Size.cardPadding,
            trailing: PrimitiveTokens.Size.cardPadding
        )
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(contentPadding)
            .background(shape.fill(backgroundFill))
            .overlay {
                shape
                    .stroke(borderColor, lineWidth: borderLineWidth)
            }
            .clipShape(shape)
            .promptCueCardShadow()
    }
}
