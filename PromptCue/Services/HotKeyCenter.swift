import KeyboardShortcuts

@MainActor
final class HotKeyCenter {
    func registerDefaultShortcuts(
        onCapture: @escaping () -> Void,
        onToggleStack: @escaping () -> Void
    ) {
        KeyboardShortcuts.removeAllHandlers()

        KeyboardShortcuts.onKeyUp(for: .quickCapture) {
            onCapture()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleStackPanel) {
            onToggleStack()
        }
    }

    func unregisterAll() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
