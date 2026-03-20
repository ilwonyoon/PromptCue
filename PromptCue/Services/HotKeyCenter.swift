import KeyboardShortcuts

@MainActor
final class HotKeyCenter {
    func registerDefaultShortcuts(
        onCapture: @escaping () -> Void,
        onToggleStack: @escaping () -> Void,
        onToggleMemory: @escaping () -> Void
    ) {
        KeyboardShortcuts.removeAllHandlers()

        KeyboardShortcuts.onKeyUp(for: .quickCapture) {
            onCapture()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleStackPanel) {
            onToggleStack()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleMemoryViewer) {
            onToggleMemory()
        }
    }

    func unregisterAll() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
