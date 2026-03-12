import SwiftUI

struct SettingsGroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsSemanticTokens.Border.rowSeparator)
            .frame(height: 1)
            .padding(.horizontal, SettingsTokens.Layout.groupDividerInset)
    }
}
