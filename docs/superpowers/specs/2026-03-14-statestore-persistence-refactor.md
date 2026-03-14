# StateStore Persistence Refactor

## Problem

`SharedMetronomeState` works but has four structural problems:

1. **Not injectable.** `MetronomeEngine` hardcodes `SharedMetronomeState.shared`. Tests leak BPM through real UserDefaults, causing flaky UI tests and fragile unit tests that depend on execution order.
2. **Split observer.** `StateChangeObserver` exists only to receive the Darwin notifications that `SharedMetronomeState` sends. Two halves of the same IPC channel live in separate classes, and `MetronomeEngine` must coordinate both.
3. **Unsafe concurrency.** `nonisolated(unsafe)` suppresses the compiler instead of proving thread safety. The `@Sendable` conformance relies on UserDefaults being thread-safe, but the compiler cannot verify this.
4. **Scattered `synchronize()` calls.** Callers must remember to force-read from disk before accessing properties. Cache coherence is the store's job, not the consumer's.

## Solution

Replace `SharedMetronomeState` and `StateChangeObserver` with a `StateStore` protocol, a production `SharedStateStore`, and a test-only `InMemoryStateStore`.

## Design

### Protocol

```swift
@MainActor
protocol StateStore: Sendable {
    var bpm: Int { get set }
    var isPlaying: Bool { get set }
    var volume: Float { get set }

    /// Emits when another process changes state or issues a command.
    var externalChanges: AnyPublisher<StoreEvent, Never> { get }

    /// Posts a cross-process play or stop command.
    func postCommand(_ command: StateStoreCommand)

    /// Forces a read from the backing store (disk, app group).
    func synchronize()

    /// Tells widgets to reload their timelines.
    func notifyWidgetUpdate()
}

enum StateStoreCommand {
    case start
    case stop
}

enum StoreEvent {
    /// Another process changed a persisted value (e.g. BPM from widget).
    case stateChanged
    /// Another process issued a playback command.
    case command(StateStoreCommand)
}
```

**Why `StoreEvent` instead of `PlaybackState`:** The current code handles state changes and commands differently. `handleSharedStateChange` reads BPM from UserDefaults and compares; `handlePlayCommand`/`handleStopCommand` mutate playback directly. A single `PlaybackState` publisher cannot represent "start the metronome" vs "the BPM changed." The enum preserves this distinction.

### `SharedStateStore` (production)

Replaces both `SharedMetronomeState` and `StateChangeObserver`.

- **Persistence:** UserDefaults app group (`group.com.danielbutler.MetronomeApp`). The mechanism is correct for three scalar values shared across process boundaries.
- **IPC send:** Property setters on `bpm` post the `stateChanged` Darwin notification. `postCommand(_:)` posts `commandStart`/`commandStop` Darwin notifications. Setting `isPlaying` does *not* post a notification — it is a local write. Widget intents call `postCommand(_:)` to trigger playback changes; the command handler in `MetronomeEngine` sets `isPlaying` itself.
- **IPC receive:** Owns its own Darwin notification observers. Calls `synchronize()` internally before emitting `.stateChanged`, so consumers never manage cache coherence.
- **Concurrency:** `@MainActor` isolation throughout. Eliminates `nonisolated(unsafe)`.
- **Singleton:** `static let shared` remains for widget intents, which run in a separate process without `MetronomeEngine`.
- **`MetronomeNotification` enum:** Becomes a private implementation detail inside `SharedStateStore`. Widget intents no longer reference notification names directly — they call `postCommand(_:)` instead.

### `InMemoryStateStore` (tests)

- Stored properties, no UserDefaults, no Darwin notifications.
- `externalChanges` backed by a `PassthroughSubject<StoreEvent, Never>` that tests push values into to simulate external changes.
- Lives in the test target only.

### `PlaybackState` (rename)

Rename `MetronomeState` to `PlaybackState`. This struct captures the live snapshot (bpm + isPlaying) published by the engine's Combine pipeline. The name distinguishes it from persisted state.

Note: `MPNowPlayingInfoCenter.default().playbackState` is a property (not a type) in MediaPlayer, so there is no type collision.

### Consumer Changes

**`MetronomeEngine`:**
- Accepts `StateStore` in `init` (defaults to `SharedStateStore.shared`).
- Subscribes to `store.externalChanges` instead of wiring a `StateChangeObserver`. Routes `.stateChanged` to the existing sync logic and `.command` to play/stop handlers.
- Removes all `synchronize()` calls — the store handles this internally.
- `syncFromSharedState()` is removed. The store auto-syncs before emitting `.stateChanged`. For returning from background (where Darwin notifications may be missed), `MetronomeEngine` calls `store.synchronize()` once in `ensureReady()` — the store reads from disk and emits `.stateChanged` if the value differs.

**Widget intents (`MetronomeAppIntents.swift`):**
- Use `SharedStateStore.shared` directly.
- Call `store.postCommand(.start)` instead of `SharedMetronomeState.postCommand(MetronomeNotification.commandStart)`.
- Set `store.bpm` / `store.isPlaying` for cross-process state, as today.

**`MetronomeAppApp.swift`:**
- No source changes. `MetronomeEngine()` uses the default `SharedStateStore.shared` parameter.

**`ContentView.swift`:**
- Remove `engine.syncFromSharedState()` from `onChange(of: scenePhase)`. The store's `externalChanges` publisher handles this.

## Files

| File | Change |
|------|--------|
| `SharedMetronomeState.swift` | **Delete.** Replaced by `StateStore.swift` + `SharedStateStore.swift`. |
| `StateChangeObserver.swift` | **Delete.** Folded into `SharedStateStore`. |
| `MetronomeEngine.swift` | Inject `StateStore`. Subscribe to `externalChanges`. Remove `synchronize()` calls, `StateChangeObserver` wiring, and `syncFromSharedState()`. Rename `MetronomeState` to `PlaybackState`. |
| `MetronomeAppIntents.swift` | Update to `SharedStateStore.shared` and `postCommand(_:)` API. |
| `ContentView.swift` | Remove `syncFromSharedState()` call in `onChange(of: scenePhase)`. |
| `StateStore.swift` | **New.** Protocol + `StateStoreCommand` + `StoreEvent` enums. |
| `SharedStateStore.swift` | **New.** Production implementation with `MetronomeNotification` as private detail. |
| `InMemoryStateStore.swift` | **New.** Test target only. |
| `SharedMetronomeStateTests.swift` | **Rewrite.** Test `SharedStateStore` against protocol contract. Include command round-trip test. |
| `StateChangeObserverTests.swift` | **Delete.** Covered by `SharedStateStore` tests. |
| `MetronomeNotificationTests.swift` | Update references to `SharedStateStore` internals or delete if fully private. |
| `MetronomeEngineTests.swift` | Inject `InMemoryStateStore`. Fix test isolation. |
| `NowPlayingTests.swift` | Inject `InMemoryStateStore` into `MetronomeEngine`. |
| `PhoneSessionManagerTests.swift` | Inject `InMemoryStateStore` into `MetronomeEngine`. |
| `PhoneSessionManager.swift` | Update `PlaybackState` references if needed. |

## Ordering

This refactor follows a separate module rename from `MetronomeApp` to `OneEighty`. The rename happens first as a mechanical prerequisite and is not covered in this spec.

## Verification

1. All unit tests pass with `InMemoryStateStore` injected — no UserDefaults leakage between tests.
2. `SharedStateStore` tests verify persistence round-trips, Darwin notification delivery, and command round-trip (`postCommand(.start)` emits `.command(.start)` on `externalChanges`).
3. Grep for `SharedMetronomeState` — zero hits in source.
4. Grep for `StateChangeObserver` — zero hits in source.
5. Grep for `nonisolated(unsafe)` in `SharedStateStore` — zero hits.
6. Grep for `synchronize()` in `MetronomeEngine` — zero hits (store handles it).
7. Grep for `syncFromSharedState` — zero hits in source.
8. Widget intents build and function (manual test: toggle from Lock Screen widget).
