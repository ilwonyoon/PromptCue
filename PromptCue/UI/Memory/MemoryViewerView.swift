import AppKit
import SwiftUI
import PromptCueCore

@MainActor
final class MemoryViewerUIState: ObservableObject {
    @Published var isEditing = false
    @Published var editorText = ""
    @Published var didCopy = false
    @Published var isPresentingNewDocumentSheet = false
    @Published var newDocumentDraft = MemoryViewerModel.NewDocumentDraft()
    @Published var newDocumentErrorMessage: String?

    private var copiedResetWorkItem: DispatchWorkItem?

    func syncSelection(with model: MemoryViewerModel) {
        if !isEditing {
            editorText = model.selectedDocument?.content ?? ""
        }
        didCopy = false
    }

    func startEditing(with model: MemoryViewerModel) {
        editorText = model.selectedDocument?.content ?? ""
        isEditing = true
    }

    func cancelEditing(with model: MemoryViewerModel) {
        editorText = model.selectedDocument?.content ?? ""
        isEditing = false
    }

    func finishDeletion(with model: MemoryViewerModel) {
        isEditing = false
        editorText = model.selectedDocument?.content ?? ""
        didCopy = false
    }

    func prepareNewDocumentDraft(using model: MemoryViewerModel) {
        newDocumentDraft = model.prepareNewDocumentDraft()
        newDocumentErrorMessage = nil
        isPresentingNewDocumentSheet = true
    }

    func showCopiedFeedback() {
        copiedResetWorkItem?.cancel()
        didCopy = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.didCopy = false
        }
        copiedResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }
}

struct MemoryViewerView: View {
    @ObservedObject var model: MemoryViewerModel
    @StateObject private var uiState: MemoryViewerUIState

    init(model: MemoryViewerModel, uiState: MemoryViewerUIState? = nil) {
        self.model = model
        _uiState = StateObject(wrappedValue: uiState ?? MemoryViewerUIState())
    }

    var body: some View {
        NavigationSplitView {
            MemoryProjectsPaneView(model: model, uiState: uiState)
                .navigationSplitViewColumnWidth(
                    min: PanelMetrics.memoryProjectColumnMinWidth,
                    ideal: PanelMetrics.memoryProjectColumnWidth,
                    max: PanelMetrics.memoryProjectColumnMaxWidth
                )
        } content: {
            MemoryDocumentsPaneView(model: model, uiState: uiState)
                .navigationSplitViewColumnWidth(
                    min: PanelMetrics.memoryDocumentColumnMinWidth,
                    ideal: PanelMetrics.memoryDocumentColumnDefaultWidth,
                    max: PanelMetrics.memoryDocumentColumnMaxWidth
                )
        } detail: {
            MemoryDetailPaneView(model: model, uiState: uiState)
                .frame(minWidth: PanelMetrics.memoryDetailMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            MemoryPaneColors.windowBackground
                .ignoresSafeArea()
        }
        .background {
            Button("", action: refreshMemory)
                .keyboardShortcut("r", modifiers: [.command])
                .labelsHidden()
                .hidden()
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $uiState.isPresentingNewDocumentSheet) {
            MemoryNewDocumentSheet(
                draft: $uiState.newDocumentDraft,
                errorMessage: uiState.newDocumentErrorMessage,
                onPasteClipboard: {
                    let pastedText = model.pasteboardString()
                    guard let pastedText,
                          !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        uiState.newDocumentErrorMessage = "Clipboard does not contain text."
                        return
                    }

                    uiState.newDocumentDraft.content = MemoryViewerModel.NewDocumentDraft
                        .contentForPastedText(pastedText)
                    uiState.newDocumentErrorMessage = nil
                },
                onCancel: {
                    uiState.isPresentingNewDocumentSheet = false
                    uiState.newDocumentErrorMessage = nil
                },
                onCreate: {
                    if model.createDocument(
                        project: uiState.newDocumentDraft.project,
                        topic: uiState.newDocumentDraft.topic,
                        documentType: uiState.newDocumentDraft.documentType,
                        content: uiState.newDocumentDraft.content
                    ) {
                        uiState.isPresentingNewDocumentSheet = false
                        uiState.newDocumentErrorMessage = nil
                    } else {
                        uiState.newDocumentErrorMessage = model.storageErrorMessage
                    }
                }
            )
        }
        .onChange(of: model.selectedDocument?.id) { _, _ in
            uiState.syncSelection(with: model)
        }
    }

    private func refreshMemory() {
        model.refresh()
        uiState.syncSelection(with: model)
    }
}

struct MemoryProjectsPaneView: View {
    @ObservedObject var model: MemoryViewerModel
    @ObservedObject var uiState: MemoryViewerUIState

    var body: some View {
        MemoryProjectListPane(
            projects: model.projects,
            selectedProject: model.selectedProject,
            isInteractionDisabled: uiState.isEditing,
            documentCount: { model.summaries(for: $0).count },
            onSelect: { model.selectedProject = $0 },
            onDeleteProject: confirmDeleteProject
        )
    }

    private func confirmDeleteProject(_ project: String) {
        let activeDocumentCount = model.summaries(for: project).count
        let confirmed = presentDeletionAlert(
            title: "Delete Project?",
            message: "Delete \(activeDocumentCount) active document(s) from \(project)? This keeps historical superseded rows hidden but intact.",
            actionTitle: "Delete Project"
        )

        guard confirmed else {
            return
        }

        let deletedSelectedProject = project == model.selectedProject
        if model.deleteProject(project),
           deletedSelectedProject {
            uiState.finishDeletion(with: model)
        }
    }
}

struct MemoryDocumentsPaneView: View {
    @ObservedObject var model: MemoryViewerModel
    @ObservedObject var uiState: MemoryViewerUIState

    var body: some View {
        MemoryColumnPane(backgroundColor: MemoryPaneColors.textBackground) {
            VStack(spacing: 0) {
                MemoryDocumentsHeader(
                    title: model.selectedProject ?? "Memory",
                    subtitle: "\(model.summaries(for: model.selectedProject).count) memory",
                    onCreateDocument: openNewDocumentSheet
                )

                MemoryDocumentListPane(
                    selectedProject: model.selectedProject,
                    summaries: model.summaries(for: model.selectedProject),
                    selectedDocumentKey: model.selectedDocumentKey,
                    isInteractionDisabled: uiState.isEditing,
                    onSelect: { model.selectedDocumentKey = $0 },
                    onCopyDocument: copyDocument,
                    onEditDocument: startEditingDocument,
                    onDeleteDocument: deleteDocument
                )
            }
        }
    }

    private func copyDocument(_ key: ProjectDocumentKey) {
        model.selectedDocumentKey = key
        model.copySelectedDocument()
        uiState.showCopiedFeedback()
    }

    private func startEditingDocument(_ key: ProjectDocumentKey) {
        model.selectedDocumentKey = key
        uiState.startEditing(with: model)
    }

    private func deleteDocument(_ key: ProjectDocumentKey) {
        model.selectedDocumentKey = key
        confirmDeleteSelectedDocument(model: model, uiState: uiState)
    }

    private func openNewDocumentSheet() {
        uiState.prepareNewDocumentDraft(using: model)
    }
}

struct MemoryDetailPaneView: View {
    @ObservedObject var model: MemoryViewerModel
    @ObservedObject var uiState: MemoryViewerUIState

    var body: some View {
        MemoryColumnPane(backgroundColor: MemoryPaneColors.textBackground) {
            MemoryDetailPane(
                document: model.selectedDocument,
                isEditing: $uiState.isEditing,
                editorText: $uiState.editorText,
                didCopy: $uiState.didCopy,
                onCopy: {
                    model.copySelectedDocument()
                    uiState.showCopiedFeedback()
                },
                onStartEditing: {
                    uiState.startEditing(with: model)
                },
                onCancelEditing: {
                    uiState.cancelEditing(with: model)
                },
                onSaveEditing: {
                    switch model.saveSelectedDocumentContent(uiState.editorText) {
                    case .saved:
                        uiState.isEditing = false
                    case .deleteIntent:
                        confirmDeleteSelectedDocument(model: model, uiState: uiState)
                    case .failed:
                        break
                    }
                },
                onDeleteDocument: {
                    confirmDeleteSelectedDocument(model: model, uiState: uiState)
                }
            )
        }
        .overlay(alignment: .bottomLeading) {
            if let storageErrorMessage = model.storageErrorMessage {
                Text(storageErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, MemoryPaneMetrics.statusMessageHorizontalInset)
                    .padding(.bottom, MemoryPaneMetrics.statusMessageBottomInset)
            }
        }
    }
}

@MainActor
private func confirmDeleteSelectedDocument(
    model: MemoryViewerModel,
    uiState: MemoryViewerUIState
) {
    guard let document = model.selectedDocument else {
        return
    }

    let confirmed = presentDeletionAlert(
        title: "Delete Document?",
        message: "Delete \(document.topic) from \(document.project)? This removes it from the active Memory list.",
        actionTitle: "Delete"
    )

    guard confirmed else {
        return
    }

    if model.deleteSelectedDocument() {
        uiState.finishDeletion(with: model)
    }
}

private func presentDeletionAlert(
    title: String,
    message: String,
    actionTitle: String
) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.icon = nil
    alert.addButton(withTitle: actionTitle)
    alert.addButton(withTitle: "Cancel")
    alert.buttons.first?.hasDestructiveAction = true
    return alert.runModal() == .alertFirstButtonReturn
}

private enum MemoryPaneColors {
    static let textBackground = SemanticTokens.adaptiveColor(
        light: NSColor.textBackgroundColor,
        dark: NSColor(
            srgbRed: 31.0 / 255.0,
            green: 31.0 / 255.0,
            blue: 30.0 / 255.0,
            alpha: 1
        )
    )

    static let windowBackground = SemanticTokens.adaptiveColor(
        light: NSColor.windowBackgroundColor,
        dark: NSColor(
            srgbRed: 27.0 / 255.0,
            green: 27.0 / 255.0,
            blue: 26.0 / 255.0,
            alpha: 1
        )
    )

    static let separator = SemanticTokens.adaptiveColor(
        light: NSColor.separatorColor,
        dark: NSColor.white.withAlphaComponent(0.085)
    )

    static let separatorSoft = separator.opacity(0.42)
    static let separatorMedium = separator.opacity(0.5)
    static let separatorStrong = separator.opacity(0.55)
    static let separatorTable = separator.opacity(0.75)

    static let destructive = SemanticTokens.adaptiveColor(
        light: NSColor.systemRed,
        dark: NSColor.systemRed
    )
}

private enum MemoryPaneMetrics {
    static let paneScrollHorizontalInset: CGFloat = 8
    static let paneScrollVerticalInset: CGFloat = 8
    static let documentListHorizontalInset: CGFloat = 14
    static let documentRowContentPadding: CGFloat = 10
    static let sidebarRowTextTopInset: CGFloat = 7
    static let contentRowTextTopInset: CGFloat = 6
    static let chromeBarMinHeight: CGFloat = 36
    static let chromeControlSize: CGFloat = 36
    static let sharedChromeHeaderHeight: CGFloat = 40
    static let detailHeaderChromeInset: CGFloat = 14
    static let chromeLaneTopInset: CGFloat = -44
    static let detailHeaderTopInset: CGFloat = chromeLaneTopInset + 4
    static let detailHeaderActionTrailingInset: CGFloat = 16
    static let documentsHeaderTopInset: CGFloat = detailHeaderTopInset
    static let chromeButtonOpticalYOffset: CGFloat = -1
    static let documentsHeaderTextTopInset: CGFloat = 2
    static let documentsHeaderContentHeight: CGFloat = sharedChromeHeaderHeight
    static let documentsHeaderDividerSpacing: CGFloat = 2
    static let documentsHeaderBottomInset: CGFloat = 0
    static let sharedHeaderTitleTopInset: CGFloat =
        documentsHeaderTopInset + documentsHeaderTextTopInset
    static let sharedHeaderDividerTopInset: CGFloat =
        documentsHeaderTopInset
        + sharedChromeHeaderHeight
        + documentsHeaderBottomInset
        + documentsHeaderDividerSpacing
    static let documentsListRowTopInsetFromPaneTop: CGFloat =
        sharedHeaderDividerTopInset
        + PrimitiveTokens.Stroke.subtle
        + paneScrollVerticalInset
    static let detailHeaderDividerTopInset: CGFloat =
        sharedHeaderDividerTopInset
    static let detailHeaderTitleOpticalOffset: CGFloat = 4
    static let detailHeaderTextTopInset: CGFloat =
        documentsListRowTopInsetFromPaneTop + detailHeaderTitleOpticalOffset
    static let detailHeaderContentBottomInset: CGFloat = 12
    static let detailContentInset: CGFloat = 24
    static let footerHorizontalInset: CGFloat = detailContentInset
    static let statusMessageHorizontalInset: CGFloat = PrimitiveTokens.Space.md
    static let statusMessageBottomInset: CGFloat = PrimitiveTokens.Space.sm
    static let footerActionIconSpacing: CGFloat = PrimitiveTokens.Space.xs
    static let footerActionHeight: CGFloat = 42
    static let footerHoverInset: CGFloat = PrimitiveTokens.Space.xs
    static let rowAccessorySpacing: CGFloat = 6
    static let rowCountSpacing: CGFloat = 4
    static let newDocumentFormSpacing: CGFloat = 18
    static let newDocumentFieldSpacing: CGFloat = 6
    static let newDocumentEditorMinHeight: CGFloat = 260
    static let newDocumentEditorOuterInset: CGFloat = 10
    static let newDocumentEditorCornerRadius: CGFloat = 10
    static let newDocumentSheetWidth: CGFloat = 620
    static let newDocumentSheetHeight: CGFloat = 560
    static let detailHeaderBottomInset: CGFloat = sharedChromeHeaderHeight - chromeBarMinHeight
    static let detailTitleBottomSpacing: CGFloat = PrimitiveTokens.Space.xs
    static let detailMetadataSpacing: CGFloat = 6
    static let detailCopyIconSize: CGFloat = 24
    static let renderedSectionSpacing: CGFloat = 30
    static let renderedBlockSpacing: CGFloat = 24
    static let renderedListSpacing: CGFloat = 10
    static let renderedBulletSize: CGFloat = 5
    static let renderedNestedBulletSize: CGFloat = 4
    static let renderedBulletTopInset: CGFloat = PrimitiveTokens.Space.xs
    static let renderedTopInset: CGFloat = 14
    static let renderedBottomInset: CGFloat = 28
    static let renderedNumberMinWidth: CGFloat = 24
    static let tableCornerRadius: CGFloat = 10
    static let tableVerticalInset: CGFloat = 2
    static let tableCellMinWidth: CGFloat = 120
    static let tableCellVerticalInset: CGFloat = 10
    static let emptyStateMaxWidth: CGFloat = 320
    static let tagCompactHeight: CGFloat = 18
    static let tagRegularHeight: CGFloat = 22
    static let tagCompactHorizontalInset: CGFloat = 6
}

private enum MemoryPaneTypography {
    static let footerActionIcon = PrimitiveTokens.Typography.metaStrong
    static let accessoryIcon = Font.system(size: PrimitiveTokens.FontSize.chip, weight: .semibold)
    static let summaryRow = PrimitiveTokens.Typography.meta
    static let codeLanguage = Font.system(size: PrimitiveTokens.FontSize.micro, weight: .medium)
    static let tag = Font.system(size: PrimitiveTokens.FontSize.micro, weight: .medium)
}

private enum MemoryLayoutDebug {
    static let isEnabled = false
    static let rowContent = Color.blue
    static let detailHeaderChrome = Color.orange
    static let detailContent = Color.green
}

private struct MemoryDebugOverlayModifier: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if MemoryLayoutDebug.isEnabled, let color {
            content
                .background(color.opacity(0.10))
                .overlay {
                    Rectangle()
                        .stroke(color.opacity(0.45), lineWidth: 1)
                }
        } else {
            content
        }
    }
}

private extension View {
    func memoryDebugOverlay(_ color: Color?) -> some View {
        modifier(MemoryDebugOverlayModifier(color: color))
    }
}

private struct MemoryChromeBar<Content: View>: View {
    let debugColor: Color?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, MemoryPaneMetrics.documentRowContentPadding)
            .frame(minHeight: MemoryPaneMetrics.chromeBarMinHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .memoryDebugOverlay(debugColor)
    }
}

private struct MemoryChromeControlButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemName)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: MemoryPaneMetrics.chromeControlSize, height: MemoryPaneMetrics.chromeControlSize)
            }
            .buttonStyle(.plain)
            .background {
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.10 : 0))
            }
            .glassEffect(.regular.interactive(), in: Circle())
            .offset(y: MemoryPaneMetrics.chromeButtonOpticalYOffset)
            .onHover { isHovered = $0 }
            .accessibilityLabel(accessibilityLabel)
        } else {
            Button(action: action) {
                Image(systemName: systemName)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SemanticTokens.Text.primary)
                    .frame(width: MemoryPaneMetrics.chromeControlSize, height: MemoryPaneMetrics.chromeControlSize)
                    .background(
                        Circle()
                            .fill(
                                isHovered
                                    ? SemanticTokens.Text.secondary.opacity(0.18)
                                    : SemanticTokens.Text.secondary.opacity(0.12)
                            )
                    )
            }
            .buttonStyle(.plain)
            .offset(y: MemoryPaneMetrics.chromeButtonOpticalYOffset)
            .onHover { isHovered = $0 }
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

private struct MemoryColumnPane<Content: View>: View {
    let backgroundColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColor)
    }
}

private struct MemoryPaneScrollBody<Content: View>: View {
    var horizontalPadding: CGFloat = MemoryPaneMetrics.paneScrollHorizontalInset
    var verticalPadding: CGFloat = MemoryPaneMetrics.paneScrollVerticalInset
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MemoryProjectListPane: View {
    let projects: [String]
    let selectedProject: String?
    let isInteractionDisabled: Bool
    let documentCount: (String) -> Int
    let onSelect: (String) -> Void
    let onDeleteProject: (String) -> Void

    var body: some View {
        MemoryPaneScrollBody {
            LazyVStack(spacing: PrimitiveTokens.Space.xxs) {
                ForEach(projects, id: \.self) { project in
                    let isSelected = project == selectedProject
                    CompactSelectableRow(
                        tone: .sidebar,
                        isSelected: isSelected,
                        action: {
                            guard !isInteractionDisabled else { return }
                            onSelect(project)
                        }
                    ) {
                        HStack(alignment: .firstTextBaseline, spacing: MemoryPaneMetrics.rowAccessorySpacing) {
                            Image(systemName: "folder")
                                .font(MemoryPaneTypography.accessoryIcon)
                                .foregroundStyle(
                                    isSelected
                                        ? MemoryProjectListColors.selectedTint
                                        : SemanticTokens.Text.secondary
                                )

                            Text(project)
                                .font(SettingsTokens.Typography.sidebarLabel)
                                .foregroundStyle(
                                    isSelected
                                        ? MemoryProjectListColors.selectedTint
                                        : SemanticTokens.Text.primary
                                )
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text("\(documentCount(project))")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(
                                    isSelected
                                        ? MemoryProjectListColors.selectedSecondaryTint
                                        : SemanticTokens.Text.secondary
                                )
                        }
                    }
                    .contextMenu {
                        Button("Delete Project...", role: .destructive) {
                            onDeleteProject(project)
                        }
                        .disabled(isInteractionDisabled)
                    }
                }
            }
        }
    }
}

private enum MemoryProjectListColors {
    static let selectedTint = SemanticTokens.adaptiveColor(
        light: NSColor(
            srgbRed: 179.0 / 255.0,
            green: 114.0 / 255.0,
            blue: 18.0 / 255.0,
            alpha: 1
        ),
        dark: NSColor(
            srgbRed: 246.0 / 255.0,
            green: 194.0 / 255.0,
            blue: 84.0 / 255.0,
            alpha: 1
        )
    )

    static let selectedSecondaryTint = selectedTint.opacity(0.92)
}

private struct MemoryDocumentListPane: View {
    let selectedProject: String?
    let summaries: [ProjectDocumentSummary]
    let selectedDocumentKey: ProjectDocumentKey?
    let isInteractionDisabled: Bool
    let onSelect: (ProjectDocumentKey) -> Void
    let onCopyDocument: (ProjectDocumentKey) -> Void
    let onEditDocument: (ProjectDocumentKey) -> Void
    let onDeleteDocument: (ProjectDocumentKey) -> Void

    @State private var isDormantExpanded = false

    private var activeSummaries: [ProjectDocumentSummary] {
        summaries.filter { $0.vividnessTier() != .dormant }
    }

    private var dormantSummaries: [ProjectDocumentSummary] {
        summaries.filter { $0.vividnessTier() == .dormant }
    }

    var body: some View {
        if summaries.isEmpty {
            MemoryEmptyState(
                title: selectedProject == nil ? "No Project Selected" : "No Documents",
                message: selectedProject == nil
                    ? "Create a durable document or choose a project to browse."
                    : "Create a durable document for this project."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MemoryPaneScrollBody(horizontalPadding: MemoryPaneMetrics.documentListHorizontalInset) {
                LazyVStack(spacing: PrimitiveTokens.Space.xxs) {
                    ForEach(activeSummaries) { summary in
                        documentRow(for: summary)
                    }

                    if !dormantSummaries.isEmpty {
                        dormantSection
                    }
                }
            }
        }
    }

    private func documentRow(for summary: ProjectDocumentSummary) -> some View {
        CompactSelectableRow(
            tone: .content,
            isSelected: summary.key == selectedDocumentKey,
            contentHorizontalPadding: MemoryPaneMetrics.documentRowContentPadding,
            debugFill: MemoryLayoutDebug.isEnabled ? MemoryLayoutDebug.rowContent : nil,
            action: {
                guard !isInteractionDisabled else { return }
                onSelect(summary.key)
            }
        ) {
            MemoryDocumentSummaryRow(
                summary: summary,
                isFading: summary.vividnessTier() == .fading
            )
        }
        .contextMenu {
            Button("Copy") {
                onCopyDocument(summary.key)
            }
            .disabled(isInteractionDisabled)
            Button("Edit") {
                onEditDocument(summary.key)
            }
            .disabled(isInteractionDisabled)
            Button("Delete", role: .destructive) {
                onDeleteDocument(summary.key)
            }
            .disabled(isInteractionDisabled)
        }
    }

    private var dormantSection: some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
            Button {
                withAnimation(.easeInOut(duration: PrimitiveTokens.Motion.hoverQuick)) {
                    isDormantExpanded.toggle()
                }
            } label: {
                HStack(spacing: PrimitiveTokens.Space.xxs) {
                    Image(systemName: isDormantExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SemanticTokens.Text.secondary)
                    Text("Older (\(dormantSummaries.count))")
                        .font(MemoryPaneTypography.summaryRow)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, PrimitiveTokens.Space.xxs)
            }
            .buttonStyle(.plain)

            if isDormantExpanded {
                ForEach(dormantSummaries) { summary in
                    documentRow(for: summary)
                }
            }
        }
        .padding(.top, PrimitiveTokens.Space.xs)
    }
}

private struct MemoryDocumentsHeader: View {
    let title: String
    let subtitle: String
    let onCreateDocument: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                HStack {
                    Spacer(minLength: 0)

                    if #available(macOS 26.0, *) {
                        GlassEffectContainer(spacing: 8) {
                            MemoryChromeControlButton(
                                systemName: "plus",
                                accessibilityLabel: "New document",
                                action: onCreateDocument
                            )
                        }
                    } else {
                        MemoryChromeControlButton(
                            systemName: "plus",
                            accessibilityLabel: "New document",
                            action: onCreateDocument
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(SemanticTokens.Text.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .lineLimit(1)
                }
                .padding(.top, MemoryPaneMetrics.documentsHeaderTextTopInset)
            }
            .frame(maxWidth: .infinity, minHeight: MemoryPaneMetrics.documentsHeaderContentHeight, alignment: .topLeading)
            .padding(.horizontal, MemoryPaneMetrics.documentListHorizontalInset)
            .padding(.top, MemoryPaneMetrics.documentsHeaderTopInset)
            .padding(.bottom, MemoryPaneMetrics.documentsHeaderBottomInset)

            Rectangle()
                .fill(MemoryPaneColors.separatorSoft)
                .frame(height: PrimitiveTokens.Stroke.subtle)
                .padding(.top, MemoryPaneMetrics.documentsHeaderDividerSpacing)
        }
    }
}

private struct MemoryDocumentSummaryRow: View {
    let summary: ProjectDocumentSummary
    var isFading: Bool = false

    var body: some View {
        Text(summary.topic)
            .font(MemoryPaneTypography.summaryRow)
            .lineLimit(1)
            .foregroundStyle(isFading ? SemanticTokens.Text.secondary : SemanticTokens.Text.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MemoryNewDocumentSheet: View {
    @Binding var draft: MemoryViewerModel.NewDocumentDraft
    let errorMessage: String?
    let onPasteClipboard: () -> Void
    let onCancel: () -> Void
    let onCreate: () -> Void

    private var canSubmit: Bool {
        !draft.project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draft.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MemoryPaneMetrics.newDocumentFormSpacing) {
                    Text("New Document")
                        .font(.title3.weight(.semibold))

                    HStack(alignment: .top, spacing: PrimitiveTokens.Space.sm) {
                        VStack(alignment: .leading, spacing: MemoryPaneMetrics.newDocumentFieldSpacing) {
                            Text("Project")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Project", text: $draft.project)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: MemoryPaneMetrics.newDocumentFieldSpacing) {
                            Text("Topic")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Topic", text: $draft.topic)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: MemoryPaneMetrics.newDocumentFieldSpacing) {
                        Text("Type")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Type", selection: $draft.documentType) {
                            ForEach(ProjectDocumentType.allCases, id: \.self) { documentType in
                                Text(documentType.rawValue.capitalized)
                                    .tag(documentType)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                        HStack {
                            Text("Content")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Paste Clipboard", action: onPasteClipboard)
                                .keyboardShortcut("v", modifiers: [.command, .shift])
                        }

                        MemoryPlainTextEditor(
                            text: $draft.content,
                            contentInsets: NSSize(width: 12, height: 12)
                        )
                        .frame(minHeight: MemoryPaneMetrics.newDocumentEditorMinHeight)
                        .padding(MemoryPaneMetrics.newDocumentEditorOuterInset)
                        .background(
                            RoundedRectangle(cornerRadius: MemoryPaneMetrics.newDocumentEditorCornerRadius, style: .continuous)
                                .fill(MemoryPaneColors.textBackground)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: MemoryPaneMetrics.newDocumentEditorCornerRadius, style: .continuous)
                                .stroke(MemoryPaneColors.separatorMedium, lineWidth: PrimitiveTokens.Stroke.subtle)
                        }
                    }
                }
                .padding(PrimitiveTokens.Space.xl)
            }

            Divider()

            HStack(alignment: .center, spacing: PrimitiveTokens.Space.md) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(MemoryPaneColors.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                        .frame(maxWidth: .infinity)
                }

                HStack(spacing: PrimitiveTokens.Space.sm) {
                    Button("Cancel", action: onCancel)
                    Button("Create", action: onCreate)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.55)
                }
            }
            .padding(.horizontal, PrimitiveTokens.Space.xl)
            .padding(.vertical, PrimitiveTokens.Space.md)
            .background(MemoryPaneColors.windowBackground)
        }
        .frame(width: MemoryPaneMetrics.newDocumentSheetWidth, height: MemoryPaneMetrics.newDocumentSheetHeight)
    }
}

private struct MemoryDetailPane: View {
    let document: ProjectDocument?
    @Binding var isEditing: Bool
    @Binding var editorText: String
    @Binding var didCopy: Bool
    let onCopy: () -> Void
    let onStartEditing: () -> Void
    let onCancelEditing: () -> Void
    let onSaveEditing: () -> Void
    let onDeleteDocument: () -> Void

    var body: some View {
        if let document {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        MemoryChromeBar(debugColor: MemoryLayoutDebug.detailHeaderChrome) {
                            HStack(alignment: .center, spacing: PrimitiveTokens.Space.sm) {
                                Spacer(minLength: 0)

                                if isEditing {
                                    actionCluster {
                                        MemoryChromeControlButton(
                                            systemName: "xmark",
                                            accessibilityLabel: "Cancel editing",
                                            action: onCancelEditing
                                        )
                                        MemoryChromeControlButton(
                                            systemName: "checkmark",
                                            accessibilityLabel: "Save document",
                                            action: onSaveEditing
                                        )
                                        .keyboardShortcut(.defaultAction)
                                    }
                                } else {
                                    actionCluster {
                                        MemoryChromeControlButton(
                                            systemName: "trash",
                                            accessibilityLabel: "Delete document",
                                            action: onDeleteDocument
                                        )
                                        MemoryChromeControlButton(
                                            systemName: "square.and.pencil",
                                            accessibilityLabel: "Edit document",
                                            action: onStartEditing
                                        )
                                        MemoryChromeControlButton(
                                            systemName: didCopy ? "checkmark" : "doc.on.doc",
                                            accessibilityLabel: didCopy ? "Copied document" : "Copy document",
                                            action: onCopy
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, MemoryPaneMetrics.detailHeaderChromeInset)
                        .padding(.top, MemoryPaneMetrics.detailHeaderTopInset)
                        .padding(.bottom, MemoryPaneMetrics.detailHeaderBottomInset)

                        Rectangle()
                            .fill(MemoryPaneColors.separatorSoft)
                            .frame(height: PrimitiveTokens.Stroke.subtle)
                            .padding(.top, MemoryPaneMetrics.detailHeaderDividerTopInset)

                        VStack(alignment: .leading, spacing: MemoryPaneMetrics.detailTitleBottomSpacing) {
                            Text(document.topic)
                                .font(.title2.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(alignment: .firstTextBaseline, spacing: MemoryPaneMetrics.detailMetadataSpacing) {
                                MemoryTag(text: document.documentType.rawValue)
                                    .layoutPriority(1)

                                Image(systemName: "folder")
                                    .font(MemoryPaneTypography.accessoryIcon)
                                    .foregroundStyle(SemanticTokens.Text.secondary)
                                    .accessibilityHidden(true)

                                Text(document.project)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Text("·")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)

                                Text(Self.timestampString(for: document.updatedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, MemoryPaneMetrics.detailHeaderTextTopInset)
                        .padding(.horizontal, MemoryPaneMetrics.detailContentInset)
                        .padding(.bottom, MemoryPaneMetrics.detailHeaderContentBottomInset)
                        .memoryDebugOverlay(MemoryLayoutDebug.detailContent)
                    }
                }

                if isEditing {
                    MemoryPlainTextEditor(text: $editorText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    MemoryRenderedDocumentView(markdown: document.content)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MemoryPaneColors.textBackground)
        } else {
            MemoryEmptyState(
                title: "No Document Selected",
                message: "Pick a durable document to inspect its saved markdown."
            )
        }
    }

    private static func timestampString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: date))"
    }

    @ViewBuilder
    private func actionCluster<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    content()
                }
            }
        } else {
            HStack(spacing: 8) {
                content()
            }
        }
    }
}

private struct MemoryRenderedDocumentView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoryPaneMetrics.renderedSectionSpacing) {
                ForEach(ParsedMemoryMarkdown.parse(markdown)) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        if let title = section.title {
                            Text(title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(SemanticTokens.Text.primary)
                                .padding(.bottom, PrimitiveTokens.Space.xs)
                        }

                        VStack(alignment: .leading, spacing: MemoryPaneMetrics.renderedBlockSpacing) {
                            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                                switch block {
                                case .paragraph(let text):
                                    MemoryInlineMarkdownText(markdown: text)
                                        .font(.body)
                                        .foregroundStyle(SemanticTokens.Text.primary)
                                        .lineSpacing(6)
                                        .fixedSize(horizontal: false, vertical: true)

                                case .bullets(let items):
                                    VStack(alignment: .leading, spacing: MemoryPaneMetrics.renderedListSpacing) {
                                        ForEach(items, id: \.self) { item in
                                            HStack(alignment: .top, spacing: MemoryPaneMetrics.renderedListSpacing) {
                                                Circle()
                                                    .fill(SemanticTokens.Text.secondary.opacity(0.7))
                                                    .frame(width: MemoryPaneMetrics.renderedBulletSize, height: MemoryPaneMetrics.renderedBulletSize)
                                                    .padding(.top, MemoryPaneMetrics.renderedBulletTopInset)

                                                MemoryInlineMarkdownText(markdown: item)
                                                    .font(.body)
                                                    .foregroundStyle(SemanticTokens.Text.primary)
                                                    .lineSpacing(6)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }

                                case .codeBlock(let language, let code):
                                    MemoryCodeBlockView(language: language, code: code)

                                case .table(let table):
                                    MemoryMarkdownTableView(table: table)

                                case .numberedList(let items):
                                    VStack(alignment: .leading, spacing: MemoryPaneMetrics.renderedListSpacing) {
                                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                                            HStack(alignment: .top, spacing: PrimitiveTokens.Space.xs) {
                                                Text("\(idx + 1).")
                                                    .font(.body.monospacedDigit())
                                                    .foregroundStyle(SemanticTokens.Text.secondary)
                                                    .frame(minWidth: MemoryPaneMetrics.renderedNumberMinWidth, alignment: .trailing)

                                                MemoryInlineMarkdownText(markdown: item)
                                                    .font(.body)
                                                    .foregroundStyle(SemanticTokens.Text.primary)
                                                    .lineSpacing(6)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }

                                case .nestedBullets(let items):
                                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                            HStack(alignment: .top, spacing: PrimitiveTokens.Space.xs) {
                                                Circle()
                                                    .fill(SemanticTokens.Text.secondary.opacity(
                                                        item.indent == 0 ? 0.7 : 0.45
                                                    ))
                                                    .frame(width: MemoryPaneMetrics.renderedNestedBulletSize, height: MemoryPaneMetrics.renderedNestedBulletSize)
                                                    .padding(.top, MemoryPaneMetrics.renderedBulletTopInset)

                                                MemoryInlineMarkdownText(markdown: item.text)
                                                    .font(.body)
                                                    .foregroundStyle(SemanticTokens.Text.primary)
                                                    .lineSpacing(6)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .padding(.leading, CGFloat(item.indent) * PrimitiveTokens.Space.md)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MemoryPaneMetrics.detailContentInset)
            .padding(.top, MemoryPaneMetrics.renderedTopInset)
            .padding(.bottom, MemoryPaneMetrics.renderedBottomInset)
        }
        .scrollIndicators(.hidden)
    }
}

private struct MemoryInlineMarkdownText: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
                .environment(\.openURL, OpenURLAction { url in
                    NSWorkspace.shared.open(url)
                    return .handled
                })
        } else {
            Text(markdown)
        }
    }
}

private struct MemoryCodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language {
                Text(language)
                    .font(MemoryPaneTypography.codeLanguage)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .padding(.horizontal, PrimitiveTokens.Space.sm)
                    .padding(.top, PrimitiveTokens.Space.xs)
                    .padding(.bottom, PrimitiveTokens.Space.xxs)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(PrimitiveTokens.Typography.code)
                    .foregroundStyle(SemanticTokens.Text.primary)
                    .textSelection(.enabled)
                    .padding(PrimitiveTokens.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: PrimitiveTokens.Space.xs, style: .continuous)
                .fill(SemanticTokens.Surface.raisedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PrimitiveTokens.Space.xs, style: .continuous)
                .stroke(SemanticTokens.Border.subtle, lineWidth: PrimitiveTokens.Stroke.subtle)
        )
    }
}

private struct MemoryMarkdownTableView: View {
    let table: ParsedMemoryMarkdown.Table

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { index, cell in
                        MemoryMarkdownTableCell(
                            markdown: cell,
                            alignment: table.alignment(at: index),
                            isHeader: true,
                            isStriped: false,
                            showsTrailingDivider: index < table.columnCount - 1,
                            showsBottomDivider: !table.rows.isEmpty
                        )
                    }
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, cell in
                            MemoryMarkdownTableCell(
                                markdown: cell,
                                alignment: table.alignment(at: columnIndex),
                                isHeader: false,
                                isStriped: rowIndex.isMultiple(of: 2),
                                showsTrailingDivider: columnIndex < table.columnCount - 1,
                                showsBottomDivider: rowIndex < table.rows.count - 1
                            )
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MemoryPaneMetrics.tableCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MemoryPaneMetrics.tableCornerRadius, style: .continuous)
                    .stroke(MemoryPaneColors.separatorTable, lineWidth: PrimitiveTokens.Stroke.subtle)
            }
            .padding(.vertical, MemoryPaneMetrics.tableVerticalInset)
        }
        .scrollIndicators(.hidden)
    }
}

private struct MemoryMarkdownTableCell: View {
    let markdown: String
    let alignment: ParsedMemoryMarkdown.TableColumnAlignment
    let isHeader: Bool
    let isStriped: Bool
    let showsTrailingDivider: Bool
    let showsBottomDivider: Bool

    var body: some View {
        MemoryInlineMarkdownText(markdown: markdown)
            .font(isHeader ? .callout.weight(.semibold) : .body)
            .foregroundStyle(SemanticTokens.Text.primary)
            .multilineTextAlignment(alignment.textAlignment)
            .frame(minWidth: MemoryPaneMetrics.tableCellMinWidth, maxWidth: .infinity, alignment: alignment.frameAlignment)
            .padding(.horizontal, PrimitiveTokens.Space.sm)
            .padding(.vertical, MemoryPaneMetrics.tableCellVerticalInset)
            .background(backgroundFill)
            .overlay(alignment: .trailing) {
                if showsTrailingDivider {
                    Rectangle()
                        .fill(MemoryPaneColors.separatorStrong)
                        .frame(width: PrimitiveTokens.Stroke.subtle)
                }
            }
            .overlay(alignment: .bottom) {
                if showsBottomDivider {
                    Rectangle()
                        .fill(MemoryPaneColors.separatorStrong)
                        .frame(height: PrimitiveTokens.Stroke.subtle)
                }
            }
    }

    private var backgroundFill: Color {
        if isHeader {
            return SemanticTokens.adaptiveColor(
                light: NSColor.black.withAlphaComponent(0.04),
                dark: NSColor.white.withAlphaComponent(0.08)
            )
        }

        if isStriped {
            return SemanticTokens.adaptiveColor(
                light: NSColor.black.withAlphaComponent(0.015),
                dark: NSColor.white.withAlphaComponent(0.03)
            )
        }

        return .clear
    }
}

enum ParsedMemoryMarkdown {
    struct Section: Identifiable {
        let id: String
        let title: String?
        let blocks: [Block]
    }

    struct Table {
        let header: [String]
        let alignments: [TableColumnAlignment]
        let rows: [[String]]

        var columnCount: Int {
            header.count
        }

        func alignment(at index: Int) -> TableColumnAlignment {
            guard alignments.indices.contains(index) else {
                return .leading
            }
            return alignments[index]
        }
    }

    enum TableColumnAlignment {
        case leading
        case center
        case trailing

        var frameAlignment: Alignment {
            switch self {
            case .leading:
                return .leading
            case .center:
                return .center
            case .trailing:
                return .trailing
            }
        }

        var textAlignment: TextAlignment {
            switch self {
            case .leading:
                return .leading
            case .center:
                return .center
            case .trailing:
                return .trailing
            }
        }
    }

    enum Block {
        case paragraph(String)
        case bullets([String])
        case codeBlock(language: String?, code: String)
        case table(Table)
        case numberedList([String])
        case nestedBullets([(indent: Int, text: String)])
    }

    private final class ParsedSectionsBox: NSObject {
        let sections: [Section]

        init(sections: [Section]) {
            self.sections = sections
        }
    }

    private static let parseCache: NSCache<NSString, ParsedSectionsBox> = {
        let cache = NSCache<NSString, ParsedSectionsBox>()
        cache.countLimit = 64
        return cache
    }()

    static func parse(_ markdown: String) -> [Section] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let cacheKey = normalized as NSString
        if let cached = parseCache.object(forKey: cacheKey) {
            return cached.sections
        }

        let lines = normalized.components(separatedBy: .newlines)

        var sections: [(title: String?, lines: [String])] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flushCurrentSection() {
            let trimmed = trimTrailingBlankLines(currentLines)
            guard currentTitle != nil || !trimmed.isEmpty else {
                return
            }
            sections.append((title: currentTitle, lines: trimmed))
        }

        for line in lines {
            if line.hasPrefix("## ") {
                flushCurrentSection()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }

        flushCurrentSection()
        let parsedSections = sections.enumerated().map { index, section in
            Section(
                id: stableSectionID(index: index, title: section.title, lines: section.lines),
                title: section.title,
                blocks: parseBlocks(section.lines)
            )
        }
        parseCache.setObject(ParsedSectionsBox(sections: parsedSections), forKey: cacheKey)
        return parsedSections
    }

    private static func stableSectionID(index: Int, title: String?, lines: [String]) -> String {
        let rawIdentity = "\(title ?? "")\u{1F}\(lines.joined(separator: "\n"))"
        return "\(index)-\(stableHash(rawIdentity))"
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func parseBlocks(_ lines: [String]) -> [Block] {
        var blocks: [Block] = []
        var currentParagraph: [String] = []
        var currentBullets: [String] = []
        var currentNumbered: [String] = []
        var currentNestedBullets: [(indent: Int, text: String)] = []

        func flushParagraph() {
            let text = currentParagraph
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            currentParagraph.removeAll()
        }

        func flushBullets() {
            let items = currentBullets
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !items.isEmpty {
                blocks.append(.bullets(items))
            }
            currentBullets.removeAll()
        }

        func flushNumbered() {
            let items = currentNumbered
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !items.isEmpty {
                blocks.append(.numberedList(items))
            }
            currentNumbered.removeAll()
        }

        func flushNestedBullets() {
            if !currentNestedBullets.isEmpty {
                blocks.append(.nestedBullets(currentNestedBullets))
            }
            currentNestedBullets.removeAll()
        }

        func flushAll() {
            flushParagraph()
            flushBullets()
            flushNumbered()
            flushNestedBullets()
        }

        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                flushAll()
                let language: String? = {
                    let tag = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    return tag.isEmpty ? nil : tag
                }()
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                let code = codeLines.joined(separator: "\n")
                blocks.append(.codeBlock(language: language, code: code))
                continue
            }

            if let (table, nextIndex) = parseTable(lines, startingAt: index) {
                flushAll()
                blocks.append(.table(table))
                index = nextIndex
                continue
            }

            if line.isEmpty {
                flushAll()
                index += 1
                continue
            }

            let leadingSpaces = rawLine.prefix(while: { $0 == " " }).count
            if leadingSpaces > 0 && line.hasPrefix("- ") {
                flushParagraph()
                flushBullets()
                flushNumbered()
                let indentLevel = leadingSpaces / 2
                let text = String(line.dropFirst(2))
                currentNestedBullets.append((indent: indentLevel, text: text))
                index += 1
                continue
            }

            let numberedPattern = "^[0-9]+\\. "
            if let _ = line.range(of: numberedPattern, options: .regularExpression) {
                flushParagraph()
                flushBullets()
                flushNestedBullets()
                if let dotRange = line.range(of: ". ") {
                    let text = String(line[dotRange.upperBound...])
                    currentNumbered.append(text)
                }
                index += 1
                continue
            }

            if line.hasPrefix("- ") {
                flushParagraph()
                flushNumbered()
                flushNestedBullets()
                currentBullets.append(String(line.dropFirst(2)))
                index += 1
                continue
            }

            if !currentBullets.isEmpty { flushBullets() }
            if !currentNumbered.isEmpty { flushNumbered() }
            if !currentNestedBullets.isEmpty { flushNestedBullets() }
            currentParagraph.append(line)
            index += 1
        }

        flushAll()
        return blocks
    }

    private static func parseTable(_ lines: [String], startingAt startIndex: Int) -> (Table, Int)? {
        guard startIndex + 1 < lines.count else {
            return nil
        }

        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let delimiterLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)

        let headerCells = splitTableRow(headerLine)
        let delimiterCells = splitTableRow(delimiterLine)

        guard !headerCells.isEmpty,
              !delimiterCells.isEmpty,
              isDelimiterRow(delimiterCells) else {
            return nil
        }

        let columnCount = max(headerCells.count, delimiterCells.count)
        let parsedRows = parseTableRows(lines, startingAt: startIndex + 2, columnCount: columnCount)
        let table = Table(
            header: normalizedCells(headerCells, to: columnCount),
            alignments: normalizedAlignments(parseDelimiterAlignments(delimiterCells), to: columnCount),
            rows: parsedRows.rows
        )
        return (table, parsedRows.nextIndex)
    }

    private static func parseTableRows(
        _ lines: [String],
        startingAt startIndex: Int,
        columnCount: Int
    ) -> (rows: [[String]], nextIndex: Int) {
        var rows: [[String]] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("- ") else {
                break
            }

            let cells = splitTableRow(line)
            guard !cells.isEmpty else {
                break
            }

            rows.append(normalizedCells(cells, to: columnCount))
            index += 1
        }

        return (rows, index)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        guard line.contains("|") else {
            return []
        }

        var working = line.trimmingCharacters(in: .whitespaces)
        if working.hasPrefix("|") {
            working.removeFirst()
        }
        if working.hasSuffix("|") {
            working.removeLast()
        }

        let characters = Array(working)
        var cells: [String] = []
        var current = ""
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\\",
               index + 1 < characters.count,
               characters[index + 1] == "|" {
                current.append("|")
                index += 2
                continue
            }

            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll()
            } else {
                current.append(character)
            }
            index += 1
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells.contains(where: { !$0.isEmpty }) ? cells : []
    }

    private static func isDelimiterRow(_ cells: [String]) -> Bool {
        cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                return false
            }

            let withoutColons = trimmed.replacingOccurrences(of: ":", with: "")
            return withoutColons.count >= 3 && withoutColons.allSatisfy { $0 == "-" }
        }
    }

    private static func parseDelimiterAlignments(_ cells: [String]) -> [TableColumnAlignment] {
        cells.map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let hasLeadingColon = trimmed.hasPrefix(":")
            let hasTrailingColon = trimmed.hasSuffix(":")

            if hasLeadingColon && hasTrailingColon {
                return .center
            }
            if hasTrailingColon {
                return .trailing
            }
            return .leading
        }
    }

    private static func normalizedCells(_ cells: [String], to count: Int) -> [String] {
        var normalized = cells
        if normalized.count < count {
            normalized.append(contentsOf: Array(repeating: "", count: count - normalized.count))
        } else if normalized.count > count {
            normalized = Array(normalized.prefix(count))
        }
        return normalized
    }

    private static func normalizedAlignments(_ alignments: [TableColumnAlignment], to count: Int) -> [TableColumnAlignment] {
        var normalized = alignments
        if normalized.count < count {
            normalized.append(contentsOf: Array(repeating: .leading, count: count - normalized.count))
        } else if normalized.count > count {
            normalized = Array(normalized.prefix(count))
        }
        return normalized
    }

    private static func trimTrailingBlankLines(_ lines: [String]) -> [String] {
        var trimmed = lines
        while let last = trimmed.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            trimmed.removeLast()
        }
        return trimmed
    }
}

private struct MemoryEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: MemoryPaneMetrics.emptyStateMaxWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MemoryTag: View {
    enum Density {
        case regular
        case compact
    }

    let text: String
    var density: Density = .regular

    var body: some View {
        PromptCueChip(
            fill: SemanticTokens.adaptiveColor(
                light: NSColor.black.withAlphaComponent(0.02),
                dark: NSColor.white.withAlphaComponent(0.04)
            ),
            border: MemoryPaneColors.separator.opacity(0.34),
            horizontalPadding: density == .compact ? MemoryPaneMetrics.tagCompactHorizontalInset : PrimitiveTokens.Space.xs,
            height: density == .compact ? MemoryPaneMetrics.tagCompactHeight : MemoryPaneMetrics.tagRegularHeight
        ) {
            Text(text)
                .font(MemoryPaneTypography.tag)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MemoryPlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var contentInsets: NSSize = NSSize(width: MemoryPaneMetrics.detailContentInset, height: 18)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.body)
        textView.textContainerInset = contentInsets
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: MemoryPlainTextEditor

        init(_ parent: MemoryPlainTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            if parent.text != textView.string {
                parent.text = textView.string
            }
        }
    }
}
