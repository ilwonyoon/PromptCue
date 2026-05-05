import Foundation

enum OnboardingLane: String, Codable {
    case lane1SharedMemory = "lane1"
    case lane2CaptureStack = "lane2"
    case skipped
}

enum OnboardingStep: String, Codable {
    case welcome
    case lanePicker
    case lane1PickMainAI = "lane1_pick"
    case lane1ConnectCode = "lane1_connect_code"
    case lane1ConnectDesktop = "lane1_connect_desktop"
    case lane1ConnectChatGPT = "lane1_connect_chatgpt"
    case lane1FirstDoc = "lane1_first_doc"
    case lane2Capture = "lane2_capture"
    case lane2Stack = "lane2_stack"
    case lane2FlowStory = "lane2_flow_story"
    case completed
}

protocol OnboardingPersisting: AnyObject {
    func bool(forKey key: String) -> Bool
    func set(_ value: Bool, forKey key: String)
    func string(forKey key: String) -> String?
    func setString(_ value: String?, forKey key: String)
}

extension UserDefaults: OnboardingPersisting {
    func setString(_ value: String?, forKey key: String) {
        if let value {
            set(value, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}

@MainActor
final class OnboardingService {
    enum Keys {
        static let completed = "com.backtick.onboarding.completed"
        static let lane = "com.backtick.onboarding.lane"
        static let step = "com.backtick.onboarding.step"
        static let lane1Completed = "com.backtick.onboarding.lane1.completed"
        static let lane2Completed = "com.backtick.onboarding.lane2.completed"
    }

    private let store: any OnboardingPersisting

    init(store: any OnboardingPersisting = UserDefaults.standard) {
        self.store = store
    }

    var hasCompletedOnboarding: Bool {
        store.bool(forKey: Keys.completed)
    }

    var lane: OnboardingLane? {
        guard let raw = store.string(forKey: Keys.lane) else {
            return nil
        }
        return OnboardingLane(rawValue: raw)
    }

    var currentStep: OnboardingStep {
        guard let raw = store.string(forKey: Keys.step),
              let step = OnboardingStep(rawValue: raw) else {
            return .welcome
        }
        return step
    }

    var lane1Completed: Bool {
        store.bool(forKey: Keys.lane1Completed)
    }

    var lane2Completed: Bool {
        store.bool(forKey: Keys.lane2Completed)
    }

    var shouldPresentOnFirstLaunch: Bool {
        !hasCompletedOnboarding && lane == nil
    }

    func recordLaneSelection(_ lane: OnboardingLane) {
        store.setString(lane.rawValue, forKey: Keys.lane)

        if lane == .skipped {
            markOnboardingCompleted()
        }
    }

    func recordStep(_ step: OnboardingStep) {
        store.setString(step.rawValue, forKey: Keys.step)
    }

    func markLane1Completed() {
        store.set(true, forKey: Keys.lane1Completed)
        markOnboardingCompleted()
    }

    func markLane2Completed() {
        store.set(true, forKey: Keys.lane2Completed)
        markOnboardingCompleted()
    }

    func markOnboardingCompleted() {
        store.set(true, forKey: Keys.completed)
        recordStep(.completed)
    }

    func resetForReplay() {
        store.set(false, forKey: Keys.completed)
        store.setString(nil, forKey: Keys.lane)
        store.setString(OnboardingStep.welcome.rawValue, forKey: Keys.step)
    }
}
