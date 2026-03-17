import SwiftUI

/// Reusable badge component for MCP connector clients.
///
/// Displays a client app icon (from asset catalog) with an optional status dot overlay.
/// Falls back to an SF Symbol on a filled rounded rect when no asset is available.
///
/// Usage:
/// ```
/// ConnectorClientBadge(
///     assetName: "ClaudeCodeIcon",
///     fallbackSymbol: "chevron.left.forwardslash.chevron.right",
///     statusColor: .green
/// )
/// ```
@MainActor
struct ConnectorClientBadge: View {
    let assetName: String?
    let fallbackSymbol: String
    var statusColor: Color?

    var body: some View {
        let badgeSize = PrimitiveTokens.Size.connectorBadge
        let badgeRadius = PrimitiveTokens.Size.connectorBadgeCornerRadius
        let badgeShape = RoundedRectangle(cornerRadius: badgeRadius, style: .continuous)

        ZStack {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: badgeSize, height: badgeSize)
                    .clipShape(badgeShape)
            } else {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                    .fill(SemanticTokens.Text.primary.opacity(0.9))

                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                    .stroke(SemanticTokens.Text.primary.opacity(0.08), lineWidth: PrimitiveTokens.Stroke.subtle)

                Image(systemName: fallbackSymbol)
                    .font(.system(size: PrimitiveTokens.Size.connectorFallbackIconSize, weight: .semibold))
                    .foregroundStyle(SemanticTokens.Surface.previewBackdropBottom)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let statusColor {
                ZStack {
                    Circle()
                        .fill(SemanticTokens.Surface.previewBackdropBottom)
                        .frame(
                            width: PrimitiveTokens.Size.connectorStatusDotRing,
                            height: PrimitiveTokens.Size.connectorStatusDotRing
                        )

                    Circle()
                        .fill(statusColor)
                        .frame(
                            width: PrimitiveTokens.Size.connectorStatusDot,
                            height: PrimitiveTokens.Size.connectorStatusDot
                        )
                }
                .offset(
                    x: PrimitiveTokens.Size.connectorStatusDotOffset,
                    y: PrimitiveTokens.Size.connectorStatusDotOffset
                )
            }
        }
        .frame(width: badgeSize, height: badgeSize)
    }
}
