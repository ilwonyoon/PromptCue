import SwiftUI

struct SettingsFormRow<Content: View>: View {
    let label: String
    let verticalAlignment: VerticalAlignment
    let showsDivider: Bool
    private let content: Content

    init(
        _ label: String,
        verticalAlignment: VerticalAlignment = .center,
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.verticalAlignment = verticalAlignment
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        SettingsTwoColumnGroupRow(
            label,
            labelWidth: SettingsTokens.Layout.labelColumnWidth,
            verticalAlignment: verticalAlignment,
            showsDivider: showsDivider,
            contentAlignment: .trailing
        ) {
            content
        }
    }
}
