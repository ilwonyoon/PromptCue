import SwiftUI

struct SettingsTwoColumnGroupRow<Content: View>: View {
    enum ContentAlignment {
        case leading
        case trailing

        var frameAlignment: Alignment {
            switch self {
            case .leading: .leading
            case .trailing: .trailing
            }
        }
    }

    let label: String
    let labelWidth: CGFloat
    let verticalAlignment: VerticalAlignment
    let showsDivider: Bool
    let contentAlignment: ContentAlignment
    private let content: Content

    init(
        _ label: String,
        labelWidth: CGFloat = SettingsTokens.Layout.labelColumnWidth,
        verticalAlignment: VerticalAlignment = .top,
        showsDivider: Bool = true,
        contentAlignment: ContentAlignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.labelWidth = labelWidth
        self.verticalAlignment = verticalAlignment
        self.showsDivider = showsDivider
        self.contentAlignment = contentAlignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: verticalAlignment, spacing: SettingsTokens.Layout.rowLabelToValueGap) {
            Text(label)
                .font(SettingsTokens.Typography.rowLabel)
                .foregroundStyle(SettingsSemanticTokens.Text.primary)
                .frame(width: labelWidth, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: contentAlignment.frameAlignment)
        }
        .frame(minHeight: SettingsTokens.Layout.formRowMinHeight, alignment: .leading)
        .padding(.horizontal, SettingsTokens.Layout.groupInset)
        .padding(.vertical, SettingsTokens.Layout.rowVerticalPadding)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(SettingsSemanticTokens.Border.rowSeparator)
                    .frame(height: 1)
                    .padding(.horizontal, SettingsTokens.Layout.groupDividerInset)
            }
        }
    }
}
