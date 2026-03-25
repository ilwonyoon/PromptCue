import Foundation
import PromptCueCore

struct PromptExportTailState: Equatable {
    var isEnabled: Bool
    var suffixText: String

    var trimmedSuffixText: String {
        suffixText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasUsableSuffix: Bool {
        !trimmedSuffixText.isEmpty
    }

    var exportSuffix: ExportSuffix {
        guard isEnabled else {
            return .off
        }

        return ExportSuffix(trimmedSuffixText)
    }
}

enum PromptExportTailPreferences {
    private static let enabledKey = "promptExportTail.enabled"
    private static let textKey = "promptExportTail.text"

    static let defaultSuffixText = """
    Start by diagnosing the root cause, devise a solution, then execute and verify the result.
    """

    static func load(defaults: UserDefaults = .standard) -> PromptExportTailState {
        PromptExportTailState(
            isEnabled: defaults.bool(forKey: enabledKey),
            suffixText: defaults.string(forKey: textKey) ?? defaultSuffixText
        )
    }

    static func save(_ state: PromptExportTailState, defaults: UserDefaults = .standard) {
        defaults.set(state.isEnabled, forKey: enabledKey)
        defaults.set(state.suffixText, forKey: textKey)
    }

    static func reset(defaults: UserDefaults = .standard) -> PromptExportTailState {
        let state = PromptExportTailState(
            isEnabled: false,
            suffixText: defaultSuffixText
        )
        save(state, defaults: defaults)
        return state
    }
}

@MainActor
final class PromptExportTailSettingsModel: ObservableObject {
    @Published var isEnabled = false
    @Published var suffixText = PromptExportTailPreferences.defaultSuffixText

    init() {
        refresh()
    }

    var previewText: String {
        ExportFormatter.string(
            for: [
                CaptureCard(text: "root cause looks like async panel timing", createdAt: .now),
                CaptureCard(text: "verify with tests before changing layout again", createdAt: .now),
            ],
            suffix: currentState.exportSuffix
        )
    }

    var currentState: PromptExportTailState {
        PromptExportTailState(
            isEnabled: isEnabled,
            suffixText: suffixText
        )
    }

    func refresh() {
        let state = PromptExportTailPreferences.load()
        isEnabled = state.isEnabled
        suffixText = state.suffixText
    }

    func updateEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        persist()
    }

    func updateSuffixText(_ suffixText: String) {
        self.suffixText = suffixText
        persist()
    }

    func resetToDefault() {
        let state = PromptExportTailPreferences.reset()
        isEnabled = state.isEnabled
        suffixText = state.suffixText
    }

    private func persist() {
        PromptExportTailPreferences.save(currentState)
    }
}
