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
                        .foregroundStyle(bodyColor)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(PrimitiveTokens.Space.xxxs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.trailing, actionColumnReservedWidth)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: PrimitiveTokens.Space.xs) {
                    iconButton(
                        systemName: copyIconSystemName,
                        foregroundColor: copyIconColor,
                        backgroundColor: copyIconBackground,
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
                        foregroundColor: deleteIconColor,
                        backgroundColor: deleteIconBackground,
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

    private var bodyColor: Color {
        if isSelected || isCardHovered || isCopyHovered || isDeleteHovered {
            return SemanticTokens.Text.primary
        }

        if card.isCopied {
            return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.soft)
        }

        return SemanticTokens.Text.primary
    }

    private var copyIconColor: Color {
        if isDeleteHovered {
            return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.subtle)
        }

        if isShowingCopyFeedback {
            return SemanticTokens.Text.primary
        }

        if isCopyHovered || (isCardHovered && !selectionMode) {
            return SemanticTokens.Text.primary
        }

        return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.soft)
    }

    private var copyIconSystemName: String {
        if isShowingCopyFeedback {
            return "checkmark"
        }

        if isCopyHovered || (isCardHovered && !selectionMode) {
            return "doc.on.doc.fill"
        }

        return "doc.on.doc"
    }

    private var deleteIconColor: Color {
        if isDeleteHovered {
            return SemanticTokens.Text.primary
        }

        if card.isCopied {
            return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.subtle)
        }

        return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.soft)
    }

    private var copyIconBackground: Color {
        if isDeleteHovered {
            return .clear
        }

        if isShowingCopyFeedback {
            return SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.strong)
        }

        if isCopyHovered || (isCardHovered && !selectionMode) {
            return SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.strong)
        }

        if usesPersistentActionBackdrop {
            return SemanticTokens.Surface.notificationCardBackdrop.opacity(0.72)
        }

        return .clear
    }

    private var deleteIconBackground: Color {
        if isDeleteHovered {
            return SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.medium)
        }

        if usesPersistentActionBackdrop {
            return SemanticTokens.Surface.notificationCardBackdrop.opacity(0.6)
        }

        return .clear
    }

    private var actionColumnWidth: CGFloat {
        PrimitiveTokens.Space.xl
    }

    private var actionColumnReservedWidth: CGFloat {
        actionColumnWidth + PrimitiveTokens.Space.sm
    }

    private var usesPersistentActionBackdrop: Bool {
        colorScheme == .light && card.screenshotURL != nil
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
