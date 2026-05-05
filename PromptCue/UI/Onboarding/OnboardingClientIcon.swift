import SwiftUI

enum OnboardingClientKind {
    case claudeDesktop
    case claudeCode
    case codex
    case chatGPT

    init?(_ connector: MCPConnectorClient?) {
        guard let connector else { return nil }
        switch connector {
        case .claudeDesktop: self = .claudeDesktop
        case .claudeCode: self = .claudeCode
        case .codex: self = .codex
        }
    }
}

/// Renders client icons at a consistent size across onboarding.
///
/// Each upstream asset is shaped differently — some come as filled squircles
/// (Claude Desktop, Claude Code), some as a centered glyph with transparent
/// padding (Codex), and ChatGPT's official monoblossom is just a glyph.
///
/// To make the row look balanced we tag each kind with how it should be
/// presented: `bleed` images already include their own background and are
/// rendered edge-to-edge, while `glyph` icons get a neutral squircle wrap
/// so they end up at roughly the same optical size.
struct OnboardingClientIcon: View {
    let kind: OnboardingClientKind?
    var size: CGFloat = 28

    init(kind: OnboardingClientKind?, size: CGFloat = 28) {
        self.kind = kind
        self.size = size
    }

    init(client: MCPConnectorClient?, size: CGFloat = 28) {
        self.kind = OnboardingClientKind(client)
        self.size = size
    }

    var body: some View {
        Group {
            switch presentation {
            case .bleed(let assetName):
                if let nsImage = NSImage(named: assetName) {
                    let scale = bleedScale
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size * scale, height: size * scale)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                } else {
                    fallback
                }
            case .glyph(let assetName, let isTemplate):
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(squircleFill)

                    if let nsImage = NSImage(named: assetName) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .renderingMode(isTemplate ? .template : .original)
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(glyphTint)
                            .padding(size * 0.18)
                    } else {
                        fallback
                    }
                }
                .frame(width: size, height: size)
            case .symbol(let symbol):
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(squircleFill)
                    Image(systemName: symbol)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(glyphTint)
                        .padding(size * 0.22)
                }
                .frame(width: size, height: size)
            }
        }
    }

    private var presentation: Presentation {
        switch kind {
        case .claudeDesktop: return .bleed("ClaudeDesktopIcon")
        case .claudeCode: return .bleed("ClaudeCodeIcon")
        case .codex: return .bleed("CodexIcon")
        case .chatGPT:
            // ChatGPT mark stays in OpenAI's official light treatment
            // (white squircle + black blossom) regardless of system theme,
            // matching how OpenAI publishes the brand mark.
            return .glyph("ChatGPTIconBlack", isTemplate: false)
        case nil: return .symbol("bubble.left.and.bubble.right")
        }
    }

    private var fallback: some View {
        Image(systemName: "bubble.left.and.bubble.right")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(SemanticTokens.Text.secondary)
            .padding(size * 0.22)
    }

    private var squircleFill: Color {
        // ChatGPT brand mark stays light theme — white squircle with the
        // black OpenAI blossom — so it reads consistently across system theme.
        Color.white
    }

    /// Per-kind optical scale applied to bleed assets so the visible mark
    /// inside each upstream PNG ends up at roughly the same optical size.
    /// Codex's source PNG has a thicker internal margin than Claude's, so
    /// we nudge it up so it matches the row.
    private var bleedScale: CGFloat {
        switch kind {
        case .codex: return 1.18
        default: return 1.0
        }
    }

    private var glyphTint: Color {
        // The PNGs themselves are pre-colored (black or white versions),
        // so we don't tint — kept here for the SF symbol fallback path.
        SemanticTokens.Text.secondary
    }
}

private enum Presentation {
    case bleed(String)
    case glyph(String, isTemplate: Bool)
    case symbol(String)
}
