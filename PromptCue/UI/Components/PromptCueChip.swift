import SwiftUI

struct PromptCueChip<Content: View>: View {
    let fill: Color
    let border: Color
    @ViewBuilder private var content: Content

    init(
        fill: Color = SemanticTokens.Surface.cardFill,
        border: Color = SemanticTokens.Border.subtle,
        @ViewBuilder content: () -> Content
    ) {
        self.fill = fill
        self.border = border
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, PrimitiveTokens.Space.sm)
            .frame(height: PrimitiveTokens.Size.chipHeight)
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
