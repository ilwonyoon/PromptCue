import AppKit
import PromptCueCore
import SwiftUI

struct CaptureComposerView: View {
    @ObservedObject var model: AppModel
    let onSubmitSuccess: () -> Void

    init(model: AppModel, onSubmitSuccess: @escaping () -> Void = {}) {
        self.model = model
        self.onSubmitSuccess = onSubmitSuccess
    }

    var body: some View {
        SearchFieldSurface {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                if shouldShowScreenshotSlot {
                    screenshotPreview
                }

                cueEditor
            }
        }
        .frame(width: PanelMetrics.captureSurfaceWidth, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, PrimitiveTokens.Space.xl)
        .padding(.top, PrimitiveTokens.Space.xl)
        .padding(.bottom, PrimitiveTokens.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            model.refreshPendingScreenshot()
        }
        .onExitCommand {
            closePanel()
        }
    }

    private var recentScreenshotPreviewURL: URL? {
        model.recentScreenshotPreviewURL
    }

    private var shouldShowScreenshotSlot: Bool {
        model.showsRecentScreenshotSlot
    }

    private var shouldShowScreenshotPlaceholder: Bool {
        model.showsRecentScreenshotPlaceholder
    }

    @ViewBuilder
    private var cueEditor: some View {
        let editorVisibleHeight = max(
            CaptureRuntimeMetrics.editorMinimumVisibleHeight,
            model.draftEditorMetrics.visibleHeight
        )

        CueTextEditor(
            text: $model.draftText,
            placeholder: "Type and press Enter to save",
            maxContentHeight: CaptureRuntimeMetrics.editorMaxHeight,
            onMetricsChange: { metrics in
                model.updateDraftEditorMetrics(metrics)
            },
            onSubmit: {
                model.beginCaptureSubmission {
                    onSubmitSuccess()
                }
            },
            onCancel: closePanel
        )
        .frame(
            maxWidth: .infinity,
            minHeight: editorVisibleHeight,
            maxHeight: editorVisibleHeight,
            alignment: .topLeading
        )
    }

    private var screenshotPreview: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                screenshotPlaceholder

                if let recentScreenshotPreviewURL {
                    LocalImageThumbnail(
                        url: recentScreenshotPreviewURL,
                        width: PrimitiveTokens.Size.captureAttachmentPreviewSize,
                        height: PrimitiveTokens.Size.captureAttachmentPreviewSize
                    )
                    .accessibilityLabel("Screenshot preview")
                    .transition(.opacity)
                }

                if model.isSubmittingCapture {
                    screenshotPlaceholder
                        .opacity(1)
                }
            }
            .frame(
                width: PrimitiveTokens.Size.captureAttachmentPreviewSize,
                height: PrimitiveTokens.Size.captureAttachmentPreviewSize
            )
            .animation(.easeOut(duration: 0.16), value: model.recentScreenshotState)

            Button(action: clearRecentScreenshot) {
                Image(systemName: "xmark.circle.fill")
                    .font(PrimitiveTokens.Typography.accessoryIcon)
                    .foregroundStyle(SemanticTokens.Text.primary)
                    .promptCueFloatingControlShadow()
            }
            .buttonStyle(.plain)
            .help("Remove recent screenshot")
            .accessibilityLabel("Remove recent screenshot")
            .padding(.top, PrimitiveTokens.Space.xs)
            .padding(.trailing, PrimitiveTokens.Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clearRecentScreenshot() {
        model.dismissPendingScreenshot()
    }

    private var screenshotPlaceholder: some View {
        RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
            .fill(SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.faint))
            .opacity(shouldShowScreenshotPlaceholder ? 1 : 0)
            .overlay {
                if shouldShowScreenshotPlaceholder {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading screenshot")
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                    .stroke(SemanticTokens.Border.subtle)
            }
    }

    private func closePanel() {
        model.clearDraft()
        NSApp.keyWindow?.cancelOperation(nil)
    }
}
