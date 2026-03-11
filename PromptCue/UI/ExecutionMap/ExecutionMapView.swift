import PromptCueCore
import SwiftUI

struct ExecutionMapView: View {
    @ObservedObject var model: ExecutionMapModel

    var body: some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.lg) {
            PanelHeader(
                title: "Execution Map",
                subtitle: subtitle
            )

            if let lastErrorDescription = model.lastErrorDescription {
                feedbackCard(message: lastErrorDescription)
            }

            if model.sections.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PrimitiveTokens.Space.xl) {
                        ForEach(model.sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.bottom, PrimitiveTokens.Space.xs)
                }
                .scrollIndicators(.visible)
            }
        }
        .padding(PrimitiveTokens.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SemanticTokens.Surface.previewBackdropBottom)
    }

    private var subtitle: String {
        let totalWorkItems = model.sections.reduce(0) { $0 + $1.workItemCount }
        let repoCount = model.sections.count

        guard totalWorkItems > 0 else {
            return "Read-only work items grouped by repo and status."
        }

        return "\(totalWorkItems) work items across \(repoCount) repo groups. Read-only for now."
    }

    private var emptyState: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                Text("No work items yet")
                    .font(PrimitiveTokens.Typography.bodyStrong)
                    .foregroundStyle(SemanticTokens.Text.primary)

                Text("Create items from selected Stack cues. Execution handoff lands in a later slice.")
                    .font(PrimitiveTokens.Typography.body)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func feedbackCard(message: String) -> some View {
        CardSurface {
            Text(message)
                .font(PrimitiveTokens.Typography.body)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionView(_ section: ExecutionMapSection) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
            HStack(alignment: .center, spacing: PrimitiveTokens.Space.sm) {
                Text(section.title)
                    .font(PrimitiveTokens.Typography.bodyStrong)
                    .foregroundStyle(SemanticTokens.Text.primary)

                PromptCueChip {
                    Text("\(section.workItemCount)")
                        .font(PrimitiveTokens.Typography.chip)
                        .foregroundStyle(SemanticTokens.Text.primary)
                }

                Spacer(minLength: PrimitiveTokens.Space.sm)
            }

            HStack(alignment: .top, spacing: PrimitiveTokens.Space.md) {
                ForEach(section.lanes) { lane in
                    laneView(lane)
                }
            }
        }
    }

    private func laneView(_ lane: ExecutionMapLane) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
            HStack(alignment: .center, spacing: PrimitiveTokens.Space.xs) {
                Text(lane.status.executionMapTitle)
                    .font(PrimitiveTokens.Typography.metaStrong)
                    .foregroundStyle(lane.status.executionMapTitleColor)

                Spacer(minLength: PrimitiveTokens.Space.xs)

                PromptCueChip(
                    fill: SemanticTokens.Surface.raisedFill,
                    border: SemanticTokens.Border.subtle
                ) {
                    Text("\(lane.items.count)")
                        .font(PrimitiveTokens.Typography.chip)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                }
            }

            if lane.items.isEmpty {
                CardSurface {
                    Text("No items")
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                    ForEach(lane.items) { workItem in
                        workItemCard(workItem)
                    }
                }
            }
        }
        .padding(PrimitiveTokens.Space.md)
        .frame(maxWidth: .infinity, minHeight: 1, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                .fill(SemanticTokens.Surface.raisedFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                .stroke(SemanticTokens.Border.subtle, lineWidth: PrimitiveTokens.Stroke.subtle)
        }
    }

    private func workItemCard(_ workItem: WorkItem) -> some View {
        CardSurface {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                Text(workItem.title)
                    .font(PrimitiveTokens.Typography.bodyStrong)
                    .foregroundStyle(SemanticTokens.Text.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let summary = workItem.summary {
                    Text(summary)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .center, spacing: PrimitiveTokens.Space.xs) {
                    if let branchName = workItem.branchName {
                        metadataChip(branchName)
                    }

                    metadataChip(sourceCountLabel(for: workItem.sourceNoteCount))

                    if workItem.createdBy == .mcpAI {
                        metadataChip("AI")
                    }

                    if let difficultyHint = workItem.difficultyHint {
                        metadataChip(difficultyHint.executionMapLabel)
                    }

                    Spacer(minLength: PrimitiveTokens.Space.xs)
                }

                Text("Updated \(RelativeTimeFormatter.string(for: workItem.updatedAt))")
                    .font(PrimitiveTokens.Typography.meta)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func metadataChip(_ text: String) -> some View {
        PromptCueChip(
            fill: SemanticTokens.Surface.raisedFill,
            border: SemanticTokens.Border.subtle
        ) {
            Text(text)
                .font(PrimitiveTokens.Typography.chip)
                .foregroundStyle(SemanticTokens.Text.secondary)
        }
    }

    private func sourceCountLabel(for sourceCount: Int) -> String {
        sourceCount == 1 ? "1 source" : "\(sourceCount) sources"
    }
}

private extension WorkItemStatus {
    var executionMapTitle: String {
        switch self {
        case .open:
            return "Open"
        case .inProgress:
            return "In Progress"
        case .done:
            return "Done"
        case .dismissed:
            return "Dismissed"
        }
    }

    var executionMapTitleColor: Color {
        switch self {
        case .open:
            return SemanticTokens.Text.primary
        case .inProgress:
            return SemanticTokens.Accent.primary
        case .done, .dismissed:
            return SemanticTokens.Text.secondary
        }
    }
}

private extension WorkItemDifficultyHint {
    var executionMapLabel: String {
        rawValue.capitalized
    }
}
