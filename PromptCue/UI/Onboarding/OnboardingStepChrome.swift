import SwiftUI

struct OnboardingStepChrome<Content: View, Footer: View>: View {
    let progress: (current: Int, total: Int)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    init(
        progress: (current: Int, total: Int)? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.progress = progress
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, OnboardingStyle.Spacing.edgePadding)
                .padding(.top, OnboardingStyle.Spacing.sectionBlock)

            VStack(spacing: PrimitiveTokens.Space.sm) {
                if let progress {
                    OnboardingProgressDots(
                        totalSteps: progress.total,
                        currentIndex: progress.current
                    )
                }
                footer()
            }
            .padding(.horizontal, OnboardingStyle.Spacing.edgePadding)
            .padding(.bottom, OnboardingStyle.Spacing.sectionBlock)
            .padding(.top, OnboardingStyle.Spacing.cardInner)
        }
    }
}

/// Hero-centered layout: vertically centered icon + title + optional
/// status line. Used for Welcome and Connect-style steps.
struct OnboardingHeroLayout<Heading: View, Body: View>: View {
    let icon: AnyView
    @ViewBuilder let heading: () -> Heading
    @ViewBuilder let bodyContent: () -> Body

    init<I: View>(
        @ViewBuilder icon: () -> I,
        @ViewBuilder heading: @escaping () -> Heading,
        @ViewBuilder bodyContent: @escaping () -> Body = { EmptyView() }
    ) {
        self.icon = AnyView(icon())
        self.heading = heading
        self.bodyContent = bodyContent
    }

    var body: some View {
        VStack(spacing: OnboardingStyle.Spacing.heroToTitle) {
            Spacer()
            icon
            VStack(spacing: OnboardingStyle.Spacing.titleToBody) {
                heading()
            }
            bodyContent()
            Spacer()
        }
    }
}

/// List-style layout: top-aligned heading + a stack of cards. Used for
/// LanePicker, PickMainAI, FirstDoc.
struct OnboardingListLayout<Heading: View, List: View>: View {
    @ViewBuilder let heading: () -> Heading
    @ViewBuilder let listContent: () -> List

    var body: some View {
        VStack(spacing: OnboardingStyle.Spacing.sectionBlock) {
            heading()
            VStack(spacing: OnboardingStyle.Spacing.stackedItems) {
                listContent()
            }
            Spacer(minLength: 0)
        }
    }
}
