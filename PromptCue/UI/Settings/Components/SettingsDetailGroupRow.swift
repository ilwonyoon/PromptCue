import SwiftUI

struct SettingsDetailGroupRow<Detail: View, Actions: View>: View {
    let label: String
    let labelWidth: CGFloat
    let verticalAlignment: VerticalAlignment
    let showsDivider: Bool
    private let detail: Detail
    private let actions: Actions?

    init(
        _ label: String,
        labelWidth: CGFloat = SettingsTokens.Layout.labelColumnWidth,
        verticalAlignment: VerticalAlignment = .top,
        showsDivider: Bool = true,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder actions: () -> Actions? = { nil }
    ) {
        self.label = label
        self.labelWidth = labelWidth
        self.verticalAlignment = verticalAlignment
        self.showsDivider = showsDivider
        self.detail = detail()
        self.actions = actions()
    }

    var body: some View {
        SettingsTwoColumnGroupRow(
            label,
            labelWidth: labelWidth,
            verticalAlignment: verticalAlignment,
            showsDivider: showsDivider,
            contentAlignment: .leading
        ) {
            VStack(alignment: .leading, spacing: SettingsTokens.Layout.rowDetailSpacing) {
                detail
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let actions {
                    HStack(spacing: SettingsTokens.Layout.rowActionSpacing) {
                        actions
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension SettingsDetailGroupRow where Actions == EmptyView {
    init(
        _ label: String,
        labelWidth: CGFloat = SettingsTokens.Layout.labelColumnWidth,
        verticalAlignment: VerticalAlignment = .top,
        showsDivider: Bool = true,
        @ViewBuilder detail: () -> Detail
    ) {
        self.init(
            label,
            labelWidth: labelWidth,
            verticalAlignment: verticalAlignment,
            showsDivider: showsDivider,
            detail: detail,
            actions: { EmptyView() }
        )
    }
}
