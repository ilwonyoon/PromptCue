import SwiftUI

struct PanelHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxxs) {
            Text(title)
                .font(PrimitiveTokens.Typography.panelTitle)
                .foregroundStyle(SemanticTokens.Text.primary)

            Text(subtitle)
                .font(PrimitiveTokens.Typography.meta)
                .foregroundStyle(SemanticTokens.Text.secondary)
        }
    }
}
