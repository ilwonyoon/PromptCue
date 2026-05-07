import SwiftUI

struct OnboardingMentalModelCard: View {
    let headline: String
    let summary: String
    let bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
            Text(headline)
                .font(OnboardingStyle.Typography.largeTitle)
                .foregroundStyle(SemanticTokens.Text.primary)

            Text(summary)
                .font(OnboardingStyle.Typography.subheadline)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundStyle(SemanticTokens.Text.secondary)
                        Text(bullet)
                            .font(OnboardingStyle.Typography.footnote)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PrimitiveTokens.Space.md)
        .background(
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                .fill(SemanticTokens.Surface.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                .stroke(SemanticTokens.Border.notificationCard, lineWidth: 1)
        )
    }
}
