import AppKit
import Foundation
import OSLog

@MainActor
enum PerformanceTrace {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.promptcue.promptcue"
    private static let signposter = OSSignposter(subsystem: subsystem, category: "Performance")
    private static let logger = Logger(subsystem: subsystem, category: "Performance")

    private struct PendingStackOpenTrace {
        let state: OSSignpostIntervalState
        let startedAt: CFAbsoluteTime
        var lastMarkedAt: CFAbsoluteTime
    }

    private static var pendingStackOpenTrace: PendingStackOpenTrace?

    static var shouldTraceStackToggleOnStart: Bool {
        ProcessInfo.processInfo.environment["PROMPTCUE_TRACE_STACK_TOGGLE_ON_START"] == "1"
    }

    static var stackToggleDelayNanoseconds: UInt64 {
        guard let rawValue = ProcessInfo.processInfo.environment["PROMPTCUE_TRACE_STACK_TOGGLE_DELAY_MS"],
              let milliseconds = UInt64(rawValue)
        else {
            return 250_000_000
        }

        return milliseconds * 1_000_000
    }

    private static var shouldAutoQuitAfterStackTrace: Bool {
        ProcessInfo.processInfo.environment["PROMPTCUE_TRACE_AUTO_QUIT_AFTER_STACK"] == "1"
    }

    private static var shouldPrintStackTraceMetric: Bool {
        ProcessInfo.processInfo.environment["PROMPTCUE_TRACE_STDOUT_METRIC"] == "1"
    }

    private static var shouldPrintStackPhaseMetrics: Bool {
        ProcessInfo.processInfo.environment["PROMPTCUE_TRACE_STACK_PHASES"] == "1"
    }

    static func beginStackOpenTrace() {
        guard pendingStackOpenTrace == nil else {
            return
        }

        let startedAt = CFAbsoluteTimeGetCurrent()

        pendingStackOpenTrace = PendingStackOpenTrace(
            state: signposter.beginInterval("StackOpenFirstFrame"),
            startedAt: startedAt,
            lastMarkedAt: startedAt
        )
        signposter.emitEvent("StackOpenRequested")
    }

    static func markStackOpenPhase(_ phase: String) {
        guard var pendingStackOpenTrace else {
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        let totalMilliseconds = (now - pendingStackOpenTrace.startedAt) * 1_000
        let deltaMilliseconds = (now - pendingStackOpenTrace.lastMarkedAt) * 1_000
        pendingStackOpenTrace.lastMarkedAt = now
        Self.pendingStackOpenTrace = pendingStackOpenTrace

        logger.info(
            "StackOpenPhase \(phase, privacy: .public) total_ms=\(totalMilliseconds, format: .fixed(precision: 2)) delta_ms=\(deltaMilliseconds, format: .fixed(precision: 2))"
        )

        if shouldPrintStackPhaseMetrics {
            let line = String(
                format: "PROMPTCUE_STACK_OPEN_PHASE=%@ TOTAL_MS=%.2f DELTA_MS=%.2f",
                phase,
                totalMilliseconds,
                deltaMilliseconds
            )
            print(line)
            fflush(stdout)
        }
    }

    static func completeStackOpenTraceIfNeeded() {
        guard let pendingStackOpenTrace else {
            return
        }

        Self.pendingStackOpenTrace = nil

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - pendingStackOpenTrace.startedAt) * 1_000
        logger.info("StackOpenPhase first_frame_displayed total_ms=\(elapsedMilliseconds, format: .fixed(precision: 2))")
        if shouldPrintStackPhaseMetrics {
            let line = String(format: "PROMPTCUE_STACK_OPEN_PHASE=first_frame_displayed TOTAL_MS=%.2f", elapsedMilliseconds)
            print(line)
            fflush(stdout)
        }
        signposter.emitEvent("StackOpenFirstFrameDisplayed")
        signposter.endInterval("StackOpenFirstFrame", pendingStackOpenTrace.state)
        logger.info("StackOpenFirstFrame elapsed_ms=\(elapsedMilliseconds, format: .fixed(precision: 2))")

        if shouldPrintStackTraceMetric {
            let metricLine = String(format: "PROMPTCUE_STACK_OPEN_FIRST_FRAME_MS=%.2f", elapsedMilliseconds)
            print(metricLine)
            fflush(stdout)
        }

        guard shouldAutoQuitAfterStackTrace else {
            return
        }

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
