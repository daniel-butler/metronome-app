import XCTest
@testable import OneEighty

final class IntentActivityDebouncerTests: XCTestCase {

    // MARK: - BPM Batching

    /// 5 rapid BPM increments within batch window → 1 flush with the final BPM
    nonisolated func testRapidBPMChangesCoalesceIntoSingleFlush() async {
        await MainActor.run {
            IntentActivityDebouncer.shared.resetForTesting()

            for bpm in 181...185 {
                IntentActivityDebouncer.shared.submit(bpm: bpm, isPlaying: true, priority: .normal)
            }

            XCTAssertTrue(IntentActivityDebouncer.shared.hasPending,
                          "Should have pending state during batch window")
            XCTAssertEqual(IntentActivityDebouncer.shared.flushCount, 0,
                           "No flushes should occur during batch window")
        }

        try? await Task.sleep(for: .milliseconds(200))

        await MainActor.run {
            let debouncer = IntentActivityDebouncer.shared
            XCTAssertEqual(debouncer.flushCount, 1,
                           "5 rapid BPM changes should coalesce into 1 flush")
            XCTAssertEqual(debouncer.lastFlushedBPM, 185,
                           "Should flush with the final BPM value")
            XCTAssertFalse(debouncer.hasPending,
                           "No pending state after flush")
        }
    }

    /// Only the last BPM in a rapid burst is flushed (intermediate values are dropped)
    nonisolated func testOnlyFinalBPMInBurstIsFlushed() async {
        await MainActor.run {
            IntentActivityDebouncer.shared.resetForTesting()

            IntentActivityDebouncer.shared.submit(bpm: 181, isPlaying: true, priority: .normal)
            IntentActivityDebouncer.shared.submit(bpm: 183, isPlaying: true, priority: .normal)
            IntentActivityDebouncer.shared.submit(bpm: 190, isPlaying: true, priority: .normal)
        }

        try? await Task.sleep(for: .milliseconds(200))

        await MainActor.run {
            let debouncer = IntentActivityDebouncer.shared
            XCTAssertEqual(debouncer.lastFlushedBPM, 190,
                           "Intermediate BPM values should be dropped, only final flushed")
        }
    }

    // MARK: - Critical Priority

    /// Play/stop changes bypass the batch window and flush immediately
    nonisolated func testCriticalPriorityBypassesBatch() async {
        await MainActor.run {
            IntentActivityDebouncer.shared.resetForTesting()

            IntentActivityDebouncer.shared.submit(bpm: 180, isPlaying: true, priority: .critical)

            XCTAssertEqual(IntentActivityDebouncer.shared.flushCount, 1,
                           "Critical priority should flush immediately")
            XCTAssertEqual(IntentActivityDebouncer.shared.lastFlushedBPM, 180)
            XCTAssertEqual(IntentActivityDebouncer.shared.lastFlushedIsPlaying, true)
            XCTAssertFalse(IntentActivityDebouncer.shared.hasPending,
                           "Critical flush should not leave pending state")
        }
    }

    /// Critical update during a pending BPM batch: flushes the pending batch first, then the critical
    nonisolated func testCriticalDuringPendingBatchFlushesBoth() async {
        await MainActor.run {
            IntentActivityDebouncer.shared.resetForTesting()

            // Start a BPM batch (playing)
            IntentActivityDebouncer.shared.submit(bpm: 185, isPlaying: true, priority: .normal)
            XCTAssertTrue(IntentActivityDebouncer.shared.hasPending)

            // Critical arrives mid-batch: stop
            IntentActivityDebouncer.shared.submit(bpm: 185, isPlaying: false, priority: .critical)

            XCTAssertEqual(IntentActivityDebouncer.shared.flushCount, 2,
                           "Should flush pending batch + critical = 2 flushes")
            XCTAssertEqual(IntentActivityDebouncer.shared.lastFlushedIsPlaying, false,
                           "Last flush should be the critical (stop) update")
            XCTAssertFalse(IntentActivityDebouncer.shared.hasPending)
        }
    }

    // MARK: - Duplicate Suppression

    /// Submitting the same state twice via critical does not produce a second flush
    nonisolated func testDuplicateStateSuppressed() async {
        await MainActor.run {
            IntentActivityDebouncer.shared.resetForTesting()

            IntentActivityDebouncer.shared.submit(bpm: 180, isPlaying: true, priority: .critical)
            XCTAssertEqual(IntentActivityDebouncer.shared.flushCount, 1)

            // Same state again
            IntentActivityDebouncer.shared.submit(bpm: 180, isPlaying: true, priority: .critical)
            XCTAssertEqual(IntentActivityDebouncer.shared.flushCount, 1,
                           "Duplicate state should be suppressed")
        }
    }

    /// After a batched flush, submitting the same final BPM is suppressed
    nonisolated func testDuplicateAfterBatchFlushSuppressed() async {
        await MainActor.run {
            IntentActivityDebouncer.shared.resetForTesting()

            IntentActivityDebouncer.shared.submit(bpm: 185, isPlaying: true, priority: .normal)
        }

        try? await Task.sleep(for: .milliseconds(200))

        await MainActor.run {
            let debouncer = IntentActivityDebouncer.shared
            XCTAssertEqual(debouncer.flushCount, 1)

            // Submit same state via critical — should be suppressed
            debouncer.submit(bpm: 185, isPlaying: true, priority: .critical)
            XCTAssertEqual(debouncer.flushCount, 1,
                           "Same state after batch flush should be suppressed")
        }
    }

    /// Different BPM is NOT suppressed (dedup only blocks identical states)
    nonisolated func testDifferentBPMNotSuppressed() async {
        await MainActor.run {
            IntentActivityDebouncer.shared.resetForTesting()

            IntentActivityDebouncer.shared.submit(bpm: 180, isPlaying: true, priority: .critical)
            XCTAssertEqual(IntentActivityDebouncer.shared.flushCount, 1)

            IntentActivityDebouncer.shared.submit(bpm: 181, isPlaying: true, priority: .critical)
            XCTAssertEqual(IntentActivityDebouncer.shared.flushCount, 2,
                           "Different BPM should not be suppressed by dedup")
        }
    }

    // MARK: - Fresh Batch After Flush

    /// After a batch fires, a new burst starts a fresh batch window
    nonisolated func testNewBurstAfterFlushStartsFreshBatch() async {
        await MainActor.run {
            IntentActivityDebouncer.shared.resetForTesting()

            // First burst
            IntentActivityDebouncer.shared.submit(bpm: 185, isPlaying: true, priority: .normal)
        }

        try? await Task.sleep(for: .milliseconds(200))

        await MainActor.run {
            XCTAssertEqual(IntentActivityDebouncer.shared.flushCount, 1)

            // Second burst — different BPM
            IntentActivityDebouncer.shared.submit(bpm: 190, isPlaying: true, priority: .normal)
            XCTAssertTrue(IntentActivityDebouncer.shared.hasPending,
                          "New burst should create new pending state")
        }

        try? await Task.sleep(for: .milliseconds(200))

        await MainActor.run {
            XCTAssertEqual(IntentActivityDebouncer.shared.flushCount, 2,
                           "Second burst should produce a second flush")
            XCTAssertEqual(IntentActivityDebouncer.shared.lastFlushedBPM, 190)
        }
    }

    // MARK: - Reset

    nonisolated func testResetClearsAllState() async {
        await MainActor.run {
            let debouncer = IntentActivityDebouncer.shared
            debouncer.resetForTesting()

            debouncer.submit(bpm: 180, isPlaying: true, priority: .critical)
            XCTAssertEqual(debouncer.flushCount, 1)

            debouncer.resetForTesting()

            XCTAssertEqual(debouncer.flushCount, 0)
            XCTAssertNil(debouncer.lastFlushedBPM)
            XCTAssertNil(debouncer.lastFlushedIsPlaying)
            XCTAssertFalse(debouncer.hasPending)
        }
    }
}
