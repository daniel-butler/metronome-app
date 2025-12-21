# Running Metronome Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build iOS metronome app for running cadence (150-230 BPM) with background playback support.

**Architecture:** SwiftUI view layer with Observable ViewModel for state management, dedicated MetronomeEngine class for audio timing/playback using AVAudioEngine, and AVAudioSession for background audio configuration.

**Tech Stack:** SwiftUI, AVAudioEngine, AVAudioSession, Combine (for debouncing)

---

## Task 1: Create MetronomeViewModel with Basic State

**Files:**
- Create: `MetronomeApp/MetronomeApp/MetronomeViewModel.swift`
- Test: `MetronomeApp/MetronomeAppTests/MetronomeViewModelTests.swift`

**Step 1: Write the failing test for initial state**

Create `MetronomeApp/MetronomeAppTests/MetronomeViewModelTests.swift`:

```swift
//
//  MetronomeViewModelTests.swift
//  MetronomeAppTests
//
//  Created by Claude on 12/21/25.
//

import XCTest
@testable import MetronomeApp

final class MetronomeViewModelTests: XCTestCase {

    func testInitialState() {
        let viewModel = MetronomeViewModel()

        XCTAssertEqual(viewModel.bpm, 180, "Default BPM should be 180")
        XCTAssertEqual(viewModel.volume, 0.4, accuracy: 0.01, "Default volume should be 40%")
        XCTAssertFalse(viewModel.isPlaying, "Should not be playing initially")
    }
}
```

**Step 2: Run test to verify it fails**

In Xcode: `Cmd+U` to run tests
Expected: BUILD FAILS with "Cannot find 'MetronomeViewModel' in scope"

**Step 3: Write minimal implementation**

Create `MetronomeApp/MetronomeApp/MetronomeViewModel.swift`:

```swift
//
//  MetronomeViewModel.swift
//  MetronomeApp
//
//  Created by Claude on 12/21/25.
//

import Foundation
import Observation

@Observable
final class MetronomeViewModel {
    var bpm: Int = 180
    var volume: Float = 0.4
    var isPlaying: Bool = false
}
```

**Step 4: Run test to verify it passes**

In Xcode: `Cmd+U` to run tests
Expected: PASS (1 test passing)

**Step 5: Commit**

```bash
git add MetronomeApp/MetronomeApp/MetronomeViewModel.swift MetronomeApp/MetronomeAppTests/MetronomeViewModelTests.swift
git commit -m "feat: add MetronomeViewModel with initial state"
```

---

## Task 2: Implement BPM Control Logic

**Files:**
- Modify: `MetronomeApp/MetronomeApp/MetronomeViewModel.swift`
- Modify: `MetronomeApp/MetronomeAppTests/MetronomeViewModelTests.swift`

**Step 1: Write failing tests for BPM increment/decrement**

Add to `MetronomeViewModelTests.swift`:

```swift
func testIncrementBPM() {
    let viewModel = MetronomeViewModel()
    viewModel.bpm = 180

    viewModel.incrementBPM()

    XCTAssertEqual(viewModel.bpm, 181)
}

func testDecrementBPM() {
    let viewModel = MetronomeViewModel()
    viewModel.bpm = 180

    viewModel.decrementBPM()

    XCTAssertEqual(viewModel.bpm, 179)
}

func testIncrementBPMAtMaximum() {
    let viewModel = MetronomeViewModel()
    viewModel.bpm = 230

    viewModel.incrementBPM()

    XCTAssertEqual(viewModel.bpm, 230, "BPM should not exceed 230")
}

func testDecrementBPMAtMinimum() {
    let viewModel = MetronomeViewModel()
    viewModel.bpm = 150

    viewModel.decrementBPM()

    XCTAssertEqual(viewModel.bpm, 150, "BPM should not go below 150")
}

func testCanIncrementBPM() {
    let viewModel = MetronomeViewModel()

    viewModel.bpm = 180
    XCTAssertTrue(viewModel.canIncrementBPM)

    viewModel.bpm = 230
    XCTAssertFalse(viewModel.canIncrementBPM)
}

func testCanDecrementBPM() {
    let viewModel = MetronomeViewModel()

    viewModel.bpm = 180
    XCTAssertTrue(viewModel.canDecrementBPM)

    viewModel.bpm = 150
    XCTAssertFalse(viewModel.canDecrementBPM)
}
```

**Step 2: Run tests to verify they fail**

In Xcode: `Cmd+U`
Expected: BUILD FAILS with "Value of type 'MetronomeViewModel' has no member 'incrementBPM'"

**Step 3: Implement BPM control methods**

Add to `MetronomeViewModel.swift`:

```swift
// Add these computed properties
var canIncrementBPM: Bool {
    bpm < 230
}

var canDecrementBPM: Bool {
    bpm > 150
}

// Add these methods
func incrementBPM() {
    guard canIncrementBPM else { return }
    bpm += 1
}

func decrementBPM() {
    guard canDecrementBPM else { return }
    bpm -= 1
}
```

**Step 4: Run tests to verify they pass**

In Xcode: `Cmd+U`
Expected: PASS (7 tests passing)

**Step 5: Commit**

```bash
git add MetronomeApp/MetronomeApp/MetronomeViewModel.swift MetronomeApp/MetronomeAppTests/MetronomeViewModelTests.swift
git commit -m "feat: add BPM increment/decrement with bounds checking"
```

---

## Task 3: Implement Volume Control Logic

**Files:**
- Modify: `MetronomeApp/MetronomeApp/MetronomeViewModel.swift`
- Modify: `MetronomeApp/MetronomeAppTests/MetronomeViewModelTests.swift`

**Step 1: Write failing test for volume bounds**

Add to `MetronomeViewModelTests.swift`:

```swift
func testVolumeClampedToValidRange() {
    let viewModel = MetronomeViewModel()

    viewModel.volume = -0.5
    XCTAssertEqual(viewModel.volume, 0.0, accuracy: 0.01, "Volume should not go below 0")

    viewModel.volume = 1.5
    XCTAssertEqual(viewModel.volume, 1.0, accuracy: 0.01, "Volume should not exceed 1.0")

    viewModel.volume = 0.5
    XCTAssertEqual(viewModel.volume, 0.5, accuracy: 0.01, "Volume should accept valid values")
}
```

**Step 2: Run test to verify it fails**

In Xcode: `Cmd+U`
Expected: FAIL - volume not clamped to range

**Step 3: Implement volume clamping**

Modify `MetronomeViewModel.swift`, change the `volume` property to:

```swift
private var _volume: Float = 0.4

var volume: Float {
    get { _volume }
    set { _volume = max(0.0, min(1.0, newValue)) }
}
```

**Step 4: Run test to verify it passes**

In Xcode: `Cmd+U`
Expected: PASS (8 tests passing)

**Step 5: Commit**

```bash
git add MetronomeApp/MetronomeApp/MetronomeViewModel.swift MetronomeApp/MetronomeAppTests/MetronomeViewModelTests.swift
git commit -m "feat: add volume clamping to valid range (0.0-1.0)"
```

---

## Task 4: Create MetronomeEngine for Audio Playback

**Files:**
- Create: `MetronomeApp/MetronomeApp/MetronomeEngine.swift`
- Create: `MetronomeApp/MetronomeAppTests/MetronomeEngineTests.swift`

**Step 1: Write failing test for interval calculation**

Create `MetronomeApp/MetronomeAppTests/MetronomeEngineTests.swift`:

```swift
//
//  MetronomeEngineTests.swift
//  MetronomeAppTests
//
//  Created by Claude on 12/21/25.
//

import XCTest
@testable import MetronomeApp

final class MetronomeEngineTests: XCTestCase {

    func testIntervalCalculation() {
        XCTAssertEqual(MetronomeEngine.calculateInterval(bpm: 60), 1.0, accuracy: 0.001, "60 BPM = 1 second interval")
        XCTAssertEqual(MetronomeEngine.calculateInterval(bpm: 120), 0.5, accuracy: 0.001, "120 BPM = 0.5 second interval")
        XCTAssertEqual(MetronomeEngine.calculateInterval(bpm: 180), 0.333, accuracy: 0.001, "180 BPM ≈ 0.333 second interval")
    }
}
```

**Step 2: Run test to verify it fails**

In Xcode: `Cmd+U`
Expected: BUILD FAILS with "Cannot find 'MetronomeEngine' in scope"

**Step 3: Write minimal implementation**

Create `MetronomeApp/MetronomeApp/MetronomeEngine.swift`:

```swift
//
//  MetronomeEngine.swift
//  MetronomeApp
//
//  Created by Claude on 12/21/25.
//

import Foundation
import AVFoundation

final class MetronomeEngine {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioBuffer: AVAudioPCMBuffer?
    private var timer: Timer?

    static func calculateInterval(bpm: Int) -> TimeInterval {
        return 60.0 / Double(bpm)
    }

    init() {
        // Audio setup will be added later
    }

    deinit {
        stop()
    }

    func start(bpm: Int, volume: Float) {
        // Implementation will be added later
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateVolume(_ volume: Float) {
        // Implementation will be added later
    }
}
```

**Step 4: Run test to verify it passes**

In Xcode: `Cmd+U`
Expected: PASS (9 tests passing)

**Step 5: Commit**

```bash
git add MetronomeApp/MetronomeApp/MetronomeEngine.swift MetronomeApp/MetronomeAppTests/MetronomeEngineTests.swift
git commit -m "feat: add MetronomeEngine with interval calculation"
```

---

## Task 5: Add Tick Sound Asset

**Note:** This task requires manual work in Xcode.

**Step 1: Find or create tick sound**

Option A: Download a free metronome tick sound (WAV format, mono, ~50-100ms duration)
Option B: Use an online tone generator to create a simple beep/click sound

**Step 2: Add to Xcode project**

1. In Xcode, right-click on `MetronomeApp` folder
2. Select "Add Files to MetronomeApp..."
3. Add the `tick.wav` file
4. Ensure "Copy items if needed" is checked
5. Ensure "MetronomeApp" target is selected

**Step 3: Verify file is in bundle**

The file should appear in the project navigator under the `MetronomeApp` group.

**Step 4: Commit**

```bash
git add MetronomeApp/MetronomeApp/tick.wav
git commit -m "feat: add tick sound asset"
```

---

## Task 6: Implement Audio Playback in MetronomeEngine

**Files:**
- Modify: `MetronomeApp/MetronomeApp/MetronomeEngine.swift`

**Step 1: Implement audio engine setup**

Replace the `init()` method in `MetronomeEngine.swift`:

```swift
init() {
    setupAudioEngine()
}

private func setupAudioEngine() {
    audioEngine = AVAudioEngine()
    playerNode = AVAudioPlayerNode()

    guard let audioEngine = audioEngine,
          let playerNode = playerNode else { return }

    audioEngine.attach(playerNode)
    audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)

    loadTickSound()

    do {
        try audioEngine.start()
    } catch {
        print("Failed to start audio engine: \(error)")
    }
}

private func loadTickSound() {
    guard let tickURL = Bundle.main.url(forResource: "tick", withExtension: "wav") else {
        print("Could not find tick.wav in bundle")
        return
    }

    do {
        let audioFile = try AVAudioFile(forReading: tickURL)
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("Could not create audio buffer")
            return
        }

        try audioFile.read(into: buffer)
        self.audioBuffer = buffer
    } catch {
        print("Failed to load tick sound: \(error)")
    }
}
```

**Step 2: Implement start method**

Replace the `start(bpm:volume:)` method:

```swift
func start(bpm: Int, volume: Float) {
    stop() // Stop any existing timer

    guard let playerNode = playerNode,
          let audioBuffer = audioBuffer,
          let audioEngine = audioEngine else { return }

    // Set volume
    audioEngine.mainMixerNode.outputVolume = volume

    // Calculate interval
    let interval = Self.calculateInterval(bpm: bpm)

    // Schedule first tick immediately
    playerNode.scheduleBuffer(audioBuffer)
    if !playerNode.isPlaying {
        playerNode.play()
    }

    // Schedule repeating ticks
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
        guard let self = self,
              let playerNode = self.playerNode,
              let audioBuffer = self.audioBuffer else { return }

        playerNode.scheduleBuffer(audioBuffer)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
}
```

**Step 3: Implement updateVolume method**

Replace the `updateVolume(_:)` method:

```swift
func updateVolume(_ volume: Float) {
    audioEngine?.mainMixerNode.outputVolume = volume
}
```

**Step 4: Update stop method**

Replace the `stop()` method:

```swift
func stop() {
    timer?.invalidate()
    timer = nil
    playerNode?.stop()
}
```

**Step 5: Manual testing**

You'll need to test this manually since audio playback is hard to unit test:

1. Build and run the app in simulator or device
2. You won't have UI yet, so add temporary code to ContentView to test
3. Verify tick sound plays at correct interval

**Step 6: Commit**

```bash
git add MetronomeApp/MetronomeApp/MetronomeEngine.swift
git commit -m "feat: implement audio playback in MetronomeEngine"
```

---

## Task 7: Connect ViewModel to MetronomeEngine

**Files:**
- Modify: `MetronomeApp/MetronomeApp/MetronomeViewModel.swift`

**Step 1: Add MetronomeEngine to ViewModel**

Add at the top of the `MetronomeViewModel` class:

```swift
private let engine = MetronomeEngine()
```

**Step 2: Implement start/stop methods**

Add these methods to `MetronomeViewModel`:

```swift
func start() {
    isPlaying = true
    engine.start(bpm: bpm, volume: volume)
}

func stop() {
    isPlaying = false
    engine.stop()
}

func togglePlayback() {
    if isPlaying {
        stop()
    } else {
        start()
    }
}
```

**Step 3: Add BPM change handling with debouncing**

Add these imports at the top of the file:

```swift
import Combine
```

Add these properties to the class:

```swift
private var bpmDebounceTimer: Timer?
private var pendingBPM: Int?
```

Modify the `incrementBPM()` and `decrementBPM()` methods to trigger restart:

```swift
func incrementBPM() {
    guard canIncrementBPM else { return }
    bpm += 1
    handleBPMChange()
}

func decrementBPM() {
    guard canDecrementBPM else { return }
    bpm -= 1
    handleBPMChange()
}

private func handleBPMChange() {
    guard isPlaying else { return }

    // Cancel existing debounce timer
    bpmDebounceTimer?.invalidate()

    // Store pending BPM
    pendingBPM = bpm

    // Schedule new timer
    bpmDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
        guard let self = self, let newBPM = self.pendingBPM else { return }
        self.engine.start(bpm: newBPM, volume: self.volume)
        self.pendingBPM = nil
    }
}
```

**Step 4: Add volume change handling**

Modify the `volume` property setter to update engine:

```swift
private var _volume: Float = 0.4

var volume: Float {
    get { _volume }
    set {
        _volume = max(0.0, min(1.0, newValue))
        engine.updateVolume(_volume)
    }
}
```

**Step 5: Add cleanup**

Add a deinit method:

```swift
deinit {
    stop()
    bpmDebounceTimer?.invalidate()
}
```

**Step 6: Commit**

```bash
git add MetronomeApp/MetronomeApp/MetronomeViewModel.swift
git commit -m "feat: connect ViewModel to MetronomeEngine with debouncing"
```

---

## Task 8: Build the UI

**Files:**
- Modify: `MetronomeApp/MetronomeApp/ContentView.swift`

**Step 1: Replace ContentView with metronome UI**

Replace the entire contents of `ContentView.swift`:

```swift
//
//  ContentView.swift
//  MetronomeApp
//
//  Created by Daniel Butler on 12/21/25.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = MetronomeViewModel()

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // BPM Display
            VStack(spacing: 8) {
                Text("\(viewModel.bpm)")
                    .font(.system(size: 80, weight: .bold))
                Text("BPM")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // BPM Controls
            HStack(spacing: 60) {
                Button {
                    viewModel.decrementBPM()
                } label: {
                    Image(systemName: "minus")
                        .font(.title)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .stroke(lineWidth: 2)
                        )
                }
                .disabled(!viewModel.canDecrementBPM)

                Spacer()

                Button {
                    viewModel.incrementBPM()
                } label: {
                    Image(systemName: "plus")
                        .font(.title)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .stroke(lineWidth: 2)
                        )
                }
                .disabled(!viewModel.canIncrementBPM)
            }
            .padding(.horizontal, 40)

            Spacer()

            // Volume Control
            HStack(spacing: 16) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)

                Slider(value: Binding(
                    get: { Double(viewModel.volume) },
                    set: { viewModel.volume = Float($0) }
                ), in: 0...1)
            }
            .padding(.horizontal, 40)

            // Start/Stop Button
            Button {
                viewModel.togglePlayback()
            } label: {
                Text(viewModel.isPlaying ? "STOP" : "START")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(viewModel.isPlaying ? Color.red : Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    ContentView()
}
```

**Step 2: Manual testing**

1. Build and run the app (`Cmd+R`)
2. Test BPM controls (should increment/decrement)
3. Test volume slider
4. Test START/STOP button (should hear ticks)
5. Test BPM change while playing (should debounce)

**Step 3: Commit**

```bash
git add MetronomeApp/MetronomeApp/ContentView.swift
git commit -m "feat: build metronome UI with controls"
```

---

## Task 9: Configure Background Audio Session

**Files:**
- Create: `MetronomeApp/MetronomeApp/AudioSessionManager.swift`
- Modify: `MetronomeApp/MetronomeApp/MetronomeViewModel.swift`

**Step 1: Create AudioSessionManager**

Create `MetronomeApp/MetronomeApp/AudioSessionManager.swift`:

```swift
//
//  AudioSessionManager.swift
//  MetronomeApp
//
//  Created by Claude on 12/21/25.
//

import Foundation
import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private var wasPlayingBeforeInterruption = false

    private init() {
        setupAudioSession()
        setupInterruptionHandling()
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            NotificationCenter.default.post(name: .audioInterruptionBegan, object: nil)
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                NotificationCenter.default.post(name: .audioInterruptionEnded, object: nil)
            }
        @unknown default:
            break
        }
    }
}

extension Notification.Name {
    static let audioInterruptionBegan = Notification.Name("audioInterruptionBegan")
    static let audioInterruptionEnded = Notification.Name("audioInterruptionEnded")
}
```

**Step 2: Initialize AudioSessionManager in ViewModel**

Add to `MetronomeViewModel.swift`:

Add this property:

```swift
private let audioSessionManager = AudioSessionManager.shared
```

Add these properties for interruption handling:

```swift
private var wasPlayingBeforeInterruption = false
```

Add in `init()`:

```swift
init() {
    setupInterruptionObservers()
}

private func setupInterruptionObservers() {
    NotificationCenter.default.addObserver(
        forName: .audioInterruptionBegan,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        guard let self = self else { return }
        self.wasPlayingBeforeInterruption = self.isPlaying
        if self.isPlaying {
            self.stop()
        }
    }

    NotificationCenter.default.addObserver(
        forName: .audioInterruptionEnded,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        guard let self = self else { return }
        if self.wasPlayingBeforeInterruption {
            self.start()
            self.wasPlayingBeforeInterruption = false
        }
    }
}
```

**Step 3: Manual testing**

1. Build and run on a physical device (simulator won't fully test this)
2. Start the metronome
3. Lock the screen - should continue playing
4. Unlock - should still be playing
5. While playing, trigger Siri or receive a call - should stop
6. When interruption ends - should auto-resume

**Step 4: Commit**

```bash
git add MetronomeApp/MetronomeApp/AudioSessionManager.swift MetronomeApp/MetronomeApp/MetronomeViewModel.swift
git commit -m "feat: add background audio session and interruption handling"
```

---

## Task 10: Add Background Modes Capability

**Note:** This requires Xcode configuration.

**Step 1: Enable background audio in Xcode**

1. Select the MetronomeApp project in the navigator
2. Select the MetronomeApp target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add "Background Modes"
6. Check "Audio, AirPlay, and Picture in Picture"

**Step 2: Verify configuration**

The capability should appear in the target's Signing & Capabilities tab.

**Step 3: Test background playback**

1. Build and run on device
2. Start metronome
3. Press home button - should continue playing
4. Open another app - should continue playing
5. Return to metronome - should still be playing

**Step 4: Commit**

```bash
git add MetronomeApp/MetronomeApp.xcodeproj/project.pbxproj
git commit -m "feat: enable background audio capability"
```

---

## Task 11: Final Polish and Testing

**Files:**
- All files for review

**Step 1: Test all features**

Manual test checklist:
- [ ] App launches with 180 BPM, 40% volume
- [ ] Plus button increments BPM by 1
- [ ] Minus button decrements BPM by 1
- [ ] Plus button disabled at 230 BPM
- [ ] Minus button disabled at 150 BPM
- [ ] Volume slider adjusts volume smoothly
- [ ] START button starts metronome
- [ ] STOP button stops metronome
- [ ] Button text changes START ↔ STOP
- [ ] Tick sound is clear and audible
- [ ] BPM changes while playing are debounced (0.3s)
- [ ] Metronome continues when screen locks
- [ ] Metronome continues when app backgrounds
- [ ] Interruption (Siri, call) stops metronome
- [ ] Metronome auto-resumes after interruption

**Step 2: Run unit tests**

In Xcode: `Cmd+U`
Expected: All tests pass

**Step 3: Test on device**

Build and run on a physical iOS device for final verification, especially for:
- Background playback
- Interruption handling
- Audio quality

**Step 4: Review code quality**

- Check for any TODO or FIXME comments
- Verify all files have proper headers
- Ensure consistent code style
- Remove any debug print statements if needed

**Step 5: Final commit (if changes needed)**

```bash
git add .
git commit -m "polish: final testing and cleanup"
```

---

## Completion Criteria

- [ ] All unit tests passing
- [ ] BPM control works (150-230 range, ±1 per tap)
- [ ] Volume control works (0-100%, default 40%)
- [ ] START/STOP button works
- [ ] Tick sound plays at correct intervals
- [ ] Background playback works (screen lock + app background)
- [ ] Interruption handling works (auto-resume after calls/Siri)
- [ ] BPM changes are debounced while playing
- [ ] UI is clean and functional
- [ ] No crashes or errors in console

## Known Limitations

- No haptic feedback (could be added later)
- No time signature options (not needed for running)
- No sound customization (classic tick only)
- Basic UI styling (functional but minimal)

## Future Enhancements (Out of Scope)

- Workout timer integration
- Cadence history tracking
- Custom sound selection
- Haptic feedback on beats
- Watch app companion
