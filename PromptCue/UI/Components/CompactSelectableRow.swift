import AppKit
import SwiftUI

struct CompactSelectableRow<Content: View>: View {
    enum Tone {
        case sidebar
        case content
    }

    let tone: Tone
    let isSelected: Bool
    var contentHorizontalPadding: CGFloat? = nil
    var debugFill: Color? = nil
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                shape
                    .fill(baseFillColor)

                shape
                    .fill(interactionFillColor)
                    .opacity(interactionFillOpacity)

                shape
                    .strokeBorder(borderBaseColor, lineWidth: PrimitiveTokens.Stroke.subtle)
                    .opacity(borderOpacity)

                content
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .frame(minHeight: minimumHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if let debugFill {
                            RoundedRectangle(cornerRadius: PrimitiveTokens.Space.xs, style: .continuous)
                                .fill(debugFill.opacity(0.10))
                        }
                    }
                    .overlay {
                        if let debugFill {
                            RoundedRectangle(cornerRadius: PrimitiveTokens.Space.xs, style: .continuous)
                                .stroke(debugFill.opacity(0.45), lineWidth: 1)
                        }
                    }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: PrimitiveTokens.Space.xs, style: .continuous)
    }

    private var baseFillColor: Color {
        switch tone {
        case .sidebar:
            return SemanticTokens.adaptiveColor(
                light: NSColor(
                    srgbRed: 225.0 / 255.0,
                    green: 225.0 / 255.0,
                    blue: 224.0 / 255.0,
                    alpha: 1
                ),
                dark: NSColor(calibratedWhite: 0.16, alpha: 1)
            )

        case .content:
            return CompactSelectableRowColors.contentBackground
        }
    }

    private var interactionFillColor: Color {
        switch tone {
        case .sidebar:
            return SemanticTokens.adaptiveColor(
                light: NSColor.black.withAlphaComponent(0.05),
                dark: NSColor.white.withAlphaComponent(0.06)
            )

        case .content:
            return SemanticTokens.adaptiveColor(
                light: NSColor.black.withAlphaComponent(0.035),
                dark: NSColor.white.withAlphaComponent(0.06)
            )
        }
    }

    private var interactionFillOpacity: Double {
        switch tone {
        case .sidebar:
            if isSelected {
                return 1
            }
            if isHovered {
                return 0.5
            }
            return 0

        case .content:
            if isSelected {
                return 1
            }
            if isHovered {
                return 0.55
            }
            return 0
        }
    }

    private var borderBaseColor: Color {
        CompactSelectableRowColors.borderBase
    }

    private var borderOpacity: Double {
        switch tone {
        case .sidebar:
            if isSelected {
                return 0.24
            }
            return 0

        case .content:
            if isSelected {
                return 0.20
            }
            return 0
        }
    }

    private var horizontalPadding: CGFloat {
        if let contentHorizontalPadding {
            return contentHorizontalPadding
        }

        switch tone {
        case .sidebar:
            return 10
        case .content:
            return 10
        }
    }

    private var verticalPadding: CGFloat {
        switch tone {
        case .sidebar:
            return 7
        case .content:
            return 6
        }
    }

    private var minimumHeight: CGFloat {
        switch tone {
        case .sidebar:
            return 32
        case .content:
            return 30
        }
    }
}

private enum CompactSelectableRowColors {
    static let contentBackground = SemanticTokens.adaptiveColor(
        light: NSColor.textBackgroundColor,
        dark: NSColor.textBackgroundColor
    )

    static let borderBase = SemanticTokens.adaptiveColor(
        light: NSColor.separatorColor,
        dark: NSColor.separatorColor
    )
}
