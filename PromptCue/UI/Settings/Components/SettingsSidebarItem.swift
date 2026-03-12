import SwiftUI

struct SettingsSidebarItem: View {
    let title: String
    let systemImage: String
    let iconFill: Color
    var isSelected: Bool = false
    var usesManualSelection: Bool = true
    var action: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        if let action {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var textColor: some ShapeStyle {
        if usesManualSelection {
            return AnyShapeStyle(
                isSelected
                    ? SettingsSemanticTokens.Text.selected
                    : SettingsSemanticTokens.Text.primary
            )
        }

        return AnyShapeStyle(Color.primary)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if usesManualSelection {
            RoundedRectangle(
                cornerRadius: SettingsTokens.Layout.sidebarCornerRadius,
                style: .continuous
            )
            .fill(isSelected ? SettingsSemanticTokens.Accent.selection : Color.clear)
        }
    }

    @ViewBuilder
    private var hoverShape: some View {
        if usesManualSelection == false, isHovered, isSelected == false {
            RoundedRectangle(
                cornerRadius: SettingsTokens.Layout.sidebarCornerRadius,
                style: .continuous
            )
            .fill(SettingsSemanticTokens.Surface.sidebarHoverFill)
        }
    }

    private var contentShape: some Shape {
        RoundedRectangle(
            cornerRadius: SettingsTokens.Layout.sidebarCornerRadius,
            style: .continuous
        )
    }

    private var rowContent: some View {
        HStack(spacing: SettingsTokens.Layout.sidebarIconTextSpacing) {
            SettingsSidebarIconTile(
                systemImage: systemImage,
                fill: iconFill
            )

            Text(title)
                .font(SettingsTokens.Typography.sidebarLabel)
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .frame(minHeight: SettingsTokens.Layout.sidebarRowHeight, alignment: .leading)
        .padding(.horizontal, usesManualSelection ? SettingsTokens.Layout.sidebarItemHorizontalPadding : PrimitiveTokens.Space.xxs)
        .padding(.vertical, usesManualSelection ? SettingsTokens.Layout.sidebarItemVerticalPadding : PrimitiveTokens.Space.xxxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundShape)
        .background(hoverShape)
        .contentShape(contentShape)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
