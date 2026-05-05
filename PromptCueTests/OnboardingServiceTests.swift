import XCTest
@testable import Prompt_Cue

@MainActor
final class OnboardingServiceTests: XCTestCase {
    private var store: InMemoryOnboardingStore!
    private var service: OnboardingService!

    override func setUp() {
        super.setUp()
        store = InMemoryOnboardingStore()
        service = OnboardingService(store: store)
    }

    override func tearDown() {
        service = nil
        store = nil
        super.tearDown()
    }

    func testFirstLaunchTriggersPresentation() {
        XCTAssertTrue(service.shouldPresentOnFirstLaunch)
        XCTAssertNil(service.lane)
        XCTAssertEqual(service.currentStep, .welcome)
    }

    func testSelectingLane2RecordsStateAndKeepsOnboardingOpen() {
        service.recordLaneSelection(.lane2CaptureStack)

        XCTAssertEqual(service.lane, .lane2CaptureStack)
        XCTAssertFalse(service.hasCompletedOnboarding)
        XCTAssertFalse(service.shouldPresentOnFirstLaunch)
    }

    func testSelectingSkipMarksCompletion() {
        service.recordLaneSelection(.skipped)

        XCTAssertEqual(service.lane, .skipped)
        XCTAssertTrue(service.hasCompletedOnboarding)
    }

    func testCompletingLane2MarksLane2AndOnboarding() {
        service.recordLaneSelection(.lane2CaptureStack)

        service.markLane2Completed()

        XCTAssertTrue(service.lane2Completed)
        XCTAssertFalse(service.lane1Completed)
        XCTAssertTrue(service.hasCompletedOnboarding)
    }

    func testCompletingLane1MarksLane1AndOnboarding() {
        service.recordLaneSelection(.lane1SharedMemory)

        service.markLane1Completed()

        XCTAssertTrue(service.lane1Completed)
        XCTAssertFalse(service.lane2Completed)
        XCTAssertTrue(service.hasCompletedOnboarding)
    }

    func testResetForReplayClearsCompletionAndLane() {
        service.recordLaneSelection(.lane2CaptureStack)
        service.markLane2Completed()

        service.resetForReplay()

        XCTAssertFalse(service.hasCompletedOnboarding)
        XCTAssertNil(service.lane)
        XCTAssertEqual(service.currentStep, .welcome)

        XCTAssertTrue(service.lane2Completed,
                      "Per-lane completion is preserved across replays so users see updated cross-sell copy.")
    }

    func testStepRoundTripsThroughPersistence() {
        service.recordStep(.lane2Stack)
        let reborn = OnboardingService(store: store)

        XCTAssertEqual(reborn.currentStep, .lane2Stack)
    }

    func testLaneRoundTripsThroughPersistence() {
        service.recordLaneSelection(.lane2CaptureStack)
        let reborn = OnboardingService(store: store)

        XCTAssertEqual(reborn.lane, .lane2CaptureStack)
    }
}

@MainActor
final class OnboardingStateTests: XCTestCase {
    func testGoToLanePickerAdvancesStep() {
        let store = InMemoryOnboardingStore()
        let service = OnboardingService(store: store)
        let state = OnboardingState(service: service)

        state.goToLanePicker()

        XCTAssertEqual(state.step, .lanePicker)
        XCTAssertEqual(service.currentStep, .lanePicker)
    }

    func testSelectingLane2RoutesToCapture() {
        let store = InMemoryOnboardingStore()
        let service = OnboardingService(store: store)
        let state = OnboardingState(service: service)

        state.selectLane(.lane2CaptureStack)

        XCTAssertEqual(state.selectedLane, .lane2CaptureStack)
        XCTAssertEqual(state.step, .lane2Capture)
    }

    func testSelectingLane1RoutesToPickMainAI() {
        let store = InMemoryOnboardingStore()
        let service = OnboardingService(store: store)
        let state = OnboardingState(service: service)

        state.selectLane(.lane1SharedMemory)

        XCTAssertEqual(state.selectedLane, .lane1SharedMemory)
        XCTAssertEqual(state.step, .lane1PickMainAI)
    }

    func testSkipFromAnyStepInvokesCompletionCallback() {
        let store = InMemoryOnboardingStore()
        let service = OnboardingService(store: store)
        var completionCalled = false
        let state = OnboardingState(service: service) {
            completionCalled = true
        }

        state.skipFromAnyStep()

        XCTAssertTrue(completionCalled)
        XCTAssertTrue(service.hasCompletedOnboarding)
        XCTAssertEqual(state.step, .completed)
    }

    func testFinishMarksAppropriateLaneCompletion() {
        let store = InMemoryOnboardingStore()
        let service = OnboardingService(store: store)
        let state = OnboardingState(service: service)

        state.selectLane(.lane2CaptureStack)
        state.advanceTo(.lane2FlowStory)
        state.finish()

        XCTAssertTrue(service.lane2Completed)
        XCTAssertTrue(service.hasCompletedOnboarding)
    }
}

@MainActor
private final class InMemoryOnboardingStore: OnboardingPersisting {
    private var bools: [String: Bool] = [:]
    private var strings: [String: String] = [:]

    func bool(forKey key: String) -> Bool {
        bools[key] ?? false
    }

    func set(_ value: Bool, forKey key: String) {
        bools[key] = value
    }

    func string(forKey key: String) -> String? {
        strings[key]
    }

    func setString(_ value: String?, forKey key: String) {
        if let value {
            strings[key] = value
        } else {
            strings.removeValue(forKey: key)
        }
    }
}
