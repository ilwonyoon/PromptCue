import SwiftUI

struct SettingsLongFormGroupRow<Content: View>: View {
    let label: String
    let labelWidth: CGFloat
    let showsDivider: Bool
    let actionTitle: String?
    let action: (() -> Void)?
    private let content: Content

    init(
        _ label: String,
        labelWidth: CGFloat = SettingsTokens.Layout.labelColumnWidth,
        showsDivider: Bool = true,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.labelWidth = labelWidth
        self.showsDivider = showsDivider
        self.actionTitle = actionTitle
        self.action = action
        self.content = content()
    }

    var body: some View {
        SettingsTwoColumnGroupRow(
            label,
            labelWidth: labelWidth,
            verticalAlignment: .top,
            showsDivider: showsDivider,
            contentAlignment: .leading
        ) {
            VStack(alignment: .leading, spacing: SettingsTokens.Layout.longFormHeaderSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: SettingsTokens.Layout.rowActionSpacing) {
                    Spacer(minLength: 0)

                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .controlSize(.small)
                    }
                }

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
