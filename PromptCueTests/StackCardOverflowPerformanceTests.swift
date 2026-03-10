import CoreGraphics
import Foundation
import XCTest
@testable import Prompt_Cue

final class StackCardOverflowPerformanceTests: XCTestCase {
    private let benchmarkWidth = StackCardOverflowPolicy.cardTextWidth
    private let benchmarkFixtureCount = 8
    private let benchmarkRunEnabled: Bool = {
#if PROMPTCUE_RUN_PERF_BENCHMARKS
        true
#else
        ProcessInfo.processInfo.environment["PROMPTCUE_RUN_PERF_BENCHMARKS"] == "1"
#endif
    }()
    private let benchmarkIterations = {
        if let rawValue = ProcessInfo.processInfo.environment["PROMPTCUE_STACK_OVERFLOW_BENCHMARK_ITERATIONS"],
           let parsedValue = Int(rawValue),
           parsedValue > 0 {
            return parsedValue
        }

        return 250
    }()

    override func tearDown() {
        StackCardOverflowPolicy.resetCacheForTesting()
        super.tearDown()
    }

    func testCachedOverflowMetricsBenchmark() throws {
        try XCTSkipUnless(
            benchmarkRunEnabled,
            "Compile with -DPROMPTCUE_RUN_PERF_BENCHMARKS or set PROMPTCUE_RUN_PERF_BENCHMARKS=1 to run stack overflow benchmarks."
        )

        let fixtures = makeLongTextFixtures(count: benchmarkFixtureCount)
        StackCardOverflowPolicy.resetCacheForTesting()

        let uncached = benchmark(label: "uncached", fixtures: fixtures) { text in
            _ = StackCardOverflowPolicy.uncachedMetrics(for: text.text, availableWidth: benchmarkWidth)
        }

        StackCardOverflowPolicy.resetCacheForTesting()
        for text in fixtures {
            _ = StackCardOverflowPolicy.metrics(
                for: text.text,
                cacheIdentity: text.id,
                availableWidth: benchmarkWidth
            )
        }

        let cachedWarm = benchmark(label: "cached-warm", fixtures: fixtures) { text in
            _ = StackCardOverflowPolicy.metrics(
                for: text.text,
                cacheIdentity: text.id,
                availableWidth: benchmarkWidth
            )
        }

        let speedup = uncached.totalMilliseconds / max(cachedWarm.totalMilliseconds, 0.001)
        print(
            String(
                format: "Stack overflow benchmark: uncached=%.2fms cachedWarm=%.2fms speedup=%.2fx ops=%d",
                uncached.totalMilliseconds,
                cachedWarm.totalMilliseconds,
                speedup,
                uncached.operationCount
            )
        )

        XCTAssertGreaterThan(uncached.totalMilliseconds, cachedWarm.totalMilliseconds)
        XCTAssertGreaterThan(
            speedup,
            4,
            "Expected warm-cache overflow metrics to be materially faster than uncached measurement."
        )
    }

    private func benchmark(
        label: String,
        fixtures: [BenchmarkFixture],
        operation: (BenchmarkFixture) -> Void
    ) -> BenchmarkResult {
        let clock = ContinuousClock()
        let duration = clock.measure {
            for _ in 0..<benchmarkIterations {
                for text in fixtures {
                    operation(text)
                }
            }
        }

        let operationCount = benchmarkIterations * fixtures.count
        let totalMilliseconds = duration.components.seconds.asMilliseconds
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        let averageMicroseconds = totalMilliseconds * 1_000 / Double(operationCount)

        print(
            String(
                format: "Stack overflow benchmark [%@]: total=%.2fms avg=%.2fus ops=%d",
                label,
                totalMilliseconds,
                averageMicroseconds,
                operationCount
            )
        )

        return BenchmarkResult(
            totalMilliseconds: totalMilliseconds,
            averageMicroseconds: averageMicroseconds,
            operationCount: operationCount
        )
    }

    private func makeLongTextFixtures(count: Int) -> [BenchmarkFixture] {
        (0..<count).map { index in
            let repeatedLine = "Backtick keeps Stack readable while long capture dumps stay expandable without blocking execution flow."
            return BenchmarkFixture(
                id: UUID(),
                text: Array(repeating: "\(repeatedLine) [fixture \(index)]", count: 18 + index).joined(separator: " ")
            )
        }
    }
}

private struct BenchmarkFixture {
    let id: UUID
    let text: String
}

private struct BenchmarkResult {
    let totalMilliseconds: Double
    let averageMicroseconds: Double
    let operationCount: Int
}

private extension Int64 {
    var asMilliseconds: Double {
        Double(self) * 1_000
    }
}
