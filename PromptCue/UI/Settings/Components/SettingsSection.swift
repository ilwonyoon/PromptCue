import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    private let content: Content

    init(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Layout.sectionHeaderSpacing) {
            VStack(alignment: .leading, spacing: SettingsTokens.Layout.sectionTitleSpacing) {
                Text(title)
                    .font(SettingsTokens.Typography.sectionTitle)
                    .foregroundStyle(SettingsSemanticTokens.Text.primary)

                if let footer, footer.isEmpty == false {
                    Text(footer)
                        .font(SettingsTokens.Typography.supporting)
                        .foregroundStyle(SettingsSemanticTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsGroupSurface {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRows<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
    }
}

struct SettingsGroupSurface<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, SettingsTokens.Layout.groupVerticalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsSemanticTokens.Surface.formGroupFill)
        .clipShape(
            RoundedRectangle(
                cornerRadius: SettingsTokens.Layout.groupCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: SettingsTokens.Layout.groupCornerRadius,
                style: .continuous
            )
            .stroke(SettingsSemanticTokens.Border.formGroup, lineWidth: PrimitiveTokens.Stroke.subtle)
        }
    }
}
