# Lifecycle Cleanup Design

## Problem

The app's singletons (LiveActivityManager, AudioSessionManager) are never cleaned up when the app is terminated. Live Activities persist on the lock screen after the app is killed. The audio session is never deactivated.

## Constraints

- The app plays background audio, so `scenePhase == .background` is normal operation — cleanup cannot happen there.
- iOS provides no reliable "app is closing" callback. `willTerminateNotification` only fires when the app is terminated from the foreground.
- `scenePhase` has known limitations and does not cover termination.

## Design

Two-pronged approach: best-effort cleanup on termination + guaranteed cleanup on next launch.

### 1. Cleanup stale Live Activities on launch

When the app launches, enumerate all existing Live Activities from a previous session and end them before starting fresh.

```swift
// In MetronomeAppApp.init() or ContentView.onAppear, before starting a new activity
for activity in Activity<MetronomeActivityAttributes>.activities {
    Task { await activity.end(nil, dismissalPolicy: .immediate) }
}
```

This mirrors the existing `resetForTesting()` logic in LiveActivityManager, which already iterates and ends all activities.

### 2. UIApplicationDelegateAdaptor for willTerminate

Add an AppDelegate via `UIApplicationDelegateAdaptor` for best-effort cleanup when the app is terminated from the foreground (e.g., user swipes up in app switcher while the app is visible).

```swift
class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        LiveActivityManager.shared.endActivity()
        AudioSessionManager.shared.deactivate()
    }
}
```

Wire it up in the App struct:

```swift
@main
struct MetronomeAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // ...
}
```

### 3. AudioSessionManager.deactivate()

Add a `deactivate()` method to AudioSessionManager that calls `AVAudioSession.sharedInstance().setActive(false)`. Add a corresponding `activate()` method that extracts the existing setup logic for reuse.

## Files changed

- `MetronomeAppApp.swift` — add AppDelegate adaptor, add stale activity cleanup on init
- `AudioSessionManager.swift` — add `deactivate()` and `activate()` methods
- `LiveActivityManager.swift` — extract stale activity cleanup into a reusable method (or reuse `resetForTesting` logic)

## What this does NOT change

- No DI framework added
- No protocol/environment refactor (deferred for future testability work)
- No changes to `scenePhase` `.background` handling — the app continues to play audio in background as before
- Service classes remain singletons with `static let shared`
