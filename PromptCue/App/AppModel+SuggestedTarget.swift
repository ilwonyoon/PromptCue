import Foundation
import PromptCueCore

extension AppModel {
    private var automaticCaptureSuggestedTargetChoiceID: String {
        "__automatic__"
    }

    var automaticSuggestedTarget: CaptureSuggestedTarget? {
        guard hasStartedSuggestedTargetProvider else {
            return nil
        }

        return suggestedTargetProvider.currentFreshSuggestedTarget(
            relativeTo: Date(),
            freshness: AppUIConstants.suggestedTargetFreshness
        )
    }

    var effectiveCaptureSuggestedTarget: CaptureSuggestedTarget? {
        draftSuggestedTargetOverride ?? automaticSuggestedTarget
    }

    var isCaptureSuggestedTargetAutomatic: Bool {
        draftSuggestedTargetOverride == nil
    }

    var canChooseSuggestedTarget: Bool {
        effectiveCaptureSuggestedTarget != nil || !availableSuggestedTargets.isEmpty
    }

    var captureChooserTarget: CaptureSuggestedTarget? {
        effectiveCaptureSuggestedTarget ?? availableSuggestedTargets.first
    }

    var captureSuggestedTargetChoiceCount: Int {
        captureSuggestedTargetChoices.count
    }

    var committedCaptureSuggestedTargetChoiceID: String? {
        committedCaptureSuggestedTargetChoice(in: captureSuggestedTargetChoices).map(choiceID(for:))
    }

    var focusedCaptureSuggestedTarget: CaptureSuggestedTarget? {
        focusedCaptureSuggestedTargetChoice(in: captureSuggestedTargetChoices)?.target
    }

    var isAutomaticCaptureSuggestedTargetFocused: Bool {
        focusedCaptureSuggestedTargetChoice(in: captureSuggestedTargetChoices)?.isAutomatic ?? false
    }

    var highlightedCaptureSuggestedTarget: CaptureSuggestedTarget? {
        focusedCaptureSuggestedTarget
    }

    var isAutomaticCaptureSuggestedTargetHighlighted: Bool {
        isAutomaticCaptureSuggestedTargetFocused
    }

    func beginStackSuggestedTargetPresentation() {
        isStackSuggestedTargetPresentationActive = true
        refreshSuggestedTargetProviderLifecycle()
    }

    func endStackSuggestedTargetPresentation() {
        isStackSuggestedTargetPresentationActive = false
        refreshSuggestedTargetProviderLifecycle()
    }

    func refreshAvailableSuggestedTargets() {
        ensureSuggestedTargetProviderStarted()
        suggestedTargetProvider.refreshAvailableSuggestedTargets()
        syncAvailableSuggestedTargets()
    }

    func chooseDraftSuggestedTarget(_ target: CaptureSuggestedTarget) {
        draftSuggestedTargetOverride = target
        isShowingCaptureSuggestedTargetChooser = false
        syncCaptureSuggestedTargetSelection()
    }

    func clearDraftSuggestedTargetOverride() {
        draftSuggestedTargetOverride = nil
        isShowingCaptureSuggestedTargetChooser = false
        syncCaptureSuggestedTargetSelection()
    }

    func toggleCaptureSuggestedTargetChooser() {
        if isShowingCaptureSuggestedTargetChooser {
            isShowingCaptureSuggestedTargetChooser = false
            syncCaptureSuggestedTargetSelection()
            return
        }

        refreshAvailableSuggestedTargets()
        syncCaptureSuggestedTargetSelection()
        isShowingCaptureSuggestedTargetChooser = true
    }

    func hideCaptureSuggestedTargetChooser() {
        isShowingCaptureSuggestedTargetChooser = false
        syncCaptureSuggestedTargetSelection()
    }

    @discardableResult
    func moveCaptureSuggestedTargetSelection(by offset: Int) -> Bool {
        let choices = captureSuggestedTargetChoices
        guard isShowingCaptureSuggestedTargetChooser, !choices.isEmpty else {
            return false
        }

        let choiceIDs = choices.map(choiceID(for:))
        let currentChoiceID = resolvedFocusedCaptureSuggestedTargetChoiceID(in: choices) ?? choiceIDs[0]
        let currentIndex = choiceIDs.firstIndex(of: currentChoiceID) ?? 0
        let nextIndex = (currentIndex + offset + choiceIDs.count) % choiceIDs.count
        applyFocusedCaptureSuggestedTargetChoiceID(choiceIDs[nextIndex], in: choices)
        return true
    }

    @discardableResult
    func highlightCaptureSuggestedTarget(_ target: CaptureSuggestedTarget) -> Bool {
        guard isShowingCaptureSuggestedTargetChooser else {
            return false
        }

        let choices = captureSuggestedTargetChoices
        guard let matchingChoice = choices.first(where: { !$0.isAutomatic && $0.target == target }) else {
            return false
        }

        applyFocusedCaptureSuggestedTargetChoiceID(choiceID(for: matchingChoice), in: choices)
        return true
    }

    @discardableResult
    func highlightAutomaticCaptureSuggestedTarget() -> Bool {
        guard isShowingCaptureSuggestedTargetChooser else {
            return false
        }

        let choices = captureSuggestedTargetChoices
        guard choices.contains(where: \.isAutomatic) else {
            return false
        }

        applyFocusedCaptureSuggestedTargetChoiceID(automaticCaptureSuggestedTargetChoiceID, in: choices)
        return true
    }

    @discardableResult
    func completeCaptureSuggestedTargetSelection() -> Bool {
        let choices = captureSuggestedTargetChoices
        guard isShowingCaptureSuggestedTargetChooser, !choices.isEmpty else {
            return false
        }

        guard let focusedChoice = focusedCaptureSuggestedTargetChoice(in: choices) else {
            return false
        }

        switch focusedChoice {
        case .automatic:
            clearDraftSuggestedTargetOverride()
        case .explicit(let target):
            chooseDraftSuggestedTarget(target)
        }

        return true
    }

    @discardableResult
    func cancelCaptureSuggestedTargetSelection() -> Bool {
        guard isShowingCaptureSuggestedTargetChooser else {
            return false
        }

        hideCaptureSuggestedTargetChooser()
        return true
    }

    func syncAvailableSuggestedTargets() {
        availableSuggestedTargets = suggestedTargetProvider.availableSuggestedTargets()
        syncCaptureSuggestedTargetSelection()
    }

    func syncCaptureSuggestedTargetSelection() {
        let choices = captureSuggestedTargetChoices
        guard !choices.isEmpty else {
            selectedCaptureSuggestedTargetIndex = 0
            focusedCaptureSuggestedTargetChoiceID = nil
            return
        }

        let committedChoiceID = committedCaptureSuggestedTargetChoice(in: choices).map(choiceID(for:))
        let preferredFocusedChoiceID: String?
        if isShowingCaptureSuggestedTargetChooser,
           let existingFocusedChoiceID = resolvedFocusedCaptureSuggestedTargetChoiceID(in: choices) {
            preferredFocusedChoiceID = existingFocusedChoiceID
        } else {
            preferredFocusedChoiceID = committedChoiceID
        }

        applyFocusedCaptureSuggestedTargetChoiceID(preferredFocusedChoiceID, in: choices)
    }

    private var captureSuggestedTargetChoices: [CaptureSuggestedTargetChoice] {
        var choices: [CaptureSuggestedTargetChoice] = []

        if let automaticSuggestedTarget {
            choices.append(.automatic(automaticSuggestedTarget))
        }

        let filteredTargets: [CaptureSuggestedTarget]
        if let automaticSuggestedTarget {
            filteredTargets = availableSuggestedTargets.filter {
                $0.canonicalIdentityKey != automaticSuggestedTarget.canonicalIdentityKey
            }
        } else {
            filteredTargets = availableSuggestedTargets
        }

        let deduplicatedTargets = filteredTargets.reduce(into: [CaptureSuggestedTarget]()) { result, target in
            if result.contains(where: { $0.canonicalIdentityKey == target.canonicalIdentityKey }) == false {
                result.append(target)
            }
        }

        choices.append(contentsOf: deduplicatedTargets.map(CaptureSuggestedTargetChoice.explicit))
        return choices
    }

    private func committedCaptureSuggestedTargetChoice(
        in choices: [CaptureSuggestedTargetChoice]
    ) -> CaptureSuggestedTargetChoice? {
        guard !choices.isEmpty else {
            return nil
        }

        if draftSuggestedTargetOverride == nil,
           let automaticChoice = choices.first(where: \.isAutomatic) {
            return automaticChoice
        }

        if let draftSuggestedTargetOverride,
           let explicitChoice = choices.first(where: { choice in
               !choice.isAutomatic
                   && choice.target.canonicalIdentityKey == draftSuggestedTargetOverride.canonicalIdentityKey
           }) {
            return explicitChoice
        }

        return choices.first
    }

    private func focusedCaptureSuggestedTargetChoice(
        in choices: [CaptureSuggestedTargetChoice]
    ) -> CaptureSuggestedTargetChoice? {
        guard let resolvedChoiceID = resolvedFocusedCaptureSuggestedTargetChoiceID(in: choices) else {
            return nil
        }

        return choices.first(where: { choiceID(for: $0) == resolvedChoiceID })
    }

    private func resolvedFocusedCaptureSuggestedTargetChoiceID(
        in choices: [CaptureSuggestedTargetChoice]
    ) -> String? {
        if let focusedCaptureSuggestedTargetChoiceID,
           choices.contains(where: { choiceID(for: $0) == focusedCaptureSuggestedTargetChoiceID }) {
            return focusedCaptureSuggestedTargetChoiceID
        }

        return committedCaptureSuggestedTargetChoice(in: choices).map(choiceID(for:))
    }

    private func applyFocusedCaptureSuggestedTargetChoiceID(
        _ choiceID: String?,
        in choices: [CaptureSuggestedTargetChoice]
    ) {
        guard let choiceID,
              let matchingIndex = choices.firstIndex(where: { self.choiceID(for: $0) == choiceID }) else {
            focusedCaptureSuggestedTargetChoiceID = nil
            selectedCaptureSuggestedTargetIndex = 0
            return
        }

        focusedCaptureSuggestedTargetChoiceID = choiceID
        selectedCaptureSuggestedTargetIndex = matchingIndex
    }

    private func choiceID(for choice: CaptureSuggestedTargetChoice) -> String {
        if choice.isAutomatic {
            return automaticCaptureSuggestedTargetChoiceID
        }

        return choice.target.canonicalIdentityKey
    }
}
