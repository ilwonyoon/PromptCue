import SwiftUI

struct CaptureCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let card: CaptureCard
    let isSelected: Bool
    let selectionMode: Bool
    let onCopy: () -> Void
    let onToggleSelection: () -> Void
    let onDelete: () -> Void
    @State private var isCardHovered = false
    @State private var isCopyHovered = false
    @State private var isDeleteHovered = false
    @State private var isShowingCopyFeedback = false

    private var actionStyle: CaptureCardActionStyle {
        CaptureCardActionStyle.resolve(
            card: card,
            isSelected: isSelected,
            selectionMode: selectionMode,
            colorScheme: colorScheme,
            isCardHovered: isCardHovered,
            isCopyHovered: isCopyHovered,
            isDeleteHovered: isDeleteHovered,
            isShowingCopyFeedback: isShowingCopyFeedback
        )
    }

    var body: some View {
        StackNotificationCardSurface(
            isSelected: isSelected,
            isEmphasized: isCardHovered || isCopyHovered || isDeleteHovered || isShowingCopyFeedback
        ) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    if let screenshotURL = card.screenshotURL {
                        LocalImageThumbnail(
                            url: screenshotURL,
                            height: PrimitiveTokens.Size.notificationThumbnailHeight
                        )
                        .opacity(card.isCopied ? PrimitiveTokens.Opacity.soft : 1)
                    }

                    Text(card.text)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(actionStyle.bodyColor)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(PrimitiveTokens.Space.xxxs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.trailing, actionColumnReservedWidth)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: PrimitiveTokens.Space.xs) {
                    iconButton(
                        systemName: actionStyle.copyIconSystemName,
                        foregroundColor: actionStyle.copyIconColor,
                        backgroundColor: actionStyle.copyIconBackground,
                        action: performCopy
                    )
                    .accessibilityLabel("Copy cue")
                    .accessibilityHint("Copies this cue to the clipboard")
                    .onHover { hovered in
                        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                            isCopyHovered = hovered
                        }
                    }

                    iconButton(
                        systemName: "trash",
                        foregroundColor: actionStyle.deleteIconColor,
                        backgroundColor: actionStyle.deleteIconBackground,
                        action: onDelete
                    )
                    .accessibilityLabel("Delete cue")
                    .accessibilityHint("Permanently removes this cue")
                    .onHover { hovered in
                        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                            isDeleteHovered = hovered
                        }
                    }
                }
                .frame(width: actionColumnWidth, alignment: .topTrailing)
                .zIndex(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Cue: \(card.text)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .onTapGesture(perform: performPrimaryAction)
            .onHover { hovered in
                withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                    isCardHovered = hovered
                }
            }
        }
    }

    private var contentSpacing: CGFloat {
        if card.screenshotURL != nil {
            return PrimitiveTokens.Space.sm
        }

        return PrimitiveTokens.Space.xxs
    }

    private var actionColumnWidth: CGFloat {
        PrimitiveTokens.Space.xl
    }

    private var actionColumnReservedWidth: CGFloat {
        actionColumnWidth + PrimitiveTokens.Space.sm
    }

    private func performPrimaryAction() {
        if selectionMode {
            onToggleSelection()
            return
        }

        performCopy()
    }

    private func performCopy() {
        guard !isShowingCopyFeedback else {
            return
        }

        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
            isShowingCopyFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + PrimitiveTokens.Motion.quick) {
            onCopy()
            isShowingCopyFeedback = false
        }
    }

    @ViewBuilder
    private func iconButton(
        systemName: String,
        foregroundColor: Color,
        backgroundColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(PrimitiveTokens.Typography.accessoryIcon)
                .foregroundStyle(foregroundColor)
                .frame(width: PrimitiveTokens.Space.lg, height: PrimitiveTokens.Space.lg)
                .background(
                    RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CaptureCardActionStyle {
    let bodyColor: Color
    let copyIconColor: Color
    let copyIconSystemName: String
    let copyIconBackground: Color
    let deleteIconColor: Color
    let deleteIconBackground: Color

    static func resolve(
        card: CaptureCard,
        isSelected: Bool,
        selectionMode: Bool,
        colorScheme: ColorScheme,
        isCardHovered: Bool,
        isCopyHovered: Bool,
        isDeleteHovered: Bool,
        isShowingCopyFeedback: Bool
    ) -> CaptureCardActionStyle {
        let usesPersistentActionBackdrop = card.screenshotURL != nil
        let isPrimaryCopyHover = isCopyHovered || (isCardHovered && !selectionMode)

        let bodyColor: Color
        if isSelected || isCardHovered || isCopyHovered || isDeleteHovered {
            bodyColor = SemanticTokens.Text.primary
        } else if card.isCopied {
            switch colorScheme {
            case .light:
                bodyColor = SemanticTokens.Text.primary.opacity(0.74)
            case .dark:
                bodyColor = SemanticTokens.Text.secondary.opacity(0.78)
            @unknown default:
                bodyColor = SemanticTokens.Text.secondary.opacity(0.78)
            }
        } else {
            bodyColor = SemanticTokens.Text.primary
        }

        let copyIconColor: Color
        if isDeleteHovered {
            copyIconColor = SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.subtle)
        } else if isShowingCopyFeedback {
            copyIconColor = SemanticTokens.Text.primary
        } else if isPrimaryCopyHover {
            copyIconColor = SemanticTokens.Text.primary
        } else {
            switch colorScheme {
            case .light:
                copyIconColor = SemanticTokens.Text.secondary.opacity(0.80)
            case .dark:
                copyIconColor = SemanticTokens.Text.secondary.opacity(0.86)
            @unknown default:
                copyIconColor = SemanticTokens.Text.secondary.opacity(0.86)
            }
        }

        let copyIconSystemName: String
        if isShowingCopyFeedback {
            copyIconSystemName = "checkmark"
        } else if isPrimaryCopyHover {
            copyIconSystemName = "doc.on.doc.fill"
        } else {
            copyIconSystemName = "doc.on.doc"
        }

        let deleteIconColor: Color
        if isDeleteHovered {
            deleteIconColor = SemanticTokens.Text.primary
        } else if card.isCopied {
            switch colorScheme {
            case .light:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.62)
            case .dark:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.56)
            @unknown default:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.56)
            }
        } else {
            switch colorScheme {
            case .light:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.76)
            case .dark:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.82)
            @unknown default:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.82)
            }
        }

        let copyIconBackground: Color
        if isDeleteHovered {
            copyIconBackground = .clear
        } else if isShowingCopyFeedback {
            copyIconBackground = SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.strong)
        } else if isPrimaryCopyHover {
            copyIconBackground = SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.strong)
        } else if usesPersistentActionBackdrop {
            switch colorScheme {
            case .light:
                copyIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.72)
            case .dark:
                copyIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.54)
            @unknown default:
                copyIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.54)
            }
        } else {
            copyIconBackground = .clear
        }

        let deleteIconBackground: Color
        if isDeleteHovered {
            deleteIconBackground = SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.medium)
        } else if usesPersistentActionBackdrop {
            switch colorScheme {
            case .light:
                deleteIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.60)
            case .dark:
                deleteIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.46)
            @unknown default:
                deleteIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.46)
            }
        } else {
            deleteIconBackground = .clear
        }

        return CaptureCardActionStyle(
            bodyColor: bodyColor,
            copyIconColor: copyIconColor,
            copyIconSystemName: copyIconSystemName,
            copyIconBackground: copyIconBackground,
            deleteIconColor: deleteIconColor,
            deleteIconBackground: deleteIconBackground
        )
    }
}
