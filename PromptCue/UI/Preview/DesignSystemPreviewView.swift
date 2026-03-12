import Foundation
import SwiftUI

struct DesignSystemPreviewView: View {
    private let sampleCard = CaptureCard(
        text: "Navigation label overlaps on narrow layouts. Save state should persist after retry.",
        createdAt: .now.addingTimeInterval(-900)
    )

    private let componentInventory: [ComponentInventoryEntry] = [
        .init(
            name: "GlassPanel",
            path: "PromptCue/UI/Components/GlassPanel.swift",
            category: "Surface",
            role: "Top-level floating shell for panels and grouped sections.",
            usesGlass: true,
            hasLivePreview: true
        ),
        .init(
            name: "SearchFieldSurface",
            path: "PromptCue/UI/Components/SearchFieldSurface.swift",
            category: "Surface",
            role: "Capture lane shell for the multiline note input.",
            usesGlass: true,
            hasLivePreview: true
        ),
        .init(
            name: "CardSurface",
            path: "PromptCue/UI/Components/CardSurface.swift",
            category: "Surface",
            role: "Solid card wrapper for stack items and dense content.",
            usesGlass: false,
            hasLivePreview: true
        ),
        .init(
            name: "PromptCueChip",
            path: "PromptCue/UI/Components/PromptCueChip.swift",
            category: "Primitive",
            role: "Compact capsule for selection and state tags.",
            usesGlass: false,
            hasLivePreview: true
        ),
        .init(
            name: "PanelHeader",
            path: "PromptCue/UI/Components/PanelHeader.swift",
            category: "Primitive",
            role: "Panel title and subtitle text block.",
            usesGlass: false,
            hasLivePreview: true
        ),
        .init(
            name: "CueTextEditor",
            path: "PromptCue/UI/Components/CueTextEditor.swift",
            category: "Primitive",
            role: "AppKit multiline editor with Enter save and Shift+Enter line break.",
            usesGlass: false,
            hasLivePreview: true
        ),
        .init(
            name: "LocalImageThumbnail",
            path: "PromptCue/UI/Views/LocalImageThumbnail.swift",
            category: "Feature View",
            role: "Screenshot attachment thumbnail with fallback state.",
            usesGlass: false,
            hasLivePreview: true
        ),
        .init(
            name: "CaptureCardView",
            path: "PromptCue/UI/Views/CaptureCardView.swift",
            category: "Feature View",
            role: "Single captured cue card with copy and selection actions.",
            usesGlass: false,
            hasLivePreview: true
        ),
        .init(
            name: "CaptureComposerView",
            path: "PromptCue/UI/Views/CaptureComposerView.swift",
            category: "Feature View",
            role: "Center capture panel composition built around the note lane.",
            usesGlass: true,
            hasLivePreview: false
        ),
        .init(
            name: "CardStackView",
            path: "PromptCue/UI/Views/CardStackView.swift",
            category: "Feature View",
            role: "Right-side stack panel composition for review and export.",
            usesGlass: true,
            hasLivePreview: false
        ),
        .init(
            name: "PromptCueSettingsView",
            path: "PromptCue/UI/Settings/PromptCueSettingsView.swift",
            category: "Feature View",
            role: "Settings form for user-editable shortcuts.",
            usesGlass: false,
            hasLivePreview: true
        ),
        .init(
            name: "CapturePanelController",
            path: "PromptCue/UI/WindowControllers/CapturePanelController.swift",
            category: "Window Controller",
            role: "Owns the centered quick capture panel lifecycle and outside-click dismissal.",
            usesGlass: true,
            hasLivePreview: false
        ),
        .init(
            name: "StackPanelController",
            path: "PromptCue/UI/WindowControllers/StackPanelController.swift",
            category: "Window Controller",
            role: "Owns the right-side stack panel lifecycle and outside-click dismissal.",
            usesGlass: true,
            hasLivePreview: false
        ),
        .init(
            name: "DesignSystemWindowController",
            path: "PromptCue/UI/WindowControllers/DesignSystemWindowController.swift",
            category: "Window Controller",
            role: "Owns the review window used to inspect the design system in-app.",
            usesGlass: false,
            hasLivePreview: false
        ),
    ]

    private let colorTokens: [ColorTokenEntry] = [
        .init(name: "Panel Fill", color: SemanticTokens.Surface.panelFill),
        .init(name: "Card Fill", color: SemanticTokens.Surface.cardFill),
        .init(name: "Raised Fill", color: SemanticTokens.Surface.raisedFill),
        .init(name: "Accent Fill", color: SemanticTokens.Surface.accentFill),
        .init(name: "Text Primary", color: SemanticTokens.Text.primary),
        .init(name: "Text Secondary", color: SemanticTokens.Text.secondary),
        .init(name: "Accent", color: SemanticTokens.Text.accent),
        .init(name: "Selection", color: SemanticTokens.Text.selection),
    ]

    private let spacingTokens: [TokenEntry] = [
        .init(name: "space-8", value: Int(PrimitiveTokens.Space.xs)),
        .init(name: "space-12", value: Int(PrimitiveTokens.Space.sm)),
        .init(name: "space-16", value: Int(PrimitiveTokens.Space.md)),
        .init(name: "space-20", value: Int(PrimitiveTokens.Space.lg)),
        .init(name: "space-24", value: Int(PrimitiveTokens.Space.xl)),
    ]

    private let radiusTokens: [TokenEntry] = [
        .init(name: "radius-12", value: Int(PrimitiveTokens.Radius.sm)),
        .init(name: "radius-18", value: Int(PrimitiveTokens.Radius.md)),
        .init(name: "radius-26", value: Int(PrimitiveTokens.Radius.lg)),
        .init(name: "radius-30", value: Int(PrimitiveTokens.Radius.xl)),
    ]

    var body: some View {
        ZStack {
            previewBackdrop

            ScrollView {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxl) {
                    hero
                    componentInventorySection
                    glassSection
                    liveGallerySection
                    settingsSimulationSection
                    foundationsSection
                }
                .padding(PrimitiveTokens.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(
            minWidth: DesignSystemPreviewTokens.windowWidth,
            minHeight: DesignSystemPreviewTokens.windowHeight
        )
    }

    private var previewBackdrop: some View {
        LinearGradient(
            colors: [
                SemanticTokens.Surface.previewBackdropTop,
                SemanticTokens.Surface.previewBackdropBottom,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(SemanticTokens.Surface.previewOrbPrimary)
                .frame(
                    width: DesignSystemPreviewTokens.glassOrbLarge,
                    height: DesignSystemPreviewTokens.glassOrbLarge
                )
                .blur(radius: PrimitiveTokens.Space.xxl * 3)
                .offset(
                    x: -PrimitiveTokens.Space.xxl,
                    y: -PrimitiveTokens.Space.xxl
                )
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(SemanticTokens.Surface.previewOrbSecondary)
                .frame(
                    width: DesignSystemPreviewTokens.glassOrbMedium,
                    height: DesignSystemPreviewTokens.glassOrbMedium
                )
                .blur(radius: PrimitiveTokens.Space.xxl * 3)
                .offset(
                    x: PrimitiveTokens.Space.xxl,
                    y: PrimitiveTokens.Space.xxl
                )
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        GlassPanel {
            HStack(alignment: .top, spacing: PrimitiveTokens.Space.xxl) {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
                    Text("Backtick Design System")
                        .font(PrimitiveTokens.Typography.panelTitle)
                        .foregroundStyle(SemanticTokens.Text.primary)

                    Text("A quiet, Spotlight-first system for capture surfaces, dense review cards, and minimal supporting chrome.")
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: PrimitiveTokens.Space.sm) {
                        principleChip("Minimal")
                        principleChip("Less Invasive")
                        principleChip("Quiet Ambient")
                        principleChip("Spotlight-First")
                    }
                }

                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                    heroStat(title: "Reusable Components", value: "\(componentInventory.count)")
                    heroStat(title: "Glass Surfaces", value: "\(componentInventory.filter(\.usesGlass).count)")
                    heroStat(title: "Capture Type Lane", value: "17 / 22")
                }
                .frame(width: DesignSystemPreviewTokens.headerPreviewWidth, alignment: .leading)
            }
        }
    }

    private var componentInventorySection: some View {
        sectionBlock(
            title: "Component Inventory",
            subtitle: "Every reusable component is listed here with ownership, file path, and whether it currently uses the glass treatment."
        ) {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: DesignSystemPreviewTokens.inventoryGridMinWidth),
                        spacing: PrimitiveTokens.Space.md
                    )
                ],
                spacing: PrimitiveTokens.Space.md
            ) {
                ForEach(componentInventory) { entry in
                    ComponentInventoryCard(entry: entry)
                }
            }
        }
    }

    private var glassSection: some View {
        sectionBlock(
            title: "Glass Readability",
            subtitle: "Today only the floating shell and capture lane use glass. The preview background below makes that material legible enough to inspect."
        ) {
            ZStack {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SemanticTokens.Surface.previewBackdropBottom,
                                SemanticTokens.Surface.previewBackdropTop,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: DesignSystemPreviewTokens.previewWallpaperHeight)

                Circle()
                    .fill(SemanticTokens.Surface.previewOrbPrimary)
                    .frame(
                        width: DesignSystemPreviewTokens.glassOrbLarge,
                        height: DesignSystemPreviewTokens.glassOrbLarge
                    )
                    .blur(radius: PrimitiveTokens.Space.xxl * 2)
                    .offset(
                        x: -PrimitiveTokens.Space.xxl * 2,
                        y: -PrimitiveTokens.Space.xl
                    )

                Circle()
                    .fill(SemanticTokens.Surface.previewOrbSecondary)
                    .frame(
                        width: DesignSystemPreviewTokens.glassOrbMedium,
                        height: DesignSystemPreviewTokens.glassOrbMedium
                    )
                    .blur(radius: PrimitiveTokens.Space.xxl * 2)
                    .offset(
                        x: PrimitiveTokens.Space.xxl * 2,
                        y: PrimitiveTokens.Space.xl
                    )

                HStack(spacing: PrimitiveTokens.Space.lg) {
                    GlassPanel(style: .showcase) {
                        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                            Text("GlassPanel")
                                .font(PrimitiveTokens.Typography.bodyStrong)
                                .foregroundStyle(SemanticTokens.Text.primary)

                            Text("Top-level shell")
                                .font(PrimitiveTokens.Typography.meta)
                                .foregroundStyle(SemanticTokens.Text.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)

                    SearchFieldSurface(style: .quiet) {
                        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                            Text("Type and press Enter to save")
                                .font(PrimitiveTokens.Typography.captureInput)
                                .foregroundStyle(SemanticTokens.Text.secondary)

                            Text("Shift+Enter adds a new line")
                                .font(PrimitiveTokens.Typography.meta)
                                .foregroundStyle(SemanticTokens.Text.secondary)
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: DesignSystemPreviewTokens.previewFieldMinHeight,
                            alignment: .topLeading
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(PrimitiveTokens.Space.xl)
            }
            .clipShape(RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.xl, style: .continuous))
        }
    }

    private var liveGallerySection: some View {
        sectionBlock(
            title: "Live Gallery",
            subtitle: "These previews show the shared surfaces and feature views together, with the current glass treatment and type scale applied."
        ) {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: DesignSystemPreviewTokens.componentGridMinWidth),
                        spacing: PrimitiveTokens.Space.md
                    )
                ],
                spacing: PrimitiveTokens.Space.md
            ) {
                previewCard(title: "Capture Lane") {
                    SearchFieldSurface {
                        CueEditorLivePreview()
                    }
                    .frame(width: DesignSystemPreviewTokens.previewFieldWidth, alignment: .leading)
                }

                previewCard(title: "CardSurface") {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                        CardSurface {
                            Text("Default surface")
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(SemanticTokens.Text.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        CardSurface(isSelected: true) {
                            Text("Selected surface")
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(SemanticTokens.Text.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                previewCard(title: "PromptCueChip") {
                    HStack(spacing: PrimitiveTokens.Space.sm) {
                        PromptCueChip {
                            Text("Default")
                                .font(PrimitiveTokens.Typography.chip)
                                .foregroundStyle(SemanticTokens.Text.primary)
                        }

                        PromptCueChip(
                            fill: SemanticTokens.Surface.accentFill,
                            border: SemanticTokens.Border.emphasis
                        ) {
                            Text("Selected")
                                .font(PrimitiveTokens.Typography.chip)
                                .foregroundStyle(SemanticTokens.Text.selection)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                previewCard(title: "PanelHeader") {
                    PanelHeader(
                        title: "Backtick",
                        subtitle: "3 cues in temporary stack"
                    )
                    .frame(width: DesignSystemPreviewTokens.headerPreviewWidth, alignment: .leading)
                }

                previewCard(title: "LocalImageThumbnail") {
                    LocalImageThumbnail(url: URL(fileURLWithPath: "/tmp/prompt-cue-design-system-missing.png"))
                        .frame(width: DesignSystemPreviewTokens.thumbnailPreviewWidth)
                }

                previewCard(title: "CaptureCardView") {
                    CaptureCardView(
                        card: sampleCard,
                        isSelected: false,
                        selectionMode: false,
                        isExpanded: false,
                        onCopy: {},
                        onToggleSelection: {},
                        onToggleExpansion: {},
                        onDelete: {}
                    )
                    .frame(width: DesignSystemPreviewTokens.previewCardWidth, alignment: .leading)
                }

                previewCard(title: "PromptCueSettingsView") {
                    PromptCueSettingsView()
                        .frame(height: DesignSystemPreviewTokens.previewSettingsHeight)
                }
            }
        }
    }

    private var settingsSimulationSection: some View {
        sectionBlock(
            title: "Settings Simulation",
            subtitle: "Preview-only mock layouts for the settings refactor. Validate one group = one left rail + one right rail before touching the live settings surface."
        ) {
            SettingsSimulationView()
                .frame(height: DesignSystemPreviewTokens.previewSettingsSimulationHeight)
        }
    }

    private var foundationsSection: some View {
        HStack(alignment: .top, spacing: PrimitiveTokens.Space.lg) {
            sectionBlock(
                title: "Typography",
                subtitle: "The capture lane is 17/22. Reading copy steps down to 15, then 13, then 11."
            ) {
                VStack(spacing: PrimitiveTokens.Space.sm) {
                    TypographyRow(
                        name: "Capture Input",
                        usage: "Primary capture field",
                        font: PrimitiveTokens.Typography.captureInput,
                        sample: "Type and press Enter to save"
                    )

                    TypographyRow(
                        name: "Body",
                        usage: "Cards and readable content",
                        font: PrimitiveTokens.Typography.body,
                        sample: "This is the main reading size for Backtick surfaces."
                    )

                    TypographyRow(
                        name: "Meta",
                        usage: "Timestamps, helper copy, chips",
                        font: PrimitiveTokens.Typography.meta,
                        sample: "5 min ago"
                    )

                    TypographyRow(
                        name: "Selection",
                        usage: "Dense badges and labels",
                        font: PrimitiveTokens.Typography.selection,
                        sample: "2 SELECTED"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            sectionBlock(
                title: "Palette and Layout",
                subtitle: "Semantic swatches and the spacing and radius primitives used by the shared surfaces."
            ) {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.lg) {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: DesignSystemPreviewTokens.tokenGridMinWidth),
                                spacing: PrimitiveTokens.Space.md
                            )
                        ],
                        spacing: PrimitiveTokens.Space.md
                    ) {
                        ForEach(colorTokens) { token in
                            ColorSwatch(name: token.name, color: token.color)
                        }
                    }

                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                        Text("Spacing")
                            .font(PrimitiveTokens.Typography.bodyStrong)
                            .foregroundStyle(SemanticTokens.Text.primary)

                        HStack(spacing: PrimitiveTokens.Space.sm) {
                            ForEach(spacingTokens) { token in
                                TokenPill(title: token.name, value: token.value)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                        Text("Radius")
                            .font(PrimitiveTokens.Typography.bodyStrong)
                            .foregroundStyle(SemanticTokens.Text.primary)

                        HStack(spacing: PrimitiveTokens.Space.sm) {
                            ForEach(radiusTokens) { token in
                                RadiusPreview(name: token.name, radius: CGFloat(token.value))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func sectionBlock<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxxs) {
                    Text(title)
                        .font(PrimitiveTokens.Typography.panelTitle)
                        .foregroundStyle(SemanticTokens.Text.primary)

                    Text(subtitle)
                        .font(PrimitiveTokens.Typography.meta)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                }

                content()
            }
        }
    }

    private func principleChip(_ title: String) -> some View {
        PromptCueChip(
            fill: SemanticTokens.Surface.accentFill,
            border: SemanticTokens.Border.emphasis
        ) {
            Text(title)
                .font(PrimitiveTokens.Typography.chip)
                .foregroundStyle(SemanticTokens.Text.selection)
        }
    }

    private func heroStat(title: String, value: String) -> some View {
        CardSurface {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxxs) {
                Text(title)
                    .font(PrimitiveTokens.Typography.meta)
                    .foregroundStyle(SemanticTokens.Text.secondary)

                Text(value)
                    .font(PrimitiveTokens.Typography.bodyStrong)
                    .foregroundStyle(SemanticTokens.Text.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func previewCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        CardSurface {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                Text(title)
                    .font(PrimitiveTokens.Typography.bodyStrong)
                    .foregroundStyle(SemanticTokens.Text.primary)

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ComponentInventoryEntry: Identifiable {
    let name: String
    let path: String
    let category: String
    let role: String
    let usesGlass: Bool
    let hasLivePreview: Bool

    var id: String { name }
}

private struct ColorTokenEntry: Identifiable {
    let name: String
    let color: Color

    var id: String { name }
}

private struct TokenEntry: Identifiable {
    let name: String
    let value: Int

    var id: String { name }
}

private struct ComponentInventoryCard: View {
    let entry: ComponentInventoryEntry

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                HStack(alignment: .top, spacing: PrimitiveTokens.Space.xs) {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxxs) {
                        Text(entry.name)
                            .font(PrimitiveTokens.Typography.bodyStrong)
                            .foregroundStyle(SemanticTokens.Text.primary)

                        Text(entry.category)
                            .font(PrimitiveTokens.Typography.meta)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                    }

                    Spacer(minLength: PrimitiveTokens.Space.xs)

                    inventoryBadge(
                        title: entry.usesGlass ? "Glass" : "Solid",
                        emphasized: entry.usesGlass
                    )
                }

                Text(entry.role)
                    .font(PrimitiveTokens.Typography.meta)
                    .foregroundStyle(SemanticTokens.Text.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.path)
                    .font(PrimitiveTokens.Typography.selection)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                inventoryBadge(
                    title: entry.hasLivePreview ? "Live Preview" : "Inventory Only",
                    emphasized: entry.hasLivePreview
                )
            }
            .frame(
                maxWidth: .infinity,
                minHeight: DesignSystemPreviewTokens.inventoryCardMinHeight,
                alignment: .topLeading
            )
        }
    }

    private func inventoryBadge(title: String, emphasized: Bool) -> some View {
        PromptCueChip(
            fill: emphasized ? SemanticTokens.Surface.accentFill : SemanticTokens.Surface.cardFill,
            border: emphasized ? SemanticTokens.Border.emphasis : SemanticTokens.Border.subtle
        ) {
            Text(title)
                .font(PrimitiveTokens.Typography.chip)
                .foregroundStyle(emphasized ? SemanticTokens.Text.selection : SemanticTokens.Text.primary)
        }
    }
}

private struct CueEditorLivePreview: View {
    @State private var text = "Type and press Enter to save"
    @State private var metrics = CaptureEditorMetrics.empty

    var body: some View {
        CueTextEditor(
            text: $text,
            placeholder: "Type and press Enter to save",
            maxContentHeight: CaptureRuntimeMetrics.editorMaxHeight,
            onMetricsChange: { nextMetrics in
                metrics = nextMetrics
            },
            onSubmit: {},
            onCancel: {}
        )
        .frame(
            maxWidth: .infinity,
            minHeight: max(DesignSystemPreviewTokens.previewFieldTextHeight, metrics.visibleHeight),
            alignment: .topLeading
        )
    }
}

private struct TypographyRow: View {
    let name: String
    let usage: String
    let font: Font
    let sample: String

    var body: some View {
        CardSurface {
            HStack(alignment: .top, spacing: PrimitiveTokens.Space.md) {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxxs) {
                    Text(name)
                        .font(PrimitiveTokens.Typography.bodyStrong)
                        .foregroundStyle(SemanticTokens.Text.primary)

                    Text(usage)
                        .font(PrimitiveTokens.Typography.meta)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(sample)
                    .font(font)
                    .foregroundStyle(SemanticTokens.Text.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ColorSwatch: View {
    let name: String
    let color: Color

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                    .fill(color)
                    .frame(height: DesignSystemPreviewTokens.swatchHeight)
                    .overlay {
                        RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                            .stroke(SemanticTokens.Border.subtle)
                    }

                Text(name)
                    .font(PrimitiveTokens.Typography.metaStrong)
                    .foregroundStyle(SemanticTokens.Text.primary)
            }
        }
    }
}

private struct TokenPill: View {
    let title: String
    let value: Int

    var body: some View {
        PromptCueChip {
            Text("\(title) \(value)")
                .font(PrimitiveTokens.Typography.chip)
                .foregroundStyle(SemanticTokens.Text.primary)
        }
    }
}

private struct RadiusPreview: View {
    let name: String
    let radius: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(SemanticTokens.Surface.cardFill)
                .frame(
                    width: PrimitiveTokens.Size.thumbnailHeight,
                    height: PrimitiveTokens.Size.searchFieldHeight
                )
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(SemanticTokens.Border.subtle)
                }

            Text(name)
                .font(PrimitiveTokens.Typography.meta)
                .foregroundStyle(SemanticTokens.Text.secondary)
        }
    }
}
