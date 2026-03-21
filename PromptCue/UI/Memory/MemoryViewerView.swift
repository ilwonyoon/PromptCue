import AppKit
import SwiftUI
import PromptCueCore

struct MemoryViewerView: View {
    @ObservedObject var model: MemoryViewerModel
    @State private var isEditing = false
    @State private var editorText = ""
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 0) {
            MemoryColumnPane(
                backgroundColor: Self.notesSidebarBackground,
                showsTrailingBorder: true
            ) {
                MemoryProjectListPane(
                    projects: model.projects,
                    selectedProject: model.selectedProject,
                    documentCount: { model.summaries(for: $0).count },
                    onSelect: { model.selectedProject = $0 }
                )
            }
            .frame(minWidth: 190, idealWidth: 220, maxWidth: 240, maxHeight: .infinity)

            MemoryColumnPane(
                backgroundColor: Color(nsColor: .textBackgroundColor),
                showsTrailingBorder: true
            ) {
                if let selectedProject = model.selectedProject {
                    MemoryDocumentListPane(
                        summaries: model.summaries(for: selectedProject),
                        selectedDocumentKey: model.selectedDocumentKey,
                        onSelect: { model.selectedDocumentKey = $0 }
                    )
                } else {
                    MemoryEmptyState(
                        title: "No Project Selected",
                        message: "Choose a project to browse its durable documents."
                    )
                }
            }
            .frame(minWidth: 176, idealWidth: 196, maxWidth: 220, maxHeight: .infinity)

            MemoryColumnPane(
                backgroundColor: Color(nsColor: .textBackgroundColor),
                showsTrailingBorder: false
            ) {
                MemoryDetailPane(
                    document: model.selectedDocument,
                    isEditing: $isEditing,
                    editorText: $editorText,
                    didCopy: $didCopy,
                    onCopy: {
                        model.copySelectedDocument()
                        showCopiedFeedback()
                    },
                    onStartEditing: {
                        editorText = model.selectedDocument?.content ?? ""
                        isEditing = true
                    },
                    onCancelEditing: {
                        editorText = model.selectedDocument?.content ?? ""
                        isEditing = false
                    },
                    onSaveEditing: {
                        if model.saveSelectedDocumentContent(editorText) {
                            isEditing = false
                        }
                    }
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.refresh()
                    if !isEditing {
                        editorText = model.selectedDocument?.content ?? ""
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onChange(of: model.selectedDocument?.id) { _, _ in
            if !isEditing {
                editorText = model.selectedDocument?.content ?? ""
            }
            didCopy = false
        }
        .overlay(alignment: .bottomLeading) {
            if let storageErrorMessage = model.storageErrorMessage {
                Text(storageErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private func showCopiedFeedback() {
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopy = false
        }
    }

    private static var notesSidebarBackground: Color {
        SemanticTokens.adaptiveColor(
            light: NSColor(
                srgbRed: 225.0 / 255.0,
                green: 225.0 / 255.0,
                blue: 224.0 / 255.0,
                alpha: 1
            ),
            dark: NSColor(calibratedWhite: 0.16, alpha: 1)
        )
    }
}

private struct MemoryColumnPane<Content: View>: View {
    let backgroundColor: Color
    let showsTrailingBorder: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .overlay(alignment: .trailing) {
            if showsTrailingBorder {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.7))
                    .frame(width: 1)
            }
        }
    }
}

private struct MemoryProjectListPane: View {
    let projects: [String]
    let selectedProject: String?
    let documentCount: (String) -> Int
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SettingsTokens.Layout.sidebarItemSpacing) {
                ForEach(projects, id: \.self) { project in
                    MemorySelectableRowShell(
                        style: .sidebar,
                        isSelected: project == selectedProject,
                        action: { onSelect(project) }
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project)
                                .font(SettingsTokens.Typography.sidebarLabel)
                                .foregroundStyle(SemanticTokens.Text.primary)
                                .lineLimit(1)
                            Text("\(documentCount(project)) docs")
                                .font(.caption)
                                .foregroundStyle(SemanticTokens.Text.secondary)
                        }
                    }
                }
            }
            .padding(10)
        }
    }
}

private struct MemoryDocumentListPane: View {
    let summaries: [ProjectDocumentSummary]
    let selectedDocumentKey: ProjectDocumentKey?
    let onSelect: (ProjectDocumentKey) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SettingsTokens.Layout.sidebarItemSpacing) {
                ForEach(summaries) { summary in
                    MemorySelectableRowShell(
                        style: .content,
                        isSelected: summary.key == selectedDocumentKey,
                        action: { onSelect(summary.key) }
                    ) {
                        MemoryDocumentSummaryRow(summary: summary)
                    }
                }
            }
            .padding(10)
        }
    }
}

private struct MemorySelectableRowShell<Content: View>: View {
    enum Style {
        case sidebar
        case content
    }

    let style: Style
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(backgroundFill)
                .overlay(backgroundStroke)
                .contentShape(
                    RoundedRectangle(cornerRadius: PrimitiveTokens.Space.xs, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var backgroundFill: some View {
        RoundedRectangle(cornerRadius: PrimitiveTokens.Space.xs, style: .continuous)
            .fill(fillColor)
    }

    private var backgroundStroke: some View {
        RoundedRectangle(cornerRadius: PrimitiveTokens.Space.xs, style: .continuous)
            .stroke(borderColor, lineWidth: PrimitiveTokens.Stroke.subtle)
    }

    private var fillColor: Color {
        switch style {
        case .sidebar:
            if isSelected {
                return SemanticTokens.adaptiveColor(
                    light: NSColor.black.withAlphaComponent(0.07),
                    dark: NSColor.white.withAlphaComponent(0.08)
                )
            }
            if isHovered {
                return SemanticTokens.adaptiveColor(
                    light: NSColor.black.withAlphaComponent(0.04),
                    dark: NSColor.white.withAlphaComponent(0.05)
                )
            }
            return .clear

        case .content:
            if isSelected {
                return SemanticTokens.adaptiveColor(
                    light: NSColor.black.withAlphaComponent(0.05),
                    dark: NSColor.white.withAlphaComponent(0.08)
                )
            }
            if isHovered {
                return SemanticTokens.adaptiveColor(
                    light: NSColor.black.withAlphaComponent(0.03),
                    dark: NSColor.white.withAlphaComponent(0.05)
                )
            }
            return .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .sidebar:
            if isSelected {
                return Color(nsColor: .separatorColor).opacity(0.42)
            }
            if isHovered {
                return Color(nsColor: .separatorColor).opacity(0.24)
            }
            return .clear

        case .content:
            if isSelected {
                return Color(nsColor: .separatorColor).opacity(0.34)
            }
            if isHovered {
                return Color(nsColor: .separatorColor).opacity(0.20)
            }
            return .clear
        }
    }
}

private struct MemoryDocumentSummaryRow: View {
    let summary: ProjectDocumentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.topic)
                .font(SettingsTokens.Typography.sidebarLabel)
                .lineLimit(1)
                .foregroundStyle(SemanticTokens.Text.primary)

            HStack(spacing: 8) {
                MemoryTag(text: summary.documentType.rawValue)
                Text(Self.relativeDateString(for: summary.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private static func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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

    var body: some View {
        if let document {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(document.project)
                                .font(.title2.weight(.semibold))
                            MemoryTag(text: document.documentType.rawValue)
                        }

                        Text(Self.timestampString(for: document.updatedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if didCopy {
                            Text("Copied")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(SemanticTokens.Text.secondary)
                                .transition(.opacity)
                        }

                        StackRailControlButton(
                            systemName: didCopy ? "checkmark" : "doc.on.doc",
                            accessibilityLabel: didCopy ? "Copied document" : "Copy document",
                            glyphSize: 13,
                            controlSize: 24,
                            isActive: didCopy,
                            action: onCopy
                        )
                        if isEditing {
                            StackRailControlButton(
                                systemName: "xmark",
                                accessibilityLabel: "Cancel editing",
                                glyphSize: 13,
                                controlSize: 24,
                                action: onCancelEditing
                            )
                            StackRailControlButton(
                                systemName: "checkmark",
                                accessibilityLabel: "Save document",
                                glyphSize: 13,
                                controlSize: 24,
                                isActive: true,
                                action: onSaveEditing
                            )
                            .keyboardShortcut(.defaultAction)
                        } else {
                            StackRailControlButton(
                                systemName: "square.and.pencil",
                                accessibilityLabel: "Edit document",
                                glyphSize: 13,
                                controlSize: 24,
                                action: onStartEditing
                            )
                        }
                    }
                }

                Divider()
                    .padding(.top, 16)

                if isEditing {
                    MemoryPlainTextEditor(text: $editorText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 16)
                } else {
                    MemoryRenderedDocumentView(markdown: document.content)
                        .padding(.top, 16)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
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
}

private struct MemoryRenderedDocumentView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(ParsedMemoryMarkdown.parse(markdown)) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        if let title = section.title {
                            Text(title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(SemanticTokens.Text.primary)
                        }

                        ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                            switch block {
                            case .paragraph(let text):
                                MemoryInlineMarkdownText(markdown: text)
                                    .font(.body)
                                    .foregroundStyle(SemanticTokens.Text.primary)
                                    .fixedSize(horizontal: false, vertical: true)

                            case .bullets(let items):
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(items, id: \.self) { item in
                                        HStack(alignment: .top, spacing: 10) {
                                            Circle()
                                                .fill(SemanticTokens.Text.secondary.opacity(0.7))
                                                .frame(width: 5, height: 5)
                                                .padding(.top, 7)

                                            MemoryInlineMarkdownText(markdown: item)
                                                .font(.body)
                                                .foregroundStyle(SemanticTokens.Text.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            case .codeBlock(let language, let code):
                                MemoryCodeBlockView(language: language, code: code)
                            case .table(let table):
                                MemoryMarkdownTableView(table: table)
                            case .numberedList(let items):
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("\(idx + 1).")
                                                .font(.body.monospacedDigit())
                                                .foregroundStyle(SemanticTokens.Text.secondary)
                                                .frame(minWidth: 24, alignment: .trailing)

                                            MemoryInlineMarkdownText(markdown: item)
                                                .font(.body)
                                                .foregroundStyle(SemanticTokens.Text.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            case .nestedBullets(let items):
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle()
                                                .fill(SemanticTokens.Text.secondary.opacity(
                                                    item.indent == 0 ? 0.7 : 0.45
                                                ))
                                                .frame(width: 4, height: 4)
                                                .padding(.top, 7)

                                            MemoryInlineMarkdownText(markdown: item.text)
                                                .font(.body)
                                                .foregroundStyle(SemanticTokens.Text.primary)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
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
                    .font(.system(size: PrimitiveTokens.FontSize.micro, weight: .medium))
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.automatic)
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
            .frame(minWidth: 120, maxWidth: .infinity, alignment: alignment.frameAlignment)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(backgroundFill)
            .overlay(alignment: .trailing) {
                if showsTrailingDivider {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.55))
                        .frame(width: 1)
                }
            }
            .overlay(alignment: .bottom) {
                if showsBottomDivider {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.55))
                        .frame(height: 1)
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
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MemoryTag: View {
    let text: String

    var body: some View {
        PromptCueChip(
            fill: SemanticTokens.Surface.raisedFill,
            border: SemanticTokens.Border.subtle,
            horizontalPadding: PrimitiveTokens.Space.xs + 1,
            height: 24
        ) {
            Text(text)
                .font(.system(size: PrimitiveTokens.FontSize.micro, weight: .medium))
                .foregroundStyle(SemanticTokens.Text.secondary)
        }
    }
}

private struct MemoryPlainTextEditor: NSViewRepresentable {
    @Binding var text: String

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
        textView.textContainerInset = NSSize(width: 2, height: 2)
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
