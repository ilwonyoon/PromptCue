import SwiftUI

struct OnboardingProgressDots: View {
    let totalSteps: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex
                          ? SemanticTokens.Text.primary
                          : SemanticTokens.Border.subtle)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("Step \(currentIndex + 1) of \(totalSteps)")
    }
}
