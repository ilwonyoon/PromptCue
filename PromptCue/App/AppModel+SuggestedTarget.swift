import Foundation
import PromptCueCore

extension AppModel {
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

    var focusedCaptureSuggestedTarget: CaptureSuggestedTarget? {
        let choices = captureSuggestedTargetChoices
        guard !choices.isEmpty else {
            return nil
        }

        let clampedIndex = max(0, min(selectedCaptureSuggestedTargetIndex, choices.count - 1))
        return choices[clampedIndex].target
    }

    var isAutomaticCaptureSuggestedTargetFocused: Bool {
        let choices = captureSuggestedTargetChoices
        guard !choices.isEmpty else {
            return false
        }

        let clampedIndex = max(0, min(selectedCaptureSuggestedTargetIndex, choices.count - 1))
        return choices[clampedIndex].isAutomatic
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
        if !isShowingCaptureSuggestedTargetChooser {
            refreshAvailableSuggestedTargets()
            syncCaptureSuggestedTargetSelection()
        }

        isShowingCaptureSuggestedTargetChooser.toggle()
    }

    func hideCaptureSuggestedTargetChooser() {
        isShowingCaptureSuggestedTargetChooser = false
    }

    @discardableResult
    func moveCaptureSuggestedTargetSelection(by offset: Int) -> Bool {
        let choices = captureSuggestedTargetChoices
        guard isShowingCaptureSuggestedTargetChooser, !choices.isEmpty else {
            return false
        }

        let count = choices.count
        let current = max(0, min(selectedCaptureSuggestedTargetIndex, count - 1))
        selectedCaptureSuggestedTargetIndex = (current + offset + count) % count
        return true
    }

    @discardableResult
    func highlightCaptureSuggestedTarget(_ target: CaptureSuggestedTarget) -> Bool {
        guard isShowingCaptureSuggestedTargetChooser else {
            return false
        }

        let choices = captureSuggestedTargetChoices
        guard let matchingIndex = choices.firstIndex(where: { !$0.isAutomatic && $0.target == target }) else {
            return false
        }

        selectedCaptureSuggestedTargetIndex = matchingIndex
        return true
    }

    @discardableResult
    func highlightAutomaticCaptureSuggestedTarget() -> Bool {
        guard isShowingCaptureSuggestedTargetChooser else {
            return false
        }

        let choices = captureSuggestedTargetChoices
        guard let matchingIndex = choices.firstIndex(where: \.isAutomatic) else {
            return false
        }

        selectedCaptureSuggestedTargetIndex = matchingIndex
        return true
    }

    @discardableResult
    func completeCaptureSuggestedTargetSelection() -> Bool {
        let choices = captureSuggestedTargetChoices
        guard isShowingCaptureSuggestedTargetChooser, !choices.isEmpty else {
            return false
        }

        let selectedIndex = max(0, min(selectedCaptureSuggestedTargetIndex, choices.count - 1))
        switch choices[selectedIndex] {
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
            return
        }

        if draftSuggestedTargetOverride == nil,
           automaticSuggestedTarget != nil {
            selectedCaptureSuggestedTargetIndex = 0
            return
        }

        if let draftSuggestedTargetOverride,
           let matchingIndex = choices.firstIndex(where: { choice in
               !choice.isAutomatic
                   && choice.target.canonicalIdentityKey == draftSuggestedTargetOverride.canonicalIdentityKey
           }) {
            selectedCaptureSuggestedTargetIndex = matchingIndex
            return
        }

        selectedCaptureSuggestedTargetIndex = min(selectedCaptureSuggestedTargetIndex, choices.count - 1)
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
}
