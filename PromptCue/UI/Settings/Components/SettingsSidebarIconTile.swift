import SwiftUI

struct SettingsSidebarIconTile: View {
    let systemImage: String
    let fill: Color

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: SettingsTokens.Layout.sidebarIconCornerRadius,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        fill,
                        fill.opacity(0.96),
                        fill.opacity(0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: SettingsTokens.Layout.sidebarIconCornerRadius,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            SettingsSemanticTokens.Surface.sidebarIconHighlight,
                            .clear,
                            SettingsSemanticTokens.Surface.sidebarIconShade,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay(alignment: .top) {
                RoundedRectangle(
                    cornerRadius: SettingsTokens.Layout.sidebarIconCornerRadius,
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.22), lineWidth: PrimitiveTokens.Stroke.subtle)
                .mask {
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: SettingsTokens.Layout.sidebarIconCornerRadius,
                    style: .continuous
                )
                .stroke(SettingsSemanticTokens.Border.sidebarIconStroke, lineWidth: PrimitiveTokens.Stroke.subtle)
            }
            .shadow(color: Color.black.opacity(0.14), radius: 1.5, x: 0, y: 0.75)

            Image(systemName: systemImage)
                .font(.system(size: SettingsTokens.Layout.sidebarIconGlyphSize, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(
            width: SettingsTokens.Layout.sidebarIconSize,
            height: SettingsTokens.Layout.sidebarIconSize
        )
    }
}
