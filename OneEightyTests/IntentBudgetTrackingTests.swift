import XCTest
@testable import OneEighty

final class IntentBudgetTrackingTests: XCTestCase {

    /// Debouncer flush routes through LiveActivityManager — manager's tracker records the update
    nonisolated func testDebouncerFlushRecordedInManagerTracker() async {
        await MainActor.run {
            LiveActivityManager.shared.resetForTesting()
            IntentActivityDebouncer.shared.resetForTesting()

            IntentActivityDebouncer.shared.submit(bpm: 180, isPlaying: true, priority: .critical)

            XCTAssertEqual(IntentActivityDebouncer.shared.flushCount, 1,
                           "Debouncer should have flushed once")
        }

        try? await Task.sleep(for: .milliseconds(100))

        await MainActor.run {
            let manager = LiveActivityManager.shared
            XCTAssertGreaterThanOrEqual(manager.tracker.totalUpdateCount, 1,
                                        "Manager tracker should record the debouncer's flush")
        }
    }

    /// Duplicate state from debouncer is caught by manager dedup — no extra tracker increment
    nonisolated func testDuplicateFromDebouncerDedupedByManager() async {
        await MainActor.run {
            LiveActivityManager.shared.resetForTesting()
            IntentActivityDebouncer.shared.resetForTesting()

            // First flush
            IntentActivityDebouncer.shared.submit(bpm: 180, isPlaying: true, priority: .critical)
        }

        try? await Task.sleep(for: .milliseconds(400))

        await MainActor.run {
            let countAfterFirst = LiveActivityManager.shared.tracker.totalUpdateCount
            XCTAssertGreaterThan(countAfterFirst, 0, "First flush should be recorded")

            // Reset debouncer dedup so it forwards again, but manager should dedup
            IntentActivityDebouncer.shared.resetForTesting()
            IntentActivityDebouncer.shared.submit(bpm: 180, isPlaying: true, priority: .critical)
        }

        try? await Task.sleep(for: .milliseconds(400))

        await MainActor.run {
            let manager = LiveActivityManager.shared
            XCTAssertEqual(manager.tracker.totalUpdateCount, 1,
                           "Manager dedup should catch identical state from debouncer")
        }
    }

    /// Batched BPM changes produce a single manager update
    nonisolated func testBatchedBPMProducesSingleManagerUpdate() async {
        await MainActor.run {
            LiveActivityManager.shared.resetForTesting()
            IntentActivityDebouncer.shared.resetForTesting()

            // Rapid BPM taps
            for bpm in 181...185 {
                IntentActivityDebouncer.shared.submit(bpm: bpm, isPlaying: true, priority: .normal)
            }
        }

        try? await Task.sleep(for: .milliseconds(500))

        await MainActor.run {
            let debouncer = IntentActivityDebouncer.shared
            let manager = LiveActivityManager.shared

            XCTAssertEqual(debouncer.flushCount, 1,
                           "Debouncer should coalesce into 1 flush")
            XCTAssertEqual(debouncer.lastFlushedBPM, 185,
                           "Should flush with final BPM")
            XCTAssertGreaterThanOrEqual(manager.tracker.totalUpdateCount, 1,
                                        "Manager should record the batched update")
        }
    }
}
