import Foundation

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selectedTab: SettingsTab

    init(selectedTab: SettingsTab = .general) {
        self.selectedTab = selectedTab
    }
}
