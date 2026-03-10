# Lifecycle Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Clean up Live Activities and audio session when the app is terminated, and clean up stale Live Activities on next launch.

**Architecture:** Add a `UIApplicationDelegateAdaptor` for best-effort `willTerminate` cleanup. Add stale activity cleanup on launch before starting a new activity. Add `deactivate()`/`activate()` methods to `AudioSessionManager`.

**Tech Stack:** SwiftUI, ActivityKit, AVFoundation, XCTest

---

### Task 1: Add `deactivate()` and `activate()` to AudioSessionManager

**Files:**
- Modify: `MetronomeApp/MetronomeApp/AudioSessionManager.swift`
- Test: `MetronomeApp/MetronomeAppTests/AudioSessionManagerTests.swift`

**Step 1: Write the failing test**

Create `MetronomeApp/MetronomeAppTests/AudioSessionManagerTests.swift`:

```swift
import XCTest
@testable import MetronomeApp

final class AudioSessionManagerTests: XCTestCase {
    func testDeactivateDoesNotThrow() {
        // Verify deactivate() exists and doesn't crash
        AudioSessionManager.shared.deactivate()
    }

    func testActivateDoesNotThrow() {
        // Verify activate() exists and doesn't crash
        AudioSessionManager.shared.activate()
    }

    func testDeactivateThenActivateRoundTrip() {
        AudioSessionManager.shared.deactivate()
        AudioSessionManager.shared.activate()
        // No crash = success. Audio session is active again.
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MetronomeApp/MetronomeApp.xcodeproj -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MetronomeAppTests/AudioSessionManagerTests 2>&1 | tail -20`
Expected: FAIL — `deactivate()` and `activate()` don't exist yet.

**Step 3: Write minimal implementation**

In `AudioSessionManager.swift`, extract setup logic into `activate()` and add `deactivate()`:

```swift
func activate() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
        try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try audioSession.setActive(true)
    } catch {
        print("Failed to activate audio session: \(error)")
    }
}

func deactivate() {
    do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
        print("Failed to deactivate audio session: \(error)")
    }
}
```

Update `private init()` to call `activate()` instead of `setupAudioSession()`. Remove `setupAudioSession()`. The full private init becomes:

```swift
private init() {
    activate()
    setupInterruptionHandling()
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MetronomeApp/MetronomeApp.xcodeproj -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MetronomeAppTests/AudioSessionManagerTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add MetronomeApp/MetronomeApp/AudioSessionManager.swift MetronomeApp/MetronomeAppTests/AudioSessionManagerTests.swift
git commit -m "feat: add activate/deactivate methods to AudioSessionManager"
```

---

### Task 2: Add `cleanupStaleActivities()` to LiveActivityManager

**Files:**
- Modify: `MetronomeApp/MetronomeApp/LiveActivityManager.swift`
- Test: `MetronomeApp/MetronomeAppTests/LiveActivityManagerTests.swift`

**Step 1: Write the failing test**

Add to `LiveActivityManagerTests.swift`:

```swift
nonisolated func testCleanupStaleActivitiesDoesNotCrash() async {
    await MainActor.run {
        let manager = LiveActivityManager.shared
        manager.resetForTesting()
        // Should succeed even when no stale activities exist
        manager.cleanupStaleActivities()
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MetronomeApp/MetronomeApp.xcodeproj -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MetronomeAppTests/LiveActivityManagerTests/testCleanupStaleActivitiesDoesNotCrash 2>&1 | tail -20`
Expected: FAIL — `cleanupStaleActivities()` doesn't exist.

**Step 3: Write minimal implementation**

Add to `LiveActivityManager.swift`:

```swift
func cleanupStaleActivities() {
    let staleActivities = Activity<MetronomeActivityAttributes>.activities
    guard !staleActivities.isEmpty else {
        logger.info("No stale activities to clean up")
        return
    }
    logger.info("Cleaning up \(staleActivities.count) stale activit\(staleActivities.count == 1 ? "y" : "ies")")
    for activity in staleActivities {
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MetronomeApp/MetronomeApp.xcodeproj -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MetronomeAppTests/LiveActivityManagerTests/testCleanupStaleActivitiesDoesNotCrash 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add MetronomeApp/MetronomeApp/LiveActivityManager.swift MetronomeApp/MetronomeAppTests/LiveActivityManagerTests.swift
git commit -m "feat: add cleanupStaleActivities to LiveActivityManager"
```

---

### Task 3: Add AppDelegate with willTerminate cleanup

**Files:**
- Modify: `MetronomeApp/MetronomeApp/MetronomeAppApp.swift`

**Step 1: Add AppDelegate class and wire it up**

Replace the contents of `MetronomeAppApp.swift` with:

```swift
import SwiftUI
import os

private let logger = Logger(subsystem: "com.danielbutler.MetronomeApp", category: "AppLifecycle")

class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        logger.info("applicationWillTerminate — cleaning up")
        Task { @MainActor in
            LiveActivityManager.shared.endActivity()
        }
        AudioSessionManager.shared.deactivate()
    }
}

@main
struct MetronomeAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Initialize audio session for background playback
        _ = AudioSessionManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Step 2: Run all tests to verify nothing is broken**

Run: `xcodebuild test -project MetronomeApp/MetronomeApp.xcodeproj -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add MetronomeApp/MetronomeApp/MetronomeAppApp.swift
git commit -m "feat: add AppDelegate for willTerminate lifecycle cleanup"
```

---

### Task 4: Clean up stale activities on launch

**Files:**
- Modify: `MetronomeApp/MetronomeApp/ContentView.swift`

**Step 1: Add stale activity cleanup before starting new activity**

In `ContentView.swift`, in the `.onAppear` block, add `cleanupStaleActivities()` before `startActivity()`. The block becomes:

```swift
.onAppear {
    logger.info("onAppear — resetting state to defaults")
    // Always start fresh
    bpm = 180
    volume = 0.4
    isPlaying = false

    // Reset shared preferences
    sharedState.bpm = 180
    sharedState.volume = 0.4

    setupAudioEngine()
    startObservingSharedState()

    // Clean up any stale activities from a previous session, then start fresh
    Task { @MainActor in
        LiveActivityManager.shared.cleanupStaleActivities()
        LiveActivityManager.shared.startActivity(bpm: bpm, isPlaying: false)
    }
}
```

**Step 2: Run all tests to verify nothing is broken**

Run: `xcodebuild test -project MetronomeApp/MetronomeApp.xcodeproj -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add MetronomeApp/MetronomeApp/ContentView.swift
git commit -m "feat: clean up stale Live Activities on app launch"
```

---

### Task 5: Final verification

**Step 1: Run the full test suite**

Run: `xcodebuild test -project MetronomeApp/MetronomeApp.xcodeproj -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests PASS

**Step 2: Build for device to verify no compilation issues**

Run: `xcodebuild build -project MetronomeApp/MetronomeApp.xcodeproj -scheme MetronomeApp -destination generic/platform=iOS 2>&1 | tail -10`
Expected: BUILD SUCCEEDED
