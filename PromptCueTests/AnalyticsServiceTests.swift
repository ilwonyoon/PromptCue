import XCTest
import PromptCueCore
@testable import Prompt_Cue

@MainActor
final class AnalyticsServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AnalyticsServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testConfigureSkipsSignalsWhenAppIDIsMissing() {
        var initializedAppIDs: [String] = []
        var signals: [(String, [String: String])] = []
        let service = AnalyticsService(
            infoDictionaryProvider: { [:] },
            environmentProvider: { [:] },
            bundledAppID: nil,
            userDefaults: defaults,
            initializeTelemetryDeck: { initializedAppIDs.append($0) },
            sendSignal: { name, parameters in
                signals.append((name, parameters))
            }
        )

        service.configure()
        service.trackCaptureSubmitted(hasScreenshot: true, isEdit: false, textLength: 42)
        service.trackPromptCopied(copyMode: .single, cardCount: 1)
        service.trackStackOpened(promptCount: 3)

        XCTAssertFalse(service.isConfigured)
        XCTAssertTrue(initializedAppIDs.isEmpty)
        XCTAssertTrue(signals.isEmpty)
    }

    func testConfigureFallsBackToBundledAppIDWhenOverridesAreMissing() {
        var initializedAppIDs: [String] = []
        let service = AnalyticsService(
            infoDictionaryProvider: { [:] },
            environmentProvider: { [:] },
            userDefaults: defaults,
            initializeTelemetryDeck: { initializedAppIDs.append($0) },
            sendSignal: { _, _ in }
        )

        service.configure()

        XCTAssertTrue(service.isConfigured)
        XCTAssertEqual(initializedAppIDs, ["F4233BDD-165C-4AB1-A88A-E883D8201965"])
    }

    func testCoreKPIsEmitExpectedSignalsWhenConfigured() {
        var initializedAppIDs: [String] = []
        var signals: [(String, [String: String])] = []
        let service = AnalyticsService(
            infoDictionaryProvider: {
                ["BacktickTelemetryDeckAppID": "F4233BDD-165C-4AB1-A88A-E883D8201965"]
            },
            environmentProvider: { [:] },
            userDefaults: defaults,
            initializeTelemetryDeck: { initializedAppIDs.append($0) },
            sendSignal: { name, parameters in
                signals.append((name, parameters))
            }
        )

        service.configure()
        service.trackCaptureSubmitted(hasScreenshot: true, isEdit: false, textLength: 120)
        service.trackPromptCopied(copyMode: .multi, cardCount: 4)
        service.trackStackOpened(promptCount: 7)
        service.trackMemorySaved(documentType: .reference, saveMode: .update, source: .app)

        XCTAssertTrue(service.isConfigured)
        XCTAssertEqual(initializedAppIDs, ["F4233BDD-165C-4AB1-A88A-E883D8201965"])
        XCTAssertEqual(signals.map(\.0), [
            "capture.submitted",
            "prompt.copied",
            "stack.opened",
            "memory.saved",
        ])
        XCTAssertEqual(signals[0].1["textLengthBucket"], "medium")
        XCTAssertEqual(signals[1].1["copyMode"], "multi")
        XCTAssertEqual(signals[1].1["cardCountBucket"], "4to10")
        XCTAssertEqual(signals[2].1["promptCountBucket"], "6to20")
        XCTAssertEqual(signals[3].1["documentType"], "reference")
        XCTAssertEqual(signals[3].1["saveMode"], "update")
        XCTAssertEqual(signals[3].1["source"], "app")
    }

    func testSyncMCPActivitySignalsOnlyEmitsForNewPostEnableActivities() {
        let enabledAt = Date(timeIntervalSince1970: 100)
        var signals: [(String, [String: String])] = []
        let service = AnalyticsService(
            infoDictionaryProvider: {
                ["BacktickTelemetryDeckAppID": "F4233BDD-165C-4AB1-A88A-E883D8201965"]
            },
            environmentProvider: { [:] },
            userDefaults: defaults,
            nowProvider: { enabledAt },
            initializeTelemetryDeck: { _ in },
            sendSignal: { name, parameters in
                signals.append((name, parameters))
            }
        )

        service.configure()

        let preexistingActivity = MCPConnectorConnectionActivity(
            transport: .remoteHTTP,
            surface: "web",
            clientName: "ChatGPT",
            clientVersion: "1.0",
            sessionID: "before",
            toolName: "backtick_save_doc",
            requestedToolName: "backtick_save_doc",
            recordedAt: Date(timeIntervalSince1970: 90),
            configuredClientID: nil,
            launchCommand: nil,
            launchArguments: nil
        )
        let freshActivity = MCPConnectorConnectionActivity(
            transport: .remoteHTTP,
            surface: "web",
            clientName: "ChatGPT",
            clientVersion: "1.0",
            sessionID: "after",
            toolName: "backtick_update_doc",
            requestedToolName: "backtick_update_doc",
            recordedAt: Date(timeIntervalSince1970: 200),
            configuredClientID: nil,
            launchCommand: nil,
            launchArguments: nil
        )

        service.syncMCPActivitySignals([preexistingActivity, freshActivity])
        service.syncMCPActivitySignals([preexistingActivity, freshActivity])

        XCTAssertEqual(signals.map(\.0), [
            "mcp.connected",
            "mcp.toolCallSucceeded",
            "memory.saved",
        ])
        XCTAssertEqual(signals[0].1["surface"], "chatgpt_web")
        XCTAssertEqual(signals[0].1["transport"], "remote_http")
        XCTAssertEqual(signals[1].1["toolFamily"], "memory")
        XCTAssertEqual(signals[2].1["saveMode"], "update")
        XCTAssertEqual(signals[2].1["source"], "mcp")
    }
}
