import SwiftUI

struct StackSectionHeader<Trailing: View>: View {
    let title: String
    let count: Int?
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        count: Int? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.count = count
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: PrimitiveTokens.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: PrimitiveTokens.Space.xxs) {
                Text(title)
                    .font(PrimitiveTokens.Typography.bodyStrong)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .lineLimit(1)

                if let count {
                    Text("\(count)")
                        .font(PrimitiveTokens.Typography.accessoryIcon)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.leading, PrimitiveTokens.Space.xs)
        .padding(.trailing, PrimitiveTokens.Space.xs)
        .padding(.vertical, PrimitiveTokens.Space.sm)
        .frame(width: PanelMetrics.stackCardColumnWidth, alignment: .leading)
    }
}
