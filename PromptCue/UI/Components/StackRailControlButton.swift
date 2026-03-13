import AppKit
import SwiftUI

struct StackRailControlButton: View {
    let systemName: String
    let accessibilityLabel: String
    let glyphSize: CGFloat
    let controlSize: CGFloat
    let isActive: Bool
    let isDestructive: Bool
    let rotationDegrees: Double
    let action: () -> Void

    @State private var isHovered = false

    init(
        systemName: String,
        accessibilityLabel: String,
        glyphSize: CGFloat = 20,
        controlSize: CGFloat = 36,
        isActive: Bool = false,
        isDestructive: Bool = false,
        rotationDegrees: Double = 0,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.glyphSize = glyphSize
        self.controlSize = controlSize
        self.isActive = isActive
        self.isDestructive = isDestructive
        self.rotationDegrees = rotationDegrees
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: glyphSize, weight: .semibold))
                .rotationEffect(.degrees(rotationDegrees))
                .foregroundStyle(foregroundColor)
                .frame(width: controlSize, height: controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            isHovered = hovered
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var foregroundColor: Color {
        if isDestructive {
            return Color(nsColor: .systemRed).opacity(isHovered ? 0.95 : 0.82)
        }

        return isActive || isHovered
            ? SemanticTokens.Text.primary
            : SemanticTokens.Text.secondary
    }
}
