import SwiftUI

struct SettingsSimulationView: View {
    private let simulatedLabelColumnWidth: CGFloat = SettingsTokens.Layout.labelColumnWidth

    private enum Page: String, CaseIterable, Identifiable {
        case general = "General"
        case capture = "Capture"
        case stack = "Stack"

        var id: String { rawValue }
    }

    private struct SidebarEntry: Identifiable {
        let page: Page?
        let title: String
        let systemImage: String
        let color: Color

        var id: String { title }
    }

    private enum ThemeOption: String, CaseIterable, Identifiable {
        case auto = "Auto"
        case light = "Light"
        case dark = "Dark"

        var id: String { rawValue }
    }

    private enum SimulationStatusTone {
        case success
        case neutral

        var fill: Color {
            switch self {
            case .success:
                return Color(nsColor: .systemGreen)
            case .neutral:
                return SettingsSemanticTokens.Text.secondary
            }
        }

        var foreground: Color {
            switch self {
            case .success:
                return Color(nsColor: .systemGreen).opacity(0.18)
            case .neutral:
                return Color.white.opacity(0.08)
            }
        }
    }

    @State private var selectedPage: Page = .general

    private let sidebarEntries: [SidebarEntry] = [
        .init(page: .general, title: "General", systemImage: "gearshape.fill", color: Color(nsColor: .systemGray)),
        .init(page: .capture, title: "Capture", systemImage: "rectangle.dashed", color: Color(nsColor: .systemPurple)),
        .init(page: .stack, title: "Stack", systemImage: "shippingbox.fill", color: Color(nsColor: .systemOrange)),
        .init(page: nil, title: "Connectors", systemImage: "link", color: Color(nsColor: .systemBlue)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
            HStack {
                Picker("Simulation", selection: $selectedPage) {
                    ForEach(Page.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Spacer(minLength: 0)

                Text("Preview-only mock")
                    .font(SettingsTokens.Typography.supporting)
                    .foregroundStyle(SettingsSemanticTokens.Text.secondary)
            }

            HStack(spacing: 0) {
                sidebar

                Rectangle()
                    .fill(SettingsSemanticTokens.Border.paneDivider)
                    .frame(width: 1)

                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsSemanticTokens.Surface.contentBackground)
            .clipShape(RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.lg, style: .continuous)
                    .stroke(SemanticTokens.Border.subtle, lineWidth: PrimitiveTokens.Stroke.subtle)
            }
        }
    }

    private var sidebar: some View {
        ZStack {
            SettingsSemanticTokens.Surface.sidebarBackground

            LinearGradient(
                colors: [
                    SettingsSemanticTokens.Surface.sidebarBackgroundTopTint,
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    SettingsSemanticTokens.Surface.sidebarBackgroundBottomShade,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: SettingsTokens.Layout.sidebarItemSpacing) {
                ForEach(sidebarEntries) { entry in
                    SettingsSidebarItem(
                        title: entry.title,
                        systemImage: entry.systemImage,
                        iconFill: entry.color,
                        isSelected: entry.page == selectedPage,
                        action: entry.page == nil ? nil : { selectedPage = entry.page! }
                    )
                    .opacity(entry.page == nil ? 0.72 : 1.0)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, SettingsTokens.Layout.sidebarVerticalPadding)
            .padding(.horizontal, SettingsTokens.Layout.sidebarHorizontalPadding)
        }
        .frame(width: SettingsTokens.Layout.sidebarWidth)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedPage.rawValue)
                    .font(SettingsTokens.Typography.pageTitle)
                    .foregroundStyle(SettingsSemanticTokens.Text.primary)

                VStack(alignment: .leading, spacing: SettingsTokens.Layout.sectionSpacing) {
                    switch selectedPage {
                    case .general:
                        generalProposal
                    case .capture:
                        captureProposal
                    case .stack:
                        stackProposal
                    }
                }
                .padding(.top, SettingsTokens.Layout.titleToFirstSectionSpacing)
            }
            .frame(maxWidth: SettingsTokens.Layout.contentMaxWidth, alignment: .leading)
            .padding(.leading, SettingsTokens.Layout.pageLeadingPadding)
            .padding(.trailing, SettingsTokens.Layout.pageTrailingPadding)
            .padding(.top, SettingsTokens.Layout.pageTopPadding)
            .padding(.bottom, SettingsTokens.Layout.pageBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var captureProposal: some View {
        SettingsSection(
            title: "Screenshots",
            footer: "Proposal: path and actions split into separate blocks so the row shell stops collapsing them into one dense strip."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                simulationGroupRow(title: "Status") {
                    simulationStatusBadge("Connected", tone: .success)
                }

                simulationGroupRow(title: "Folder", verticalAlignment: .top, showsDivider: false) {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                        Text("~/Downloads")
                            .font(PrimitiveTokens.Typography.body)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: PrimitiveTokens.Space.sm) {
                            Button("Change…") {}
                            Button("Reveal in Finder") {}
                            Button("Disconnect") {}
                        }
                    }
                }
            }
        }
    }

    private var stackProposal: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Layout.sectionSpacing) {
            SettingsSection(
                title: "Retention",
                footer: "Proposal: keep dense form rows only for short settings."
            ) {
                simulationGroupRow(title: "Card Lifetime", verticalAlignment: .top, showsDivider: false) {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                        Toggle("Auto-expire stack cards after 8 hours", isOn: .constant(false))
                            .toggleStyle(.checkbox)

                        Text("Cards stay until you delete them unless auto-expire is enabled.")
                            .font(SettingsTokens.Typography.supporting)
                            .foregroundStyle(SettingsSemanticTokens.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Off by default. Turn this on to restore the original 8-hour cleanup behavior.")
                            .font(SettingsTokens.Typography.supporting)
                            .foregroundStyle(SettingsSemanticTokens.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsSection(
                title: "AI Export Tail",
                footer: "Proposal: one behavior row, then separate long-form blocks with open spacing instead of shared row dividers."
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    simulationGroupRow(title: "Behavior", verticalAlignment: .top) {
                        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                            Toggle("Append AI export tail", isOn: .constant(true))
                                .toggleStyle(.checkbox)

                            Text("Append your reusable instruction block to copied text without modifying saved cards.")
                                .font(SettingsTokens.Typography.supporting)
                                .foregroundStyle(SettingsSemanticTokens.Text.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    simulationLongFormRow(title: "Tail Text") {
                        SettingsInlinePanel {
                            Text(mockTailText)
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(SemanticTokens.Text.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 120, alignment: .topLeading)
                        }
                    }

                    simulationLongFormRow(title: "Preview", actionTitle: "Reset to Default", showsDivider: false) {
                        SettingsInlinePanel {
                            Text(mockPreviewText)
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(SemanticTokens.Text.secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 120, alignment: .topLeading)
                        }
                    }
                }
            }
        }
    }

    private var generalProposal: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Layout.sectionSpacing) {
            SettingsSection(
                title: "Appearance",
                footer: "Proposal: simple trailing-control group with a consistent trailing rail."
            ) {
                simulationGroupRow(title: "Theme", showsDivider: false) {
                    Picker("", selection: .constant(ThemeOption.auto)) {
                        ForEach(ThemeOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            SettingsSection(
                title: "Shortcuts",
                footer: "Proposal: recorder controls share one trailing rail instead of floating independently."
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    simulationGroupRow(title: "Quick Capture") {
                        simulationShortcutRecorder("⌘`")
                    }

                    simulationGroupRow(title: "Show Stack", showsDivider: false) {
                        simulationShortcutRecorder("⌘2")
                    }
                }
            }

            SettingsSection(
                title: "iCloud Sync",
                footer: "Proposal: detail group with one label rail, one content rail, and one trailing status treatment."
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    simulationGroupRow(title: "Sync", verticalAlignment: .top) {
                        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                            Toggle("Enable iCloud sync", isOn: .constant(false))
                                .toggleStyle(.checkbox)

                            Text("Cards sync automatically between Macs signed into the same Apple ID.")
                                .font(SettingsTokens.Typography.supporting)
                                .foregroundStyle(SettingsSemanticTokens.Text.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    simulationGroupRow(title: "Status", showsDivider: false) {
                        simulationStatusBadge("Disabled", tone: .neutral)
                    }
                }
            }
        }
    }

    private func simulationGroupRow<Content: View>(
        title: String,
        verticalAlignment: VerticalAlignment = .center,
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: verticalAlignment, spacing: SettingsTokens.Layout.rowLabelToValueGap) {
            Text(title)
                .font(SettingsTokens.Typography.rowLabel)
                .foregroundStyle(SettingsSemanticTokens.Text.primary)
                .frame(width: simulatedLabelColumnWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: SettingsTokens.Layout.formRowMinHeight, alignment: .leading)
        .padding(.horizontal, SettingsTokens.Layout.groupInset)
        .padding(.vertical, SettingsTokens.Layout.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(SettingsSemanticTokens.Border.rowSeparator)
                    .frame(height: 1)
                    .padding(.horizontal, SettingsTokens.Layout.groupInset)
            }
        }
    }

    private func simulationLongFormRow<Content: View>(
        title: String,
        actionTitle: String? = nil,
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        simulationGroupRow(title: title, verticalAlignment: .top, showsDivider: showsDivider) {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                if let actionTitle {
                    HStack(alignment: .firstTextBaseline, spacing: PrimitiveTokens.Space.sm) {
                        Spacer(minLength: 0)

                        Button(actionTitle) {}
                            .controlSize(.small)
                    }
                }

                content()
            }
        }
    }

    private func simulationShortcutRecorder(_ shortcut: String) -> some View {
        HStack(spacing: PrimitiveTokens.Space.xxs) {
            Text(shortcut)
                .font(PrimitiveTokens.Typography.metaStrong)
                .foregroundStyle(SemanticTokens.Text.primary)

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SemanticTokens.Text.secondary)
        }
        .padding(.horizontal, PrimitiveTokens.Space.sm)
        .padding(.vertical, PrimitiveTokens.Space.xxs)
        .background(SettingsSemanticTokens.Surface.inlinePanelFill)
        .clipShape(RoundedRectangle(cornerRadius: SettingsTokens.Layout.fieldCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTokens.Layout.fieldCornerRadius, style: .continuous)
                .stroke(SettingsSemanticTokens.Border.formGroup, lineWidth: PrimitiveTokens.Stroke.subtle)
        }
    }

    private func simulationStatusBadge(_ title: String, tone: SimulationStatusTone) -> some View {
        HStack(spacing: PrimitiveTokens.Space.xxs) {
            Circle()
                .fill(tone.fill)
                .frame(width: 8, height: 8)

            Text(title)
                .font(PrimitiveTokens.Typography.bodyStrong)
                .foregroundStyle(SemanticTokens.Text.primary)
        }
        .padding(.horizontal, PrimitiveTokens.Space.sm)
        .padding(.vertical, PrimitiveTokens.Space.xxs)
        .background(tone.foreground)
        .clipShape(Capsule(style: .continuous))
    }
}

private let mockTailText = """
The note above is raw input.

First, determine the intent and appropriate response:
- If reporting a problem → diagnose root cause first
- If requesting a feature → review carefully and plan phases
"""

private let mockPreviewText = """
- root cause looks like async panel timing
- verify with tests before changing layout again

The note above is raw input.
"""
