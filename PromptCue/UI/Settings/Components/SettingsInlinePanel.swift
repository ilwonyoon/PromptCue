import SwiftUI

struct SettingsInlinePanel<Content: View>: View {
    private let contentPadding: CGFloat
    private let content: Content

    init(
        contentPadding: CGFloat = SettingsTokens.Layout.inlinePanelPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
            content
        }
        .padding(contentPadding)
        .background(SettingsSemanticTokens.Surface.inlinePanelFill)
        .clipShape(
            RoundedRectangle(
                cornerRadius: SettingsTokens.Layout.fieldCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: SettingsTokens.Layout.fieldCornerRadius,
                style: .continuous
            )
            .stroke(SettingsSemanticTokens.Border.formGroup, lineWidth: PrimitiveTokens.Stroke.subtle)
        }
    }
}
