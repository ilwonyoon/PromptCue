import AppKit
import Foundation

enum AppearanceMode: Int, CaseIterable {
    case auto = 0
    case light = 1
    case dark = 2

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .auto:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

enum AppearancePreferences {
    private static let modeKey = "appearance.mode"

    static func load(defaults: UserDefaults = .standard) -> AppearanceMode {
        let raw = defaults.integer(forKey: modeKey)
        return AppearanceMode(rawValue: raw) ?? .auto
    }

    static func save(_ mode: AppearanceMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }
}

@MainActor
final class AppearanceSettingsModel: ObservableObject {
    @Published var mode: AppearanceMode = .auto

    init() {
        refresh()
    }

    func refresh() {
        mode = AppearancePreferences.load()
    }

    func updateMode(_ newMode: AppearanceMode) {
        mode = newMode
        AppearancePreferences.save(newMode)
        applyAppearance()
    }

    func applyAppearance() {
        NSApp.appearance = mode.nsAppearance
    }
}
