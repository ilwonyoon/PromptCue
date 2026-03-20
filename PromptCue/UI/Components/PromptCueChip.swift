import SwiftUI

struct PromptCueChip<Content: View>: View {
    let fill: Color
    let border: Color
    let horizontalPadding: CGFloat
    let height: CGFloat
    @ViewBuilder private var content: Content

    init(
        fill: Color = SemanticTokens.Surface.cardFill,
        border: Color = SemanticTokens.Border.subtle,
        horizontalPadding: CGFloat = PrimitiveTokens.Space.sm,
        height: CGFloat = PrimitiveTokens.Size.chipHeight,
        @ViewBuilder content: () -> Content
    ) {
        self.fill = fill
        self.border = border
        self.horizontalPadding = horizontalPadding
        self.height = height
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(border)
            }
    }
}
