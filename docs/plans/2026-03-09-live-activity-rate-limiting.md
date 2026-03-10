# Live Activity Rate Limiting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the basic 0.3s Timer-based throttle in LiveActivityManager with a robust rate-limiting system that tracks update budgets, detects Apple's silent throttling, and provides structured logging for debugging.

**Architecture:** Extract throttle/budget logic into a standalone `ActivityUpdateTracker` that is independently testable (no ActivityKit dependency). `LiveActivityManager` delegates throttle decisions to the tracker. App Intents log their updates through a shared tracker instance for budget visibility. All ActivityKit calls remain in `LiveActivityManager`.

**Tech Stack:** Swift, XCTest, ActivityKit, os.Logger (OSLog)

**Test command:** `make test-unit` (from project root), or for a specific test class:
```bash
cd MetronomeApp && xcodebuild test \
  -scheme MetronomeApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MetronomeAppTests/<TestClassName> \
  -parallel-testing-enabled NO
```

**Key paths:**
- Source: `MetronomeApp/MetronomeApp/`
- Tests: `MetronomeApp/MetronomeAppTests/`
- Widget: `MetronomeApp/MetronomeWidget/`
- Intents: `MetronomeApp/MetronomeApp/MetronomeAppIntents.swift`

---

## Task 1: Create UpdatePriority enum and ActivityUpdateTracker with recording

**Files:**
- Create: `MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift`
- Create: `MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift`

> **Xcode note:** After creating new files, add them to the correct target in Xcode:
> - `ActivityUpdateTracker.swift` → MetronomeApp target AND MetronomeWidget target (both need it)
> - `ActivityUpdateTrackerTests.swift` → MetronomeAppTests target
>
> If using `xcodebuild`, new files in the directory are auto-discovered only if the project uses file system references. This project uses explicit file references, so you must add them to the `.xcodeproj`. Use `pbxproj` manipulation or open Xcode. Alternatively, verify with a build first and fix if needed.

### Step 1: Write the failing test

```swift
// MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift
import XCTest
@testable import MetronomeApp

@MainActor
final class ActivityUpdateTrackerTests: XCTestCase {

    func testRecordUpdateIncrementsCount() {
        let tracker = ActivityUpdateTracker()
        XCTAssertEqual(tracker.totalUpdateCount, 0)

        tracker.recordUpdate()

        XCTAssertEqual(tracker.totalUpdateCount, 1)
    }

    func testRecordUpdateTracksTimestamps() {
        let tracker = ActivityUpdateTracker()
        let now = Date()

        tracker.recordUpdate(at: now)

        XCTAssertEqual(tracker.updateTimestamps.count, 1)
        XCTAssertEqual(tracker.updateTimestamps.first, now)
    }

    func testMultipleUpdatesTracked() {
        let tracker = ActivityUpdateTracker()
        let t1 = Date()
        let t2 = t1.addingTimeInterval(1.0)
        let t3 = t2.addingTimeInterval(1.0)

        tracker.recordUpdate(at: t1)
        tracker.recordUpdate(at: t2)
        tracker.recordUpdate(at: t3)

        XCTAssertEqual(tracker.totalUpdateCount, 3)
        XCTAssertEqual(tracker.updateTimestamps.count, 3)
    }
}
```

### Step 2: Run test to verify it fails

Run: `make test-unit`
Expected: FAIL — `ActivityUpdateTracker` not defined

### Step 3: Write minimal implementation

```swift
// MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift
import Foundation
import os

enum UpdatePriority {
    case critical  // play/stop — bypasses all throttling
    case normal    // BPM changes — subject to rate limiting
}

@MainActor
final class ActivityUpdateTracker {
    private let logger = Logger(subsystem: "com.danielbutler.MetronomeApp", category: "UpdateTracker")

    private(set) var updateTimestamps: [Date] = []
    private(set) var totalUpdateCount: Int = 0

    func recordUpdate(at date: Date = Date()) {
        totalUpdateCount += 1
        updateTimestamps.append(date)
    }
}
```

### Step 4: Run test to verify it passes

Run: `make test-unit`
Expected: PASS — all 3 new tests + all 15 existing tests pass

### Step 5: Commit

```bash
git add MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift \
       MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift
git commit -m "feat: add ActivityUpdateTracker with update recording (TDD)"
```

---

## Task 2: Add rolling-window budget tracking

**Files:**
- Modify: `MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift`
- Modify: `MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift`

### Step 1: Write the failing tests

Add to `ActivityUpdateTrackerTests.swift`:

```swift
func testUpdatesInLastHourCountsCorrectly() {
    let tracker = ActivityUpdateTracker()
    let now = Date()
    let twoHoursAgo = now.addingTimeInterval(-7200)
    let thirtyMinutesAgo = now.addingTimeInterval(-1800)

    tracker.recordUpdate(at: twoHoursAgo)   // outside window
    tracker.recordUpdate(at: thirtyMinutesAgo) // inside window
    tracker.recordUpdate(at: now)              // inside window

    XCTAssertEqual(tracker.updatesInLastHour(relativeTo: now), 2)
}

func testOldTimestampsArePruned() {
    let tracker = ActivityUpdateTracker()
    let now = Date()
    let twoHoursAgo = now.addingTimeInterval(-7200)

    tracker.recordUpdate(at: twoHoursAgo)
    XCTAssertEqual(tracker.updateTimestamps.count, 1)

    // Recording a new update prunes old entries
    tracker.recordUpdate(at: now)
    XCTAssertEqual(tracker.updateTimestamps.count, 1,
                   "Old timestamp should have been pruned")
    XCTAssertEqual(tracker.updateTimestamps.first, now)
}
```

### Step 2: Run test to verify they fail

Run: `make test-unit`
Expected: FAIL — `updatesInLastHour(relativeTo:)` not defined

### Step 3: Implement rolling window and pruning

Update `ActivityUpdateTracker.swift` — add these methods:

```swift
func updatesInLastHour(relativeTo date: Date = Date()) -> Int {
    let oneHourAgo = date.addingTimeInterval(-3600)
    return updateTimestamps.filter { $0 > oneHourAgo }.count
}

func recordUpdate(at date: Date = Date()) {
    totalUpdateCount += 1
    updateTimestamps.append(date)
    pruneOldEntries(relativeTo: date)
}

private func pruneOldEntries(relativeTo date: Date) {
    let oneHourAgo = date.addingTimeInterval(-3600)
    updateTimestamps.removeAll { $0 <= oneHourAgo }
}
```

(Replace the existing `recordUpdate` — the new version adds pruning.)

### Step 4: Run test to verify they pass

Run: `make test-unit`
Expected: PASS

### Step 5: Commit

```bash
git add MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift \
       MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift
git commit -m "feat: add rolling-window budget tracking with auto-pruning (TDD)"
```

---

## Task 3: Add budget warning threshold

**Files:**
- Modify: `MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift`
- Modify: `MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift`

### Step 1: Write the failing tests

```swift
func testIsApproachingBudgetLimitDefaultThreshold() {
    let tracker = ActivityUpdateTracker()
    let now = Date()

    // Default threshold is 40. Add 39 updates — not yet approaching.
    for i in 0..<39 {
        tracker.recordUpdate(at: now.addingTimeInterval(Double(i)))
    }
    XCTAssertFalse(tracker.isApproachingBudgetLimit(at: now.addingTimeInterval(39)))

    // 40th update crosses threshold
    tracker.recordUpdate(at: now.addingTimeInterval(39))
    XCTAssertTrue(tracker.isApproachingBudgetLimit(at: now.addingTimeInterval(39)))
}

func testCustomBudgetWarningThreshold() {
    let tracker = ActivityUpdateTracker(budgetWarningThreshold: 5)
    let now = Date()

    for i in 0..<5 {
        tracker.recordUpdate(at: now.addingTimeInterval(Double(i)))
    }
    XCTAssertTrue(tracker.isApproachingBudgetLimit(at: now.addingTimeInterval(4)))
}
```

### Step 2: Run test to verify they fail

Run: `make test-unit`
Expected: FAIL — `isApproachingBudgetLimit` and `init(budgetWarningThreshold:)` not defined

### Step 3: Implement budget threshold

Update `ActivityUpdateTracker`:

```swift
@MainActor
final class ActivityUpdateTracker {
    private let logger = Logger(subsystem: "com.danielbutler.MetronomeApp", category: "UpdateTracker")

    let budgetWarningThreshold: Int

    private(set) var updateTimestamps: [Date] = []
    private(set) var totalUpdateCount: Int = 0

    init(budgetWarningThreshold: Int = 40) {
        self.budgetWarningThreshold = budgetWarningThreshold
    }

    func isApproachingBudgetLimit(at date: Date = Date()) -> Bool {
        updatesInLastHour(relativeTo: date) >= budgetWarningThreshold
    }

    // ... existing methods unchanged ...
}
```

Also update `recordUpdate` to log a warning:

```swift
func recordUpdate(at date: Date = Date()) {
    totalUpdateCount += 1
    updateTimestamps.append(date)
    pruneOldEntries(relativeTo: date)

    let hourlyCount = updatesInLastHour(relativeTo: date)
    if isApproachingBudgetLimit(at: date) {
        logger.warning("High update rate: \(hourlyCount) updates in last hour (threshold: \(self.budgetWarningThreshold))")
    } else {
        logger.info("Update #\(self.totalUpdateCount) recorded. \(hourlyCount) in last hour.")
    }
}
```

### Step 4: Run test to verify they pass

Run: `make test-unit`
Expected: PASS

### Step 5: Commit

```bash
git add MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift \
       MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift
git commit -m "feat: add budget warning threshold with configurable limit (TDD)"
```

---

## Task 4: Add shouldThrottle with configurable minimum interval

**Files:**
- Modify: `MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift`
- Modify: `MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift`

### Step 1: Write the failing tests

```swift
func testCriticalPriorityNeverThrottled() {
    let tracker = ActivityUpdateTracker(minimumInterval: 1.0)
    let now = Date()

    tracker.recordUpdate(at: now)

    // Even immediately after an update, critical is never throttled
    XCTAssertFalse(tracker.shouldThrottle(priority: .critical, at: now))
}

func testNormalPriorityThrottledWithinInterval() {
    let tracker = ActivityUpdateTracker(minimumInterval: 0.5)
    let now = Date()

    tracker.recordUpdate(at: now)

    // 0.1s later — within minimum interval — should throttle
    let soon = now.addingTimeInterval(0.1)
    XCTAssertTrue(tracker.shouldThrottle(priority: .normal, at: soon))
}

func testNormalPriorityNotThrottledAfterInterval() {
    let tracker = ActivityUpdateTracker(minimumInterval: 0.5)
    let now = Date()

    tracker.recordUpdate(at: now)

    // 0.6s later — past minimum interval — should not throttle
    let later = now.addingTimeInterval(0.6)
    XCTAssertFalse(tracker.shouldThrottle(priority: .normal, at: later))
}

func testNoUpdatesYetNeverThrottles() {
    let tracker = ActivityUpdateTracker(minimumInterval: 1.0)
    XCTAssertFalse(tracker.shouldThrottle(priority: .normal, at: Date()))
}
```

### Step 2: Run test to verify they fail

Run: `make test-unit`
Expected: FAIL — `minimumInterval` init parameter and `shouldThrottle` not defined

### Step 3: Implement shouldThrottle

Update `ActivityUpdateTracker`:

```swift
@MainActor
final class ActivityUpdateTracker {
    private let logger = Logger(subsystem: "com.danielbutler.MetronomeApp", category: "UpdateTracker")

    let minimumInterval: TimeInterval
    let budgetWarningThreshold: Int

    private(set) var updateTimestamps: [Date] = []
    private(set) var totalUpdateCount: Int = 0

    init(minimumInterval: TimeInterval = 0.3, budgetWarningThreshold: Int = 40) {
        self.minimumInterval = minimumInterval
        self.budgetWarningThreshold = budgetWarningThreshold
    }

    func shouldThrottle(priority: UpdatePriority, at date: Date = Date()) -> Bool {
        if priority == .critical { return false }
        guard let lastUpdate = updateTimestamps.last else { return false }
        return date.timeIntervalSince(lastUpdate) < minimumInterval
    }

    // ... existing methods unchanged ...
}
```

### Step 4: Run test to verify they pass

Run: `make test-unit`
Expected: PASS

### Step 5: Commit

```bash
git add MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift \
       MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift
git commit -m "feat: add shouldThrottle with priority and configurable interval (TDD)"
```

---

## Task 5: Add reset method for test isolation

**Files:**
- Modify: `MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift`
- Modify: `MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift`

### Step 1: Write the failing test

```swift
func testResetClearsAllState() {
    let tracker = ActivityUpdateTracker()
    let now = Date()

    tracker.recordUpdate(at: now)
    tracker.recordUpdate(at: now.addingTimeInterval(1))
    XCTAssertEqual(tracker.totalUpdateCount, 2)

    tracker.reset()

    XCTAssertEqual(tracker.totalUpdateCount, 0)
    XCTAssertEqual(tracker.updateTimestamps.count, 0)
}
```

### Step 2: Run test to verify it fails

Run: `make test-unit`
Expected: FAIL — `reset()` not defined

### Step 3: Implement reset

Add to `ActivityUpdateTracker`:

```swift
func reset() {
    updateTimestamps.removeAll()
    totalUpdateCount = 0
    logger.info("Tracker reset")
}
```

### Step 4: Run test to verify it passes

Run: `make test-unit`
Expected: PASS

### Step 5: Commit

```bash
git add MetronomeApp/MetronomeApp/ActivityUpdateTracker.swift \
       MetronomeApp/MetronomeAppTests/ActivityUpdateTrackerTests.swift
git commit -m "feat: add reset method to ActivityUpdateTracker for test isolation (TDD)"
```

---

## Task 6: Refactor LiveActivityManager to use ActivityUpdateTracker

This is the integration task. Replace the Timer-based throttle logic with tracker-based decisions while preserving existing behavior.

**Files:**
- Modify: `MetronomeApp/MetronomeApp/LiveActivityManager.swift`
- Modify: `MetronomeApp/MetronomeAppTests/LiveActivityManagerTests.swift`

### Step 1: Write new integration tests (they'll pass once refactored)

Add to `LiveActivityManagerTests.swift`:

```swift
func testTrackerRecordsBudgetOnUpdate() async {
    let manager = LiveActivityManager.shared
    manager.resetForTesting()

    // Force play state change so update isn't blocked by missing activity
    manager.updateActivity(bpm: 180, isPlaying: true)
    try? await Task.sleep(for: .milliseconds(50))

    XCTAssertGreaterThan(manager.tracker.totalUpdateCount, 0,
                         "Tracker should record updates dispatched by manager")
}
```

Update existing tests to use `resetForTesting()` in setUp:

```swift
@MainActor
final class LiveActivityManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        LiveActivityManager.shared.resetForTesting()
    }

    func testRapidUpdatesAreThrottled() async {
        let manager = LiveActivityManager.shared

        for bpm in 180...189 {
            manager.updateActivity(bpm: bpm, isPlaying: false)
        }

        try? await Task.sleep(for: .milliseconds(500))

        let updateCount = manager.tracker.totalUpdateCount
        XCTAssertLessThan(updateCount, 10,
                          "Rapid updates should be throttled, not sent individually")
        XCTAssertGreaterThan(updateCount, 0,
                             "At least one update should go through")
    }

    func testPlayStateUpdatesImmediately() async {
        let manager = LiveActivityManager.shared

        manager.updateActivity(bpm: 180, isPlaying: true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(manager.tracker.totalUpdateCount, 1,
                       "Play state change should update immediately")
    }

    func testTrackerRecordsBudgetOnUpdate() async {
        let manager = LiveActivityManager.shared

        manager.updateActivity(bpm: 180, isPlaying: true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertGreaterThan(manager.tracker.totalUpdateCount, 0,
                             "Tracker should record updates dispatched by manager")
    }
}
```

### Step 2: Run tests to verify the new test fails

Run: `make test-unit`
Expected: FAIL — `tracker` property and `resetForTesting()` don't exist on LiveActivityManager

### Step 3: Refactor LiveActivityManager

Replace the full contents of `LiveActivityManager.swift`:

```swift
import ActivityKit
import Foundation
import os

private let logger = Logger(subsystem: "com.danielbutler.MetronomeApp", category: "LiveActivity")

struct MetronomeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var bpm: Int
        var isPlaying: Bool
    }
}

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<MetronomeActivityAttributes>?
    private var pendingState: (bpm: Int, isPlaying: Bool)?
    private var throttleTimer: Timer?
    private var lastIsPlaying: Bool = false

    private(set) var tracker: ActivityUpdateTracker

    private init() {
        tracker = ActivityUpdateTracker()
    }

    func resetForTesting() {
        currentActivity = nil
        pendingState = nil
        throttleTimer?.invalidate()
        throttleTimer = nil
        lastIsPlaying = false
        tracker = ActivityUpdateTracker()
    }

    func startActivity(bpm: Int, isPlaying: Bool) {
        logger.info("startActivity called — bpm=\(bpm), isPlaying=\(isPlaying)")
        endActivity()

        let attributes = MetronomeActivityAttributes()
        let contentState = MetronomeActivityAttributes.ContentState(
            bpm: bpm,
            isPlaying: isPlaying
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil)
            )
            lastIsPlaying = isPlaying
            logger.info("Live Activity started successfully, id=\(self.currentActivity?.id ?? "nil")")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func updateActivity(bpm: Int, isPlaying: Bool) {
        let priority: UpdatePriority = (isPlaying != lastIsPlaying) ? .critical : .normal
        logger.info("updateActivity — bpm=\(bpm), isPlaying=\(isPlaying), priority=\(String(describing: priority))")

        guard currentActivity != nil else {
            logger.warning("No current activity, falling back to startActivity")
            startActivity(bpm: bpm, isPlaying: isPlaying)
            return
        }

        // Critical updates (play/stop) bypass throttling entirely
        if priority == .critical {
            throttleTimer?.invalidate()
            throttleTimer = nil
            pendingState = nil
            lastIsPlaying = isPlaying
            pushUpdate(bpm: bpm, isPlaying: isPlaying)
            return
        }

        // Normal updates: coalesce within minimum interval
        pendingState = (bpm, isPlaying)

        if throttleTimer == nil {
            // First update in burst: send immediately if tracker allows
            if !tracker.shouldThrottle(priority: .normal) {
                pendingState = nil
                pushUpdate(bpm: bpm, isPlaying: isPlaying)
            }

            // Start cooldown — pending updates flush when timer fires
            throttleTimer = Timer.scheduledTimer(
                withTimeInterval: tracker.minimumInterval,
                repeats: false
            ) { _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.throttleTimer = nil
                    if let pending = self.pendingState {
                        self.pendingState = nil
                        self.pushUpdate(bpm: pending.bpm, isPlaying: pending.isPlaying)
                    }
                }
            }
        }
    }

    private func pushUpdate(bpm: Int, isPlaying: Bool) {
        guard let activity = currentActivity else { return }

        let contentState = MetronomeActivityAttributes.ContentState(
            bpm: bpm,
            isPlaying: isPlaying
        )

        tracker.recordUpdate()
        let count = tracker.totalUpdateCount
        let hourly = tracker.updatesInLastHour()
        logger.info("Pushing update #\(count) (hourly: \(hourly)) — bpm=\(bpm), isPlaying=\(isPlaying)")

        Task {
            await activity.update(.init(state: contentState, staleDate: nil))
            logger.info("Activity updated — id=\(activity.id)")

            // Throttle detection: verify the update landed
            let actualState = activity.content.state
            if actualState != contentState {
                logger.warning(
                    "Possible throttle: sent bpm=\(bpm) isPlaying=\(isPlaying), " +
                    "activity shows bpm=\(actualState.bpm) isPlaying=\(actualState.isPlaying)"
                )
            }
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }
        logger.info("endActivity called — id=\(activity.id)")

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
            logger.info("Activity ended")
        }
    }
}
```

### Step 4: Run all tests to verify they pass

Run: `make test-unit`
Expected: All tests pass (existing behavior preserved + new integration test passes)

### Step 5: Commit

```bash
git add MetronomeApp/MetronomeApp/LiveActivityManager.swift \
       MetronomeApp/MetronomeAppTests/LiveActivityManagerTests.swift
git commit -m "refactor: integrate ActivityUpdateTracker into LiveActivityManager"
```

---

## Task 7: Route App Intent updates through budget tracking

The App Intents run in the widget extension process (separate from the main app). They can't share the app's `LiveActivityManager` instance in memory. However, they can use their own `ActivityUpdateTracker` instance for logging and budget awareness within the extension process.

**Files:**
- Modify: `MetronomeApp/MetronomeApp/MetronomeAppIntents.swift`

### Step 1: Write the failing test

Add new test file:
- Create: `MetronomeApp/MetronomeAppTests/IntentBudgetTrackingTests.swift`

```swift
import XCTest
@testable import MetronomeApp

@MainActor
final class IntentBudgetTrackingTests: XCTestCase {

    func testIntentTrackerRecordsUpdates() {
        let tracker = IntentUpdateTracker.shared
        tracker.reset()

        tracker.recordIntentUpdate(intent: "StartMetronome", bpm: 180, isPlaying: true)

        XCTAssertEqual(tracker.tracker.totalUpdateCount, 1)
    }

    func testIntentTrackerTracksIntentNames() {
        let tracker = IntentUpdateTracker.shared
        tracker.reset()

        tracker.recordIntentUpdate(intent: "IncrementBPM", bpm: 181, isPlaying: true)
        tracker.recordIntentUpdate(intent: "DecrementBPM", bpm: 180, isPlaying: true)

        XCTAssertEqual(tracker.tracker.totalUpdateCount, 2)
    }
}
```

### Step 2: Run test to verify it fails

Run: `make test-unit`
Expected: FAIL — `IntentUpdateTracker` not defined

### Step 3: Implement IntentUpdateTracker and wire into intents

Add `IntentUpdateTracker` to `MetronomeAppIntents.swift` (above the existing intents):

```swift
@MainActor
final class IntentUpdateTracker {
    static let shared = IntentUpdateTracker()

    let tracker = ActivityUpdateTracker()

    private init() {}

    func recordIntentUpdate(intent: String, bpm: Int, isPlaying: Bool) {
        tracker.recordUpdate()
        logger.info("\(intent) pushed update — bpm=\(bpm), isPlaying=\(isPlaying), hourly=\(self.tracker.updatesInLastHour())")
    }

    func reset() {
        tracker.reset()
    }
}
```

Update the `pushActivityUpdate` helper to use it:

```swift
private func pushActivityUpdate(bpm: Int, isPlaying: Bool, intent: String) async {
    let state = MetronomeActivityAttributes.ContentState(bpm: bpm, isPlaying: isPlaying)
    for activity in Activity<MetronomeActivityAttributes>.activities {
        await activity.update(.init(state: state, staleDate: nil))
    }
    await IntentUpdateTracker.shared.recordIntentUpdate(intent: intent, bpm: bpm, isPlaying: isPlaying)
}
```

Update each intent's `perform()` to pass the intent name:

```swift
// In StartMetronomeIntent.perform():
await pushActivityUpdate(bpm: bpm, isPlaying: true, intent: "StartMetronome")

// In StopMetronomeIntent.perform():
await pushActivityUpdate(bpm: bpm, isPlaying: false, intent: "StopMetronome")

// In IncrementBPMIntent.perform():
await pushActivityUpdate(bpm: newBPM, isPlaying: isPlaying, intent: "IncrementBPM")

// In DecrementBPMIntent.perform():
await pushActivityUpdate(bpm: newBPM, isPlaying: isPlaying, intent: "DecrementBPM")
```

### Step 4: Run all tests to verify they pass

Run: `make test-unit`
Expected: All tests pass

### Step 5: Commit

```bash
git add MetronomeApp/MetronomeApp/MetronomeAppIntents.swift \
       MetronomeApp/MetronomeAppTests/IntentBudgetTrackingTests.swift
git commit -m "feat: route App Intent updates through budget tracking with logging"
```

---

## Task 8: Final verification and cleanup

### Step 1: Run full test suite

Run: `make test-unit`
Expected: All tests pass (original 15 + new tests)

### Step 2: Verify no build warnings in widget extension

Run:
```bash
cd MetronomeApp && xcodebuild build \
  -scheme MetronomeApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "(warning:|error:|BUILD)"
```
Expected: `BUILD SUCCEEDED` with no errors

### Step 3: Review log output in Console.app

After running the app on simulator, filter Console.app by:
- Subsystem: `com.danielbutler.MetronomeApp`
- Category: `UpdateTracker` or `LiveActivity`

Verify you see:
- Update count logging on each dispatched update
- Hourly rate in log messages
- Budget warnings when rapid-tapping BPM buttons

### Step 4: Final commit

```bash
git add -A
git commit -m "chore: final verification — all tests passing, rate limiting complete"
```

---

## Summary of new/modified files

| File | Action | Purpose |
|------|--------|---------|
| `ActivityUpdateTracker.swift` | Create | Standalone throttle logic + budget tracking |
| `ActivityUpdateTrackerTests.swift` | Create | 10 unit tests for tracker |
| `LiveActivityManager.swift` | Modify | Delegate to tracker, add throttle detection |
| `LiveActivityManagerTests.swift` | Modify | Use resetForTesting(), add integration test |
| `MetronomeAppIntents.swift` | Modify | Add IntentUpdateTracker, log intent updates |
| `IntentBudgetTrackingTests.swift` | Create | 2 tests for intent budget tracking |

## Architecture gap analysis (post-implementation)

After completing the rate-limiting work, the second goal is to compare the codebase against the target architecture diagram. Key areas to evaluate:

1. **Actor-based engine (SSoT):** Currently ContentView owns all state + audio. The diagram shows a separate `MetronomeEngine` actor.
2. **Watch connectivity:** No Watch app exists yet. The diagram shows WCSession integration.
3. **AppIntent → Engine flow:** Currently intents post Darwin notifications. The diagram shows intents calling the engine directly.
4. **Live Activity update path:** Currently two paths (LiveActivityManager from app, direct `pushActivityUpdate` from intents). The diagram shows a single `Activity.update()` path from the engine.
