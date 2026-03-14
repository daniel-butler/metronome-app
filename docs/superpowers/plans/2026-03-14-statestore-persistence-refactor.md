# StateStore Persistence Refactor — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `SharedMetronomeState` + `StateChangeObserver` with an injectable `StateStore` protocol, production `SharedStateStore`, and test-only `InMemoryStateStore`.

**Architecture:** Protocol-based dependency injection. `SharedStateStore` folds in Darwin notification observation (previously split across `StateChangeObserver`). `MetronomeEngine` accepts any `StateStore` conformer, defaulting to `SharedStateStore.shared` in production. Tests inject `InMemoryStateStore` for full isolation.

**Tech Stack:** Swift, Combine, UserDefaults (app group), CFNotificationCenter (Darwin notifications)

**Spec:** `docs/superpowers/specs/2026-03-14-statestore-persistence-refactor.md`

**Prerequisite:** Module rename `MetronomeApp` → `OneEighty` (separate effort, not covered here). This plan uses current module names. Update `@testable import` statements after the rename.

---

## Task 1: Create `StateStore` protocol and enums

**Files:**
- Create: `MetronomeApp/StateStore.swift`

- [ ] **Step 1: Create the protocol file**

```swift
//
//  StateStore.swift
//  MetronomeApp
//
//  Protocol for persisting and observing metronome state across processes.
//

import Combine

enum StateStoreCommand: Equatable {
    case start
    case stop
}

enum StoreEvent: Equatable {
    /// Another process changed a persisted value (e.g. BPM from widget).
    case stateChanged
    /// Another process issued a playback command.
    case command(StateStoreCommand)
}

@MainActor
protocol StateStore: AnyObject, Sendable {
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
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add MetronomeApp/StateStore.swift
git commit -m "refactor: add StateStore protocol and event enums"
```

---

## Task 2: Rename `MetronomeState` → `PlaybackState`

**Files:**
- Modify: `MetronomeApp/MetronomeEngine.swift` (lines 16-19, 54, 57, 64)
- Modify: `MetronomeAppTests/MetronomeEngineTests.swift` (lines 125-196 — all `MetronomeState` references)
- Modify: `MetronomeApp/PhoneSessionManager.swift` (no direct references — uses publisher but doesn't name the type)

- [ ] **Step 1: Rename struct in `MetronomeEngine.swift`**

In `MetronomeEngine.swift`, rename the struct definition and all 4 references:

```swift
// Line 16-18: struct definition
struct PlaybackState: Equatable {
    let bpm: Int
    let isPlaying: Bool
}

// Line 54: subject type
private let stateSubject = CurrentValueSubject<PlaybackState, Never>(PlaybackState(bpm: 180, isPlaying: false))

// Line 57: publisher return type
var statePublisher: AnyPublisher<PlaybackState, Never> {

// Line 64: in notifyStateChanged()
stateSubject.send(PlaybackState(bpm: bpm, isPlaying: isPlaying))
```

- [ ] **Step 2: Rename in test file**

In `MetronomeEngineTests.swift`, replace all `MetronomeState` with `PlaybackState` (approximately 15 occurrences across lines 125-196).

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests -quiet 2>&1 | grep "failed" | head -10`
Expected: No output (all pass)

- [ ] **Step 4: Commit**

```bash
git add MetronomeApp/MetronomeEngine.swift MetronomeAppTests/MetronomeEngineTests.swift
git commit -m "refactor: rename MetronomeState to PlaybackState"
```

---

## Task 3: Create `InMemoryStateStore` (test target)

**Files:**
- Create: `MetronomeAppTests/InMemoryStateStore.swift`

- [ ] **Step 1: Write the InMemoryStateStore test**

Add to `MetronomeAppTests/MetronomeEngineTests.swift` at the end of the file (before the closing `}`):

```swift
    // MARK: - InMemoryStateStore

    func testInMemoryStateStoreDefaults() {
        let store = InMemoryStateStore()
        XCTAssertEqual(store.bpm, 180)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.volume, 0.4)
    }

    func testInMemoryStateStoreRoundTrips() {
        let store = InMemoryStateStore()
        store.bpm = 200
        store.isPlaying = true
        store.volume = 0.8
        XCTAssertEqual(store.bpm, 200)
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(store.volume, 0.8)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests/MetronomeEngineTests/testInMemoryStateStoreDefaults -quiet 2>&1 | tail -5`
Expected: FAIL (cannot find `InMemoryStateStore`)

- [ ] **Step 3: Create InMemoryStateStore**

Create `MetronomeAppTests/InMemoryStateStore.swift`:

```swift
//
//  InMemoryStateStore.swift
//  MetronomeAppTests
//
//  In-memory StateStore for tests. No UserDefaults, no Darwin notifications.
//

import Combine
@testable import MetronomeApp

@MainActor
final class InMemoryStateStore: StateStore {
    var bpm: Int = 180
    var isPlaying: Bool = false
    var volume: Float = 0.4

    private let externalChangesSubject = PassthroughSubject<StoreEvent, Never>()

    var externalChanges: AnyPublisher<StoreEvent, Never> {
        externalChangesSubject.eraseToAnyPublisher()
    }

    /// Tests call this to simulate an external process changing state.
    func simulateExternalChange(_ event: StoreEvent) {
        externalChangesSubject.send(event)
    }

    func postCommand(_ command: StateStoreCommand) {
        // No-op in tests — no cross-process IPC
    }

    func synchronize() {
        // No-op in tests — no disk backing store
    }

    func notifyWidgetUpdate() {
        // No-op in tests — no WidgetKit
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests/MetronomeEngineTests/testInMemoryStateStoreDefaults -quiet 2>&1 | tail -5`
Expected: PASS

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests/MetronomeEngineTests/testInMemoryStateStoreRoundTrips -quiet 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add MetronomeAppTests/InMemoryStateStore.swift MetronomeAppTests/MetronomeEngineTests.swift
git commit -m "test: add InMemoryStateStore for isolated engine testing"
```

---

## Task 4: Create `SharedStateStore` (production)

This task builds the production implementation that replaces both `SharedMetronomeState` and `StateChangeObserver`. It folds Darwin notification observation into the store.

**Files:**
- Create: `MetronomeApp/SharedStateStore.swift`
- Modify: `MetronomeAppTests/SharedMetronomeStateTests.swift` (rewrite)

- [ ] **Step 1: Write failing tests for SharedStateStore**

Rewrite `MetronomeAppTests/SharedMetronomeStateTests.swift`:

```swift
//
//  SharedStateStoreTests.swift
//  MetronomeAppTests
//
//  Tests for SharedStateStore persistence and Darwin notification delivery.
//

import Combine
import XCTest
@testable import MetronomeApp

@MainActor
final class SharedStateStoreTests: XCTestCase {

    private var store: SharedStateStore!
    private var testDefaults: UserDefaults!

    override func setUp() {
        testDefaults = UserDefaults(suiteName: "test.SharedStateStore.\(UUID().uuidString)")!
        store = SharedStateStore(userDefaults: testDefaults)
    }

    override func tearDown() {
        store = nil
        if let suiteName = testDefaults?.suiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        testDefaults = nil
    }

    // MARK: - Defaults

    func testBPMDefaultsTo180() {
        XCTAssertEqual(store.bpm, 180)
    }

    func testIsPlayingDefaultsToFalse() {
        XCTAssertFalse(store.isPlaying)
    }

    func testVolumeDefaultsTo04() {
        XCTAssertEqual(store.volume, 0.4)
    }

    // MARK: - Persistence

    func testBPMPersists() {
        store.bpm = 200
        let store2 = SharedStateStore(userDefaults: testDefaults)
        store2.synchronize()
        XCTAssertEqual(store2.bpm, 200)
    }

    func testIsPlayingPersists() {
        store.isPlaying = true
        let store2 = SharedStateStore(userDefaults: testDefaults)
        store2.synchronize()
        XCTAssertTrue(store2.isPlaying)
    }

    func testVolumePersists() {
        store.volume = 0.8
        let store2 = SharedStateStore(userDefaults: testDefaults)
        store2.synchronize()
        XCTAssertEqual(store2.volume, 0.8)
    }

    // MARK: - Command Round-Trip

    func testPostCommandStartEmitsOnExternalChanges() {
        var events: [StoreEvent] = []
        let cancellable = store.externalChanges.sink { events.append($0) }

        store.postCommand(.start)

        let expectation = expectation(description: "command delivered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let commandEvents = events.compactMap { event -> StateStoreCommand? in
            if case .command(let cmd) = event { return cmd }
            return nil
        }
        XCTAssertTrue(commandEvents.contains(.start))

        cancellable.cancel()
    }

    func testPostCommandStopEmitsOnExternalChanges() {
        var events: [StoreEvent] = []
        let cancellable = store.externalChanges.sink { events.append($0) }

        store.postCommand(.stop)

        let expectation = expectation(description: "command delivered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let commandEvents = events.compactMap { event -> StateStoreCommand? in
            if case .command(let cmd) = event { return cmd }
            return nil
        }
        XCTAssertTrue(commandEvents.contains(.stop))

        cancellable.cancel()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests/SharedStateStoreTests -quiet 2>&1 | tail -5`
Expected: FAIL (cannot find `SharedStateStore`)

- [ ] **Step 3: Create SharedStateStore**

Create `MetronomeApp/SharedStateStore.swift`:

```swift
//
//  SharedStateStore.swift
//  MetronomeApp
//
//  Production StateStore backed by UserDefaults app group and Darwin notifications.
//  Replaces SharedMetronomeState and StateChangeObserver.
//

import Combine
import os

#if canImport(WidgetKit)
import WidgetKit
#endif

private let logger = Logger(subsystem: "com.danielbutler.MetronomeApp", category: "SharedStateStore")

private enum DarwinNotification {
    static let stateChanged = "com.danielbutler.MetronomeApp.stateChanged"
    static let commandStart = "com.danielbutler.MetronomeApp.command.start"
    static let commandStop = "com.danielbutler.MetronomeApp.command.stop"
}

@MainActor
final class SharedStateStore: StateStore {
    static let shared = SharedStateStore()

    private nonisolated let defaults: UserDefaults
    private nonisolated let observerPointer: UnsafeRawPointer

    private let externalChangesSubject = PassthroughSubject<StoreEvent, Never>()

    var externalChanges: AnyPublisher<StoreEvent, Never> {
        externalChangesSubject.eraseToAnyPublisher()
    }

    var bpm: Int {
        get { defaults.object(forKey: "bpm") as? Int ?? 180 }
        set {
            defaults.set(newValue, forKey: "bpm")
            logger.info("SharedStateStore.bpm SET \(newValue)")
            postDarwinNotification(DarwinNotification.stateChanged)
        }
    }

    var isPlaying: Bool {
        get { defaults.object(forKey: "isPlaying") as? Bool ?? false }
        set {
            defaults.set(newValue, forKey: "isPlaying")
            logger.info("SharedStateStore.isPlaying SET \(newValue)")
        }
    }

    var volume: Float {
        get { defaults.object(forKey: "volume") as? Float ?? 0.4 }
        set {
            defaults.set(newValue, forKey: "volume")
        }
    }

    private init() {
        defaults = UserDefaults(suiteName: "group.com.danielbutler.MetronomeApp") ?? .standard
        observerPointer = Unmanaged.passUnretained(self).toOpaque()
        startObserving()
    }

    init(userDefaults: UserDefaults) {
        defaults = userDefaults
        observerPointer = Unmanaged.passUnretained(self).toOpaque()
        startObserving()
    }

    func synchronize() {
        defaults.synchronize()
    }

    func postCommand(_ command: StateStoreCommand) {
        switch command {
        case .start:
            postDarwinNotification(DarwinNotification.commandStart)
        case .stop:
            postDarwinNotification(DarwinNotification.commandStop)
        }
    }

    func notifyWidgetUpdate() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: - Darwin Notifications (Send)

    private nonisolated func postDarwinNotification(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
        logger.info("Posted Darwin notification: \(name)")
    }

    // MARK: - Darwin Notifications (Receive)

    private func startObserving() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = observerPointer

        let stateCallback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let instance = Unmanaged<SharedStateStore>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in
                instance.defaults.synchronize()
                instance.externalChangesSubject.send(.stateChanged)
            }
        }

        let startCallback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let instance = Unmanaged<SharedStateStore>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in
                instance.externalChangesSubject.send(.command(.start))
            }
        }

        let stopCallback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let instance = Unmanaged<SharedStateStore>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in
                instance.externalChangesSubject.send(.command(.stop))
            }
        }

        CFNotificationCenterAddObserver(center, observer,
            stateCallback,
            DarwinNotification.stateChanged as CFString,
            nil, .deliverImmediately)

        CFNotificationCenterAddObserver(center, observer,
            startCallback,
            DarwinNotification.commandStart as CFString,
            nil, .deliverImmediately)

        CFNotificationCenterAddObserver(center, observer,
            stopCallback,
            DarwinNotification.commandStop as CFString,
            nil, .deliverImmediately)
    }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, observerPointer)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests/SharedStateStoreTests -quiet 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Run all existing tests (regression check)**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests -quiet 2>&1 | grep "failed" | head -10`
Expected: No output (all pass — old and new code coexist)

- [ ] **Step 6: Commit**

```bash
git add MetronomeApp/SharedStateStore.swift MetronomeAppTests/SharedMetronomeStateTests.swift
git commit -m "refactor: add SharedStateStore with folded Darwin notification observer"
```

---

## Task 5: Inject `StateStore` into `MetronomeEngine`

Replace the hardcoded `SharedMetronomeState.shared` with an injectable `StateStore` parameter.

**Files:**
- Modify: `MetronomeApp/MetronomeEngine.swift` (lines 49-50 — replace `sharedState` and `stateObserver`)

- [ ] **Step 1: Write failing test**

Add to `MetronomeAppTests/MetronomeEngineTests.swift`:

```swift
    // MARK: - StateStore Injection

    func testEngineUsesInjectedStore() {
        let store = InMemoryStateStore()
        store.bpm = 200
        let injectedEngine = MetronomeEngine(store: store)
        injectedEngine.setup()
        XCTAssertEqual(injectedEngine.bpm, 200)
        injectedEngine.teardown()
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests/MetronomeEngineTests/testEngineUsesInjectedStore -quiet 2>&1 | tail -5`
Expected: FAIL (no `store:` parameter on `MetronomeEngine.init`)

- [ ] **Step 3: Add `store` parameter to `MetronomeEngine`**

In `MetronomeEngine.swift`, replace:

```swift
    // MARK: - Cross-Process

    private let sharedState = SharedMetronomeState.shared
    private var stateObserver: StateChangeObserver?
```

With:

```swift
    // MARK: - Cross-Process

    private let store: StateStore
```

Add an initializer:

```swift
    init(store: StateStore = SharedStateStore.shared) {
        self.store = store
    }
```

Then replace every `sharedState.` reference with `store.` throughout the file. The references are at the following locations (approximate — verify after prior edits):
- `setup()`: `sharedState.synchronize()`, `sharedState.bpm`, `sharedState.bpm =`, `sharedState.volume =`, `sharedState.isPlaying =`
- `togglePlayback()`: `sharedState.isPlaying =`
- `incrementBPM()`: `sharedState.bpm =`
- `decrementBPM()`: `sharedState.bpm =`
- `setBPM()`: `sharedState.bpm =`
- `setVolume()`: `sharedState.volume =` → `store.volume =`, `sharedState.notifyWidgetUpdate()` → `store.notifyWidgetUpdate()`
- `syncFromSharedState()`: `sharedState.synchronize()` → `store.synchronize()`, `sharedState.bpm` → `store.bpm`
- `handleSharedStateChange()`: `sharedState.synchronize()` → `store.synchronize()`, `sharedState.bpm` → `store.bpm`
- `handlePlayCommand()`: `sharedState.isPlaying =`
- `handleStopCommand()`: `sharedState.isPlaying =`
- `handleInterruptionBegan()`: `self.sharedState.isPlaying =`
- `handleInterruptionEnded()`: `self.sharedState.isPlaying =`

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests -quiet 2>&1 | grep "failed" | head -10`
Expected: No output (all pass)

- [ ] **Step 5: Commit**

```bash
git add MetronomeApp/MetronomeEngine.swift MetronomeAppTests/MetronomeEngineTests.swift
git commit -m "refactor: inject StateStore into MetronomeEngine"
```

---

## Task 6: Subscribe to `externalChanges` (replace `StateChangeObserver`)

Replace the `StateChangeObserver` wiring in `MetronomeEngine` with a subscription to `store.externalChanges`.

**Files:**
- Modify: `MetronomeApp/MetronomeEngine.swift` (replace `startObservingSharedState()` / `stopObservingSharedState()`)

- [ ] **Step 1: Write failing test**

Add to `MetronomeAppTests/MetronomeEngineTests.swift`:

```swift
    // MARK: - External Changes

    func testExternalStateChangeUpdatesBPM() {
        let store = InMemoryStateStore()
        let injectedEngine = MetronomeEngine(store: store)
        injectedEngine.setup()

        store.bpm = 210
        store.simulateExternalChange(.stateChanged)

        XCTAssertEqual(injectedEngine.bpm, 210)
        injectedEngine.teardown()
    }

    func testExternalStartCommandStartsPlayback() {
        let store = InMemoryStateStore()
        let injectedEngine = MetronomeEngine(store: store)
        injectedEngine.setup()
        XCTAssertFalse(injectedEngine.isPlaying)

        store.simulateExternalChange(.command(.start))

        XCTAssertTrue(injectedEngine.isPlaying)
        injectedEngine.teardown()
    }

    func testExternalStopCommandStopsPlayback() {
        let store = InMemoryStateStore()
        let injectedEngine = MetronomeEngine(store: store)
        injectedEngine.setup()
        injectedEngine.togglePlayback()
        XCTAssertTrue(injectedEngine.isPlaying)

        store.simulateExternalChange(.command(.stop))

        XCTAssertFalse(injectedEngine.isPlaying)
        injectedEngine.teardown()
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests/MetronomeEngineTests/testExternalStateChangeUpdatesBPM -quiet 2>&1 | tail -5`
Expected: FAIL

- [ ] **Step 3: Replace observer with subscription**

In `MetronomeEngine.swift`, replace the `startObservingSharedState()` method:

```swift
    private func startObservingSharedState() {
        store.externalChanges
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .stateChanged:
                    self.handleSharedStateChange()
                case .command(.start):
                    self.handlePlayCommand()
                case .command(.stop):
                    self.handleStopCommand()
                }
            }
            .store(in: &subscriptions)
    }
```

Remove the `stopObservingSharedState()` method body (subscriptions are already cancelled in `teardown()` via `subscriptions.removeAll()`):

```swift
    private func stopObservingSharedState() {
        // Subscriptions cancelled via subscriptions.removeAll() in teardown()
    }
```

In `handleSharedStateChange()`, remove the `sharedState.synchronize()` call (the store now calls `synchronize()` internally before emitting `.stateChanged`). Replace `sharedState.bpm` with `store.bpm`:

```swift
    @MainActor
    private func handleSharedStateChange() {
        let newBPM = store.bpm
        logger.info("handleSharedStateChange — shared bpm=\(newBPM), local bpm=\(self.bpm)")

        if newBPM != bpm {
            logger.info("handleSharedStateChange — BPM changed \(self.bpm) → \(newBPM)")
            bpm = newBPM
            if isPlaying {
                handleBPMChange()
            }
            notifyStateChanged()
        }
    }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests -quiet 2>&1 | grep "failed" | head -10`
Expected: No output (all pass)

- [ ] **Step 5: Commit**

```bash
git add MetronomeApp/MetronomeEngine.swift MetronomeAppTests/MetronomeEngineTests.swift
git commit -m "refactor: replace StateChangeObserver with store.externalChanges subscription"
```

---

## Task 7: Remove `syncFromSharedState()`, update `ContentView`, add background-resume sync

**Files:**
- Modify: `MetronomeApp/MetronomeEngine.swift` (remove `syncFromSharedState()`, add `store.synchronize()` to `ensureReady()`)
- Modify: `MetronomeApp/ContentView.swift` (remove `syncFromSharedState()` call, lines 121-126)

- [ ] **Step 1: Remove `syncFromSharedState()` from `MetronomeEngine`**

Delete the entire `syncFromSharedState()` method from `MetronomeEngine.swift`. The store's `externalChanges` publisher handles this automatically.

- [ ] **Step 2: Add `store.synchronize()` to `ensureReady()`**

Darwin notifications can be missed while the app is suspended. When the app wakes via `ensureReady()`, it must force-read from disk. Add `store.synchronize()` at the start of `ensureReady()`, after the `guard !isSetUp` check:

```swift
func ensureReady() {
    guard !isSetUp else { return }
    logger.info("ensureReady — background setup (preserving state)")
    store.synchronize()
    setupAudioEngine()
    // ... rest unchanged
}
```

The `store.synchronize()` call reads the latest values from disk. Once subscriptions are set up and `notifyStateChanged()` fires, the subscription will pick up any changes.

- [ ] **Step 3: Update `ContentView.swift`**

Replace the `onChange(of: scenePhase)` block (lines 121-126):

```swift
.onChange(of: scenePhase) { _, newPhase in
    logger.info("scenePhase changed to \(String(describing: newPhase))")
    if newPhase == .active {
        engine.syncFromSharedState()
    }
}
```

With:

```swift
.onChange(of: scenePhase) { _, newPhase in
    logger.info("scenePhase changed to \(String(describing: newPhase))")
}
```

Note: If this is the only thing the `onChange` does, you may remove the entire modifier. Check whether logging alone justifies keeping it.

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests -quiet 2>&1 | grep "failed" | head -10`
Expected: No output (all pass)

- [ ] **Step 5: Commit**

```bash
git add MetronomeApp/MetronomeEngine.swift MetronomeApp/ContentView.swift
git commit -m "refactor: remove syncFromSharedState, add store.synchronize() to ensureReady"
```

---

## Task 8: Update widget intents

**Files:**
- Modify: `MetronomeApp/MetronomeAppIntents.swift` (lines 49, 59, 71, 75, 87, 91, 102, 121)

- [ ] **Step 1: Update all intents**

Replace all `SharedMetronomeState` references with `SharedStateStore`:

```swift
// In each intent's perform() method, change:
let sharedState = SharedMetronomeState.shared
// To:
let store = SharedStateStore.shared
```

Replace all `SharedMetronomeState.postCommand(...)` calls:

```swift
// Change:
SharedMetronomeState.postCommand(MetronomeNotification.commandStart)
// To:
SharedStateStore.shared.postCommand(.start)

// Change:
SharedMetronomeState.postCommand(MetronomeNotification.commandStop)
// To:
SharedStateStore.shared.postCommand(.stop)

// Change (in ToggleMetronomeIntent):
SharedMetronomeState.postCommand(command)
// To:
SharedStateStore.shared.postCommand(newIsPlaying ? .start : .stop)
```

Also replace `sharedState.` property accesses with `store.` throughout.

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Verify no dangling references**

```bash
grep -r "SharedMetronomeState" MetronomeApp/ --include="*.swift"
grep -r "MetronomeNotification\." MetronomeApp/ --include="*.swift"
```

Expected: No output. All references should now use `SharedStateStore` and `StateStoreCommand`.

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests -quiet 2>&1 | grep "failed" | head -10`
Expected: No output (all pass)

- [ ] **Step 5: Commit**

```bash
git add MetronomeApp/MetronomeAppIntents.swift
git commit -m "refactor: update widget intents to use SharedStateStore"
```

---

## Task 9: Inject `InMemoryStateStore` into all test files

Update all test files that create `MetronomeEngine()` directly to inject `InMemoryStateStore`.

**Files:**
- Modify: `MetronomeAppTests/MetronomeEngineTests.swift` (lines 17-18 — `setUp`)
- Modify: `MetronomeAppTests/NowPlayingTests.swift` (wherever `MetronomeEngine()` is created)
- Modify: `MetronomeAppTests/PhoneSessionManagerTests.swift` (wherever `MetronomeEngine()` is created)

- [ ] **Step 1: Update `MetronomeEngineTests`**

In `setUp()`, change:

```swift
override func setUp() {
    engine = MetronomeEngine()
}
```

To:

```swift
override func setUp() {
    engine = MetronomeEngine(store: InMemoryStateStore())
}
```

Also update any tests that create `MetronomeEngine()` inline (e.g. `testSetupRestoresBPMFromSharedState`, `testSetupResetsIsPlayingToFalse`). These tests verify persistence behavior — they need a *shared* `InMemoryStateStore` instance across engine instances:

```swift
func testSetupRestoresBPMFromSharedState() {
    let store = InMemoryStateStore()
    let engine1 = MetronomeEngine(store: store)
    engine1.setup()
    engine1.setBPM(210)
    engine1.teardown()

    let engine2 = MetronomeEngine(store: store)
    engine2.setup()
    XCTAssertEqual(engine2.bpm, 210, "setup() should restore BPM from store")
    engine2.teardown()
}

func testSetupResetsIsPlayingToFalse() {
    let store = InMemoryStateStore()
    let engine1 = MetronomeEngine(store: store)
    engine1.setup()
    engine1.togglePlayback()
    XCTAssertTrue(engine1.isPlaying)
    engine1.teardown()

    let engine2 = MetronomeEngine(store: store)
    engine2.setup()
    XCTAssertFalse(engine2.isPlaying, "setup() should always start with isPlaying = false")
    engine2.teardown()
}
```

- [ ] **Step 2: Update `NowPlayingTests`**

Change all `MetronomeEngine()` calls to `MetronomeEngine(store: InMemoryStateStore())`.

- [ ] **Step 3: Update `PhoneSessionManagerTests`**

Change all `MetronomeEngine()` calls to `MetronomeEngine(store: InMemoryStateStore())`.

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests -quiet 2>&1 | grep "failed" | head -10`
Expected: No output (all pass)

- [ ] **Step 5: Commit**

```bash
git add MetronomeAppTests/MetronomeEngineTests.swift MetronomeAppTests/NowPlayingTests.swift MetronomeAppTests/PhoneSessionManagerTests.swift
git commit -m "test: inject InMemoryStateStore into all engine tests"
```

---

## Task 10: Delete old files and update notification tests

**Files:**
- Delete: `MetronomeApp/MetronomeApp/SharedMetronomeState.swift`
- Delete: `MetronomeApp/StateChangeObserver.swift`
- Delete: `MetronomeAppTests/StateChangeObserverTests.swift`
- Modify or delete: `MetronomeAppTests/MetronomeNotificationTests.swift`

**Important:** Delete test files before source files to avoid intermediate compile failures (test files reference types from the source files being deleted).

- [ ] **Step 1: Delete test files that reference old types**

Delete these from the Xcode project and filesystem:
- `MetronomeAppTests/StateChangeObserverTests.swift` — covered by `SharedStateStoreTests`
- `MetronomeAppTests/MetronomeNotificationTests.swift` — `MetronomeNotification` is now `DarwinNotification`, a private detail inside `SharedStateStore`. Round-trip tests in `SharedStateStoreTests` cover this end-to-end.

- [ ] **Step 2: Delete source files**

Delete these from the Xcode project and filesystem:
- `MetronomeApp/MetronomeApp/SharedMetronomeState.swift` (note: nested under `MetronomeApp/MetronomeApp/` on disk)
- `MetronomeApp/StateChangeObserver.swift`

All consumers now use `SharedStateStore`.

- [ ] **Step 3: Verify build and tests**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests -quiet 2>&1 | grep "failed" | head -10`
Expected: No output (all pass)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: delete SharedMetronomeState, StateChangeObserver, and related tests"
```

---

## Task 11: Final verification

- [ ] **Step 1: Run full unit test suite**

Run: `xcodebuild test -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:MetronomeAppTests 2>&1 | grep -E "(Test Case|passed|failed|Test Suite)" | head -60`
Expected: All pass

- [ ] **Step 2: Grep verifications**

```bash
# Zero hits for old types in source (not tests, not docs)
grep -r "SharedMetronomeState" MetronomeApp/ --include="*.swift"
grep -r "StateChangeObserver" MetronomeApp/ --include="*.swift"
grep -r "nonisolated(unsafe)" MetronomeApp/ --include="*.swift"
grep -r "syncFromSharedState" MetronomeApp/ --include="*.swift"
grep -r "syncFromSharedState" MetronomeAppTests/ --include="*.swift"
```

Expected: No output for any of these.

- [ ] **Step 3: Verify `synchronize()` not called from `MetronomeEngine`**

```bash
grep "synchronize()" MetronomeApp/MetronomeEngine.swift
```

Expected: No output (store handles sync internally).

- [ ] **Step 4: Commit (if any cleanup needed)**

```bash
git status
# If clean, no commit needed. If cleanup was done, commit it.
```
