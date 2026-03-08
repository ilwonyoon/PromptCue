import AppKit
import PromptCueCore
import SwiftUI

struct CaptureComposerView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SearchFieldSurface {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                if let recentScreenshotAttachment {
                    screenshotPreview(for: recentScreenshotAttachment)
                }

                cueEditor
            }
        }
        .frame(width: AppUIConstants.captureSurfaceWidth, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(PrimitiveTokens.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            model.refreshPendingScreenshot()
        }
        .onExitCommand {
            closePanel()
        }
    }

    private var trimmedDraft: String {
        model.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentScreenshotAttachment: ScreenshotAttachment? {
        model.pendingScreenshotAttachment
    }

    private var cueEditor: some View {
        CueTextEditor(
            text: $model.draftText,
            onHeightChange: { height in
                if abs(model.draftEditorContentHeight - height) > 0.5 {
                    model.draftEditorContentHeight = height
                }
            },
            onSubmit: {
                _ = model.submitCapture()
            },
            onCancel: closePanel
        )
        .frame(
            maxWidth: .infinity,
            minHeight: max(AppUIConstants.captureTextLineHeight, model.draftEditorContentHeight),
            alignment: .topLeading
        )
        .overlay(alignment: .topLeading) {
            if trimmedDraft.isEmpty {
                Text("Type and press Enter to save")
                    .font(PrimitiveTokens.Typography.captureInput)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .opacity(PrimitiveTokens.Opacity.soft)
                    .allowsHitTesting(false)
            }
        }
    }

    private func screenshotPreview(for attachment: ScreenshotAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            LocalImageThumbnail(
                url: URL(fileURLWithPath: attachment.path),
                height: PrimitiveTokens.Size.captureAttachmentPreviewSize
            )
            .frame(
                width: PrimitiveTokens.Size.captureAttachmentPreviewSize,
                height: PrimitiveTokens.Size.captureAttachmentPreviewSize
            )

            Button(action: clearRecentScreenshot) {
                Image(systemName: "xmark.circle.fill")
                    .font(PrimitiveTokens.Typography.accessoryIcon)
                    .foregroundStyle(SemanticTokens.Text.primary)
                    .promptCueFloatingControlShadow()
            }
            .buttonStyle(.plain)
            .help("Remove recent screenshot")
            .accessibilityLabel("Remove recent screenshot")
            .padding(PrimitiveTokens.Space.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clearRecentScreenshot() {
        model.dismissPendingScreenshot()
    }

    private func closePanel() {
        model.clearDraft()
        NSApp.keyWindow?.cancelOperation(nil)
    }
}
