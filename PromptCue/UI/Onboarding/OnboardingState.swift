import Foundation
import SwiftUI

@MainActor
final class OnboardingState: ObservableObject {
    @Published private(set) var step: OnboardingStep
    @Published private(set) var selectedLane: OnboardingLane?
    @Published var selectedClient: MCPConnectorClient?

    private let service: OnboardingService
    let connector: MCPConnectorSettingsModel?
    private let onComplete: () -> Void

    init(
        service: OnboardingService,
        connector: MCPConnectorSettingsModel? = nil,
        onComplete: @escaping () -> Void = {}
    ) {
        self.service = service
        self.connector = connector
        self.onComplete = onComplete
        self.step = service.currentStep
        self.selectedLane = service.lane
    }

    func goToLanePicker() {
        step = .lanePicker
        service.recordStep(.lanePicker)
    }

    func selectLane(_ lane: OnboardingLane) {
        selectedLane = lane
        service.recordLaneSelection(lane)

        switch lane {
        case .lane1SharedMemory:
            advanceTo(.lane1PickMainAI)
        case .lane2CaptureStack:
            advanceTo(.lane2Capture)
        case .skipped:
            finish()
        }
    }

    func selectClient(_ client: MCPConnectorClient) {
        selectedClient = client
        switch client {
        case .claudeCode, .codex:
            advanceTo(.lane1ConnectCode)
        case .claudeDesktop:
            advanceTo(.lane1ConnectDesktop)
        }
    }

    func advanceTo(_ next: OnboardingStep) {
        step = next
        service.recordStep(next)
    }

    func finish() {
        switch selectedLane {
        case .lane1SharedMemory:
            service.markLane1Completed()
        case .lane2CaptureStack:
            service.markLane2Completed()
        case .skipped, nil:
            service.markOnboardingCompleted()
        }

        step = .completed
        onComplete()
    }

    func skipFromAnyStep() {
        service.markOnboardingCompleted()
        step = .completed
        onComplete()
    }
}
