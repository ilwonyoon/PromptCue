import SwiftUI

struct OnboardingRootView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        Group {
            switch state.step {
            case .welcome:
                OnboardingWelcomeView(state: state)
            case .lanePicker:
                OnboardingLanePickerView(state: state)
            case .lane1PickMainAI:
                OnboardingPickMainAIView(state: state)
            case .lane1ConnectCode:
                OnboardingConnectCodeView(state: state)
            case .lane1ConnectDesktop:
                OnboardingConnectDesktopView(state: state)
            case .lane1ConnectChatGPT:
                OnboardingConnectChatGPTView(state: state)
            case .lane1FirstDoc:
                OnboardingFirstDocView(state: state)
            case .lane2Capture:
                OnboardingCaptureView(state: state)
            case .lane2Stack:
                OnboardingStackView(state: state)
            case .lane2FlowStory:
                OnboardingFlowStoryView(state: state)
            case .completed:
                OnboardingCompletedView()
            }
        }
        .frame(width: 540, height: 480)
        .background(OnboardingStyle.Surface.groupedBackground)
        .animation(.easeInOut(duration: 0.22), value: state.step)
    }
}

private struct OnboardingCompletedView: View {
    var body: some View {
        VStack(spacing: OnboardingStyle.Spacing.titleToBody) {
            Spacer()
            Text("You're set.")
                .font(OnboardingStyle.Typography.largeTitle)
                .foregroundStyle(SemanticTokens.Text.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
