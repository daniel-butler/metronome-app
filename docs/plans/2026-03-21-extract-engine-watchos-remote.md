# Implementation Plan: Extract MetronomeEngine + watchOS Remote

## Context

The metronome app ("180") has all engine logic (AVAudioEngine, Timer, BPM state, tick scheduling) embedded in ContentView.swift (417 lines). This makes it impossible to reuse the metronome logic for a watchOS remote. The watchOS app will be a dumb remote — 3 buttons (plus, minus, start/stop) and SPM display — communicating with the phone via WatchConnectivity.

## Architecture After

```
MetronomeEngine (@Observable, @MainActor)
├── Owns: bpm, isPlaying, volume, AVAudioEngine, Timer, debounce
├── Owns: StateChangeObserver (reacts to widget commands)
├── Calls: LiveActivityManager (on state changes)
├── Calls: SharedMetronomeState (persists bpm/volume)
├── Calls: WatchSessionManager (sends state to watch)
│
ContentView (thin UI shell)
├── Observes: MetronomeEngine
├── Owns: UI-only state (alert, text field)
│
WatchSessionManager (iOS side)
├── WCSessionDelegate
├── Receives: commands from watch → drives MetronomeEngine
├── Sends: state updates to watch when engine changes
│
watchOS App
├── WatchSessionManager (watch side, @Observable)
│   ├── Sends: commands to phone
│   └── Receives: state (bpm, isPlaying) from phone
├── WatchContentView
│   ├── SPM display
│   └── 3 buttons: minus, start/stop, plus
```

## Phases

---

### Phase 1: Extract MetronomeEngine (pure refactor, no new features)

#### Task 1.1: Create MetronomeEngine.swift

Create `MetronomeApp/MetronomeEngine.swift`.

```swift
import AVFoundation
import os

@Observable
@MainActor
final class MetronomeEngine {
    // Published state (observed by ContentView)
    private(set) var bpm: Int = 180
    private(set) var isPlaying: Bool = false
    var volume: Float = 0.4

    // BPM constraints
    static let bpmRange = 150...230
    var canIncrementBPM: Bool { bpm < Self.bpmRange.upperBound }
    var canDecrementBPM: Bool { bpm > Self.bpmRange.lowerBound }

    // Audio internals
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioBuffer: AVAudioPCMBuffer?
    private var tickTimer: Timer?
    private var bpmDebounceTimer: Timer?
    private var pendingBPM: Int?

    // Cross-process
    private let sharedState = SharedMetronomeState.shared
    private var stateObserver: StateChangeObserver?
}
```

Move these methods from ContentView → MetronomeEngine:
- `setupAudioEngine()` → called from `start()` or an explicit `setup()`
- `loadTickSound()` → private, called during setup
- `cleanupAudio()` → `teardown()`
- `calculateInterval(bpm:)` → private
- `startMetronome()` → private (called by `start()`)
- `stopMetronome()` → private (called by `stop()`)
- `togglePlayback()` → public
- `incrementBPM()` → public
- `decrementBPM()` → public
- `handleBPMChange()` → private
- `updateVolume(_:)` → `setVolume(_:)`
- `startObservingSharedState()` / `stopObservingSharedState()` → private, called in setup/teardown
- `handleSharedStateChange()` → private
- `handlePlayCommand()` → private
- `handleStopCommand()` → private

Add a new method:
- `setBPM(_ newBPM: Int)` — clamps to range, updates shared state, handles debounce. Used by commitBPM in ContentView and by WatchSessionManager later.
- `syncFromSharedState()` — reads bpm from SharedMetronomeState, updates if different. Called on scene phase active.
- `setup()` — initializes audio engine + state observer. Called from ContentView.onAppear.
- `teardown()` — cleans up audio + observer. Called from ContentView.onDisappear.

Each state-changing method calls `LiveActivityManager.shared.updateActivity(bpm:isPlaying:)` internally — ContentView no longer touches LiveActivityManager.

**Files modified:** None (new file)
**Files read:** ContentView.swift (source of moved code)
**Risk:** Low — creating new file, no existing code changes yet

#### Task 1.2: Slim down ContentView.swift

Replace all engine-related `@State` properties with a single:
```swift
@State private var engine = MetronomeEngine()
```

Remove from ContentView:
- `@State bpm`, `isPlaying`, `volume` → read from `engine.bpm`, etc.
- `@State audioEngine`, `playerNode`, `audioBuffer`, `timer` → gone
- `@State bpmDebounceTimer`, `pendingBPM` → gone
- `@State stateObserver` → gone
- `sharedState` property → gone
- All methods in MARK: Audio Engine Setup → gone
- All methods in MARK: Metronome Control → gone
- All methods in MARK: BPM Control (except commitBPM which calls engine.setBPM) → gone
- All methods in MARK: Volume Control → gone
- All methods in MARK: Shared State Observer → gone

Keep in ContentView:
- `@State showBPMAlert`, `@State bpmText` (UI-only)
- `@Environment(\.scenePhase)` — onChange calls `engine.syncFromSharedState()`
- `body` — same layout, but reads `engine.bpm`, `engine.isPlaying`, calls `engine.incrementBPM()`, etc.
- `commitBPM()` — parses text, calls `engine.setBPM(clamped)`
- `onAppear` → `engine.setup(); LiveActivityManager.shared.cleanupStaleActivities(); LiveActivityManager.shared.startActivity(...)`
- `onDisappear` → `engine.teardown()`

ContentView should drop from ~417 lines to ~120 lines.

**Files modified:** ContentView.swift
**Depends on:** Task 1.1
**Risk:** Medium — large refactor of the main view

#### Task 1.3: Update MetronomeAppApp.swift

No changes needed if MetronomeEngine is created as `@State` in ContentView. The AppDelegate termination cleanup stays as-is (it directly uses Activity<> APIs and AudioSessionManager, not the engine).

If we later need the engine accessible from MetronomeAppApp (for WatchConnectivity), we'll promote it then (Phase 2).

**Files modified:** Possibly none
**Depends on:** Task 1.2

#### Task 1.4: Verify existing tests still pass

Run `make test-unit`. The existing tests cover:
- SharedMetronomeState (no changes)
- LiveActivityManager (no changes)
- ActivityUpdateTracker (no changes)
- StateChangeObserver (no changes)
- ContentView tests (may need updates if they reference removed state)

Fix any broken tests. Consider adding basic MetronomeEngine tests (e.g., incrementBPM clamps at 230, decrementBPM clamps at 150, setBPM clamps to range).

**Files modified:** Test files as needed
**Depends on:** Task 1.2
**Risk:** Low

---

### Phase 2: WatchConnectivity (iOS side)

#### Task 2.1: Promote MetronomeEngine to app-level ownership

Move MetronomeEngine creation from ContentView `@State` to MetronomeAppApp. Pass it to ContentView via `@Environment` or init parameter.

This is needed because WatchSessionManager (next task) needs a reference to the engine to execute commands from the watch.

```swift
@main
struct MetronomeAppApp: App {
    @State private var engine = MetronomeEngine()

    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
        }
    }
}
```

ContentView changes from `@State private var engine` to accepting it via init or `@Environment`.

**Files modified:** MetronomeAppApp.swift, ContentView.swift
**Depends on:** Phase 1
**Risk:** Low

#### Task 2.2: Create WatchSessionManager (iOS side)

Create `MetronomeApp/WatchSessionManager.swift`.

```swift
import WatchConnectivity
import os

@MainActor
final class WatchSessionManager: NSObject, WCSessionDelegate {
    private let engine: MetronomeEngine

    init(engine: MetronomeEngine) { ... }

    func activate() { WCSession.default.delegate = self; WCSession.default.activate() }

    // Receive commands from watch
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // "command": "start" | "stop" | "incrementBPM" | "decrementBPM"
        // Route to engine methods
    }

    // Send state to watch (called by engine on state changes)
    func sendStateToWatch(bpm: Int, isPlaying: Bool) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["bpm": bpm, "isPlaying": isPlaying], ...)
    }
}
```

**Integration with MetronomeEngine:** Add an optional `onStateChange` callback to MetronomeEngine that WatchSessionManager subscribes to, or use Observation framework to watch for changes.

**Files modified:** New file + MetronomeEngine.swift (add callback/notification)
**Depends on:** Task 2.1
**Risk:** Medium — WatchConnectivity has many edge cases

#### Task 2.3: Wire WatchSessionManager into app lifecycle

Activate the session in MetronomeAppApp. Pass engine reference.

**Files modified:** MetronomeAppApp.swift
**Depends on:** Task 2.2
**Risk:** Low

---

### Phase 3: watchOS App Target

#### Task 3.1: Create watchOS target in Xcode (manual step)

In Xcode:
1. File → New → Target → watchOS → App
2. Product name: "MetronomeWatch" (or "180 Watch")
3. Bundle ID: `com.danielbutler.MetronomeApp.watchkitapp`
4. Interface: SwiftUI
5. Watch-only app: NO (companion to iOS app)
6. Embed in: MetronomeApp

This creates:
- `MetronomeWatch/` directory
- `MetronomeWatchApp.swift` (entry point)
- `ContentView.swift` (watch UI)
- New target in xcodeproj

**Files modified:** .xcodeproj (Xcode manages this)
**Depends on:** None (can be done in parallel with Phase 1-2)
**Risk:** Low

#### Task 3.2: Create WatchSessionManager (watch side)

Create `MetronomeWatch/WatchSessionManager.swift`.

```swift
import WatchConnectivity
import os

@Observable
@MainActor
final class WatchSessionManager: NSObject, WCSessionDelegate {
    var bpm: Int = 180
    var isPlaying: Bool = false
    var isReachable: Bool = false

    func activate() { ... }

    // Send commands to phone
    func sendCommand(_ command: String) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["command": command], ...)
    }

    // Receive state from phone
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Update bpm, isPlaying from message
    }

    // Convenience
    func start() { sendCommand("start") }
    func stop() { sendCommand("stop") }
    func incrementBPM() { sendCommand("incrementBPM") }
    func decrementBPM() { sendCommand("decrementBPM") }
}
```

**Files modified:** New file in MetronomeWatch/
**Depends on:** Task 3.1
**Risk:** Low

#### Task 3.3: Create watch UI

Create/edit `MetronomeWatch/ContentView.swift`:

```swift
struct WatchContentView: View {
    @State private var session = WatchSessionManager()

    var body: some View {
        VStack(spacing: 12) {
            // SPM display
            Text("\(session.bpm)")
                .font(.system(size: 48, weight: .bold))
            Text("SPM")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Controls: same layout as Live Activity
            HStack(spacing: 16) {
                Button { session.decrementBPM() } label: {
                    Image(systemName: "minus")
                }

                Button { session.isPlaying ? session.stop() : session.start() } label: {
                    Image(systemName: session.isPlaying ? "stop.fill" : "play.fill")
                }

                Button { session.incrementBPM() } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { session.activate() }
    }
}
```

**Files modified:** MetronomeWatch/ContentView.swift
**Depends on:** Task 3.2
**Risk:** Low

#### Task 3.4: Handle unreachable phone

When `WCSession.default.isReachable` is false, the watch should:
- Show current last-known BPM (grayed out)
- Disable buttons or show "Phone not connected" indicator
- Queue commands via `transferUserInfo` as fallback (optional)

**Files modified:** WatchContentView, WatchSessionManager
**Depends on:** Task 3.3
**Risk:** Low

---

## Task Dependency Graph

```
Phase 1 (refactor):
  1.1 Create MetronomeEngine
   └→ 1.2 Slim ContentView
       └→ 1.3 Update App entry (if needed)
           └→ 1.4 Verify tests

Phase 2 (WatchConnectivity iOS):
  1.4 ─→ 2.1 Promote engine to app level
           └→ 2.2 Create WatchSessionManager (iOS)
               └→ 2.3 Wire into app lifecycle

Phase 3 (watchOS app):
  3.1 Create target (parallel, anytime)
  2.3 + 3.1 ─→ 3.2 WatchSessionManager (watch)
                 └→ 3.3 Watch UI
                     └→ 3.4 Handle unreachable
```

## Out of Scope

- Haptic tick on watch (deferred per user decision)
- Standalone watch metronome (watch is remote-only)
- Renaming internal module/target names (display name already "180")
- Watch complications
- Watch app running independently without phone
