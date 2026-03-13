import Testing
@testable import PromptCueCore

struct StackRailStateTests {
    @Test
    func summaryUsesStageMetaphor() {
        let state = StackRailState(activeCount: 4, copiedCount: 2, stagedCount: 0)

        #expect(state.summaryLabel == "4 On Stage · 2 Off Stage")
        #expect(state.headerTitle == "On Stage 4 · Off Stage 2")
        #expect(state.headerCountLabel == "4 On Stage · 2 Off Stage")
    }

    @Test
    func feedbackUsesCopiedForImmediateAction() {
        let one = StackRailState(activeCount: 4, copiedCount: 2, stagedCount: 1)
        let many = StackRailState(activeCount: 4, copiedCount: 2, stagedCount: 3)

        #expect(one.actionFeedbackLabel == "1 Copied")
        #expect(many.actionFeedbackLabel == "3 Copied")
    }

    @Test
    func onStageFilterHidesOffstageCards() {
        let state = StackRailState(
            activeCount: 4,
            copiedCount: 2,
            stagedCount: 0,
            filter: .onStage
        )

        #expect(state.showsActiveCards)
        #expect(state.showsCopiedCards == false)
        #expect(state.forcesExpandedCopiedSection == false)
        #expect(state.headerTitle == "On Stage 4")
        #expect(state.headerCountLabel == "4")
    }

    @Test
    func offstageFilterShowsExpandedOffstageList() {
        let state = StackRailState(
            activeCount: 4,
            copiedCount: 2,
            stagedCount: 0,
            filter: .offstage
        )

        #expect(state.showsActiveCards == false)
        #expect(state.showsCopiedCards)
        #expect(state.forcesExpandedCopiedSection)
        #expect(state.headerTitle == "Off Stage 2")
        #expect(state.headerCountLabel == "2")
    }
}
