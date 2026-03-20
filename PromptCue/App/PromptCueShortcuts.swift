import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let quickCapture = Self(
        "quickCapture",
        default: .init(.backtick, modifiers: [.command])
    )

    static let toggleStackPanel = Self(
        "toggleStackPanel",
        default: .init(.two, modifiers: [.command])
    )

    static let toggleMemoryViewer = Self(
        "toggleMemoryViewer",
        default: .init(.three, modifiers: [.command])
    )
}
