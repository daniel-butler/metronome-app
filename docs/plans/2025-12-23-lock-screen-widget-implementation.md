# Lock Screen Widget Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add background audio playback and interactive lock screen widget with BPM controls

**Architecture:** Enable background audio via Info.plist capability, share state between app and widget via App Group UserDefaults, implement App Intents for widget button actions, create WidgetKit extension with lock screen widget

**Tech Stack:** SwiftUI, WidgetKit, App Intents, AVFoundation, App Groups

---

## Task 1: Enable Background Audio

**Files:**
- Modify: `MetronomeApp/MetronomeApp/Info.plist`

**Step 1: Add background audio capability to Info.plist**

Add this entry to Info.plist (right after the existing entries):

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

**Step 2: Verify the change**

Run: `cat MetronomeApp/MetronomeApp/Info.plist | grep -A 2 UIBackgroundModes`

Expected: Shows the array with audio entry

**Step 3: Commit**

```bash
git add MetronomeApp/MetronomeApp/Info.plist
git commit -m "feat: enable background audio playback"
```

---

## Task 2: Create App Group (XCODE STEP)

**Manual Xcode Steps:**

This task MUST be done in Xcode as it requires signing and entitlements configuration.

1. Open `MetronomeApp/MetronomeApp.xcodeproj` in Xcode
2. Select the `MetronomeApp` target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Search for and add "App Groups"
6. Click "+" under App Groups
7. Enter App Group ID: `group.com.danielbutler.MetronomeApp`
8. Ensure the checkbox next to the group is checked

**Step 4: Verify entitlements file was created**

Run: `ls -la MetronomeApp/MetronomeApp/MetronomeApp.entitlements`

Expected: File exists

**Step 5: Commit the entitlements**

```bash
git add MetronomeApp/MetronomeApp.xcodeproj MetronomeApp/MetronomeApp/MetronomeApp.entitlements
git commit -m "feat: add App Group for widget state sharing"
```

---

## Task 3: Create Shared State Manager

**Files:**
- Create: `MetronomeApp/MetronomeApp/SharedMetronomeState.swift`

**Step 1: Write the shared state manager**

Create `MetronomeApp/MetronomeApp/SharedMetronomeState.swift`:

```swift
//
//  SharedMetronomeState.swift
//  MetronomeApp
//
//  Created by Claude on 12/23/25.
//

import Foundation

final class SharedMetronomeState {
    static let shared = SharedMetronomeState()

    private let appGroupID = "group.com.danielbutler.MetronomeApp"
    private var userDefaults: UserDefaults?

    private init() {
        userDefaults = UserDefaults(suiteName: appGroupID)
    }

    // MARK: - BPM

    var bpm: Int {
        get {
            userDefaults?.integer(forKey: "bpm") ?? 180
        }
        set {
            userDefaults?.set(newValue, forKey: "bpm")
        }
    }

    // MARK: - Playing State

    var isPlaying: Bool {
        get {
            userDefaults?.bool(forKey: "isPlaying") ?? false
        }
        set {
            userDefaults?.set(newValue, forKey: "isPlaying")
        }
    }

    // MARK: - Volume

    var volume: Float {
        get {
            let value = userDefaults?.float(forKey: "volume")
            return value == 0 ? 0.4 : value
        }
        set {
            userDefaults?.set(newValue, forKey: "volume")
        }
    }

    // MARK: - Widget Refresh

    func notifyWidgetUpdate() {
        #if canImport(WidgetKit)
        import WidgetKit
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
```

**Step 2: Add to Xcode project (XCODE STEP)**

1. In Xcode Project Navigator, right-click on `MetronomeApp` folder
2. Select "Add Files to 'MetronomeApp'..."
3. Select `SharedMetronomeState.swift`
4. Ensure "Add to targets: MetronomeApp" is checked
5. Click "Add"

**Step 3: Build to verify no errors**

Run: `cd MetronomeApp && xcodebuild build -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add MetronomeApp/MetronomeApp/SharedMetronomeState.swift MetronomeApp/MetronomeApp.xcodeproj
git commit -m "feat: add shared state manager for App Group"
```

---

## Task 4: Update ContentView to Use Shared State

**Files:**
- Modify: `MetronomeApp/MetronomeApp/ContentView.swift`

**Step 1: Add shared state property**

At the top of `ContentView` struct (after the existing @State properties around line 21), add:

```swift
    private let sharedState = SharedMetronomeState.shared
```

**Step 2: Update onAppear to initialize from shared state**

Replace the `onAppear` method (around line 110-112) with:

```swift
        .onAppear {
            // Load from shared state
            bpm = sharedState.bpm
            volume = sharedState.volume
            isPlaying = sharedState.isPlaying

            setupAudioEngine()

            // Resume playback if was playing
            if isPlaying {
                startMetronome()
            }
        }
```

**Step 3: Update togglePlayback to save state**

In the `togglePlayback` method (around line 220-228), update to:

```swift
    private func togglePlayback() {
        if isPlaying {
            isPlaying = false
            sharedState.isPlaying = false
            stopMetronome()
        } else {
            isPlaying = true
            sharedState.isPlaying = true
            startMetronome()
        }
        sharedState.notifyWidgetUpdate()
    }
```

**Step 4: Update BPM increment to save state**

In the `incrementBPM` method (around line 232-236), update to:

```swift
    private func incrementBPM() {
        guard canIncrementBPM else { return }
        bpm += 1
        sharedState.bpm = bpm
        handleBPMChange()
        sharedState.notifyWidgetUpdate()
    }
```

**Step 5: Update BPM decrement to save state**

In the `decrementBPM` method (around line 238-242), update to:

```swift
    private func decrementBPM() {
        guard canDecrementBPM else { return }
        bpm -= 1
        sharedState.bpm = bpm
        handleBPMChange()
        sharedState.notifyWidgetUpdate()
    }
```

**Step 6: Update volume control to save state**

In the `updateVolume` method (around line 267-270), update to:

```swift
    private func updateVolume(_ newVolume: Float) {
        let clampedVolume = max(0.0, min(1.0, newVolume))
        audioEngine?.mainMixerNode.outputVolume = clampedVolume
        sharedState.volume = clampedVolume
        sharedState.notifyWidgetUpdate()
    }
```

**Step 7: Build to verify no errors**

Run: `cd MetronomeApp && xcodebuild build -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add MetronomeApp/MetronomeApp/ContentView.swift
git commit -m "feat: integrate shared state in ContentView"
```

---

## Task 5: Create Widget Extension (XCODE STEP)

**Manual Xcode Steps:**

1. In Xcode, File → New → Target
2. Select "Widget Extension"
3. Product Name: `MetronomeWidget`
4. Check "Include Configuration Intent" → UNCHECK (we don't need it)
5. Click "Finish"
6. When prompted "Activate MetronomeWidget scheme?", click "Activate"
7. Select the `MetronomeWidget` target
8. Go to "Signing & Capabilities"
9. Click "+ Capability"
10. Add "App Groups"
11. Click "+" and add the same group: `group.com.danielbutler.MetronomeApp`
12. Ensure checkbox is checked

**Step 1: Verify widget target was created**

Run: `ls -la MetronomeApp/MetronomeWidget/`

Expected: Directory exists with MetronomeWidget.swift and other files

**Step 2: Commit**

```bash
git add MetronomeApp/MetronomeWidget MetronomeApp/MetronomeApp.xcodeproj
git commit -m "feat: create Widget Extension target"
```

---

## Task 6: Implement App Intents

**Files:**
- Create: `MetronomeApp/MetronomeApp/MetronomeAppIntents.swift`

**Step 1: Create App Intents file**

Create `MetronomeApp/MetronomeApp/MetronomeAppIntents.swift`:

```swift
//
//  MetronomeAppIntents.swift
//  MetronomeApp
//
//  Created by Claude on 12/23/25.
//

import AppIntents
import Foundation

struct StartMetronomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Metronome"
    static var description = IntentDescription("Starts the metronome playback")

    func perform() async throws -> some IntentResult {
        let sharedState = SharedMetronomeState.shared
        sharedState.isPlaying = true
        sharedState.notifyWidgetUpdate()

        // Post notification to app
        NotificationCenter.default.post(name: .startMetronome, object: nil)

        return .result()
    }
}

struct StopMetronomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Metronome"
    static var description = IntentDescription("Stops the metronome playback")

    func perform() async throws -> some IntentResult {
        let sharedState = SharedMetronomeState.shared
        sharedState.isPlaying = false
        sharedState.notifyWidgetUpdate()

        // Post notification to app
        NotificationCenter.default.post(name: .stopMetronome, object: nil)

        return .result()
    }
}

struct IncrementBPMIntent: AppIntent {
    static var title: LocalizedStringResource = "Increment BPM"
    static var description = IntentDescription("Increases BPM by 1")

    func perform() async throws -> some IntentResult {
        let sharedState = SharedMetronomeState.shared
        let currentBPM = sharedState.bpm

        if currentBPM < 230 {
            sharedState.bpm = currentBPM + 1
            sharedState.notifyWidgetUpdate()

            // Post notification to app
            NotificationCenter.default.post(name: .bpmChanged, object: nil)
        }

        return .result()
    }
}

struct DecrementBPMIntent: AppIntent {
    static var title: LocalizedStringResource = "Decrement BPM"
    static var description = IntentDescription("Decreases BPM by 1")

    func perform() async throws -> some IntentResult {
        let sharedState = SharedMetronomeState.shared
        let currentBPM = sharedState.bpm

        if currentBPM > 150 {
            sharedState.bpm = currentBPM - 1
            sharedState.notifyWidgetUpdate()

            // Post notification to app
            NotificationCenter.default.post(name: .bpmChanged, object: nil)
        }

        return .result()
    }
}

// Notification names for app to listen to
extension Notification.Name {
    static let startMetronome = Notification.Name("startMetronome")
    static let stopMetronome = Notification.Name("stopMetronome")
    static let bpmChanged = Notification.Name("bpmChanged")
}
```

**Step 2: Add to Xcode project (XCODE STEP)**

1. Add file to both MetronomeApp AND MetronomeWidget targets:
   - Right-click `MetronomeApp` folder
   - "Add Files to 'MetronomeApp'..."
   - Select `MetronomeAppIntents.swift`
   - In "Add to targets", check BOTH `MetronomeApp` AND `MetronomeWidget`
   - Click "Add"

**Step 3: Build to verify**

Run: `cd MetronomeApp && xcodebuild build -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add MetronomeApp/MetronomeApp/MetronomeAppIntents.swift MetronomeApp/MetronomeApp.xcodeproj
git commit -m "feat: add App Intents for widget actions"
```

---

## Task 7: Update ContentView to Handle Intent Notifications

**Files:**
- Modify: `MetronomeApp/MetronomeApp/ContentView.swift`

**Step 1: Add notification observers in onAppear**

Update the `onAppear` method to add notification observers:

```swift
        .onAppear {
            // Load from shared state
            bpm = sharedState.bpm
            volume = sharedState.volume
            isPlaying = sharedState.isPlaying

            setupAudioEngine()

            // Resume playback if was playing
            if isPlaying {
                startMetronome()
            }

            // Listen to widget intent notifications
            NotificationCenter.default.addObserver(
                forName: .startMetronome,
                object: nil,
                queue: .main
            ) { _ in
                if !self.isPlaying {
                    self.isPlaying = true
                    self.startMetronome()
                }
            }

            NotificationCenter.default.addObserver(
                forName: .stopMetronome,
                object: nil,
                queue: .main
            ) { _ in
                if self.isPlaying {
                    self.isPlaying = false
                    self.stopMetronome()
                }
            }

            NotificationCenter.default.addObserver(
                forName: .bpmChanged,
                object: nil,
                queue: .main
            ) { _ in
                self.bpm = self.sharedState.bpm
                if self.isPlaying {
                    self.handleBPMChange()
                }
            }
        }
```

**Step 2: Remove observers in onDisappear**

Update the `onDisappear` method:

```swift
        .onDisappear {
            cleanupAudio()
            NotificationCenter.default.removeObserver(self)
        }
```

**Step 3: Build to verify**

Run: `cd MetronomeApp && xcodebuild build -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add MetronomeApp/MetronomeApp/ContentView.swift
git commit -m "feat: handle widget intent notifications in app"
```

---

## Task 8: Implement Lock Screen Widget UI

**Files:**
- Modify: `MetronomeApp/MetronomeWidget/MetronomeWidget.swift`

**Step 1: Replace MetronomeWidget.swift contents**

Replace the entire contents of `MetronomeApp/MetronomeWidget/MetronomeWidget.swift`:

```swift
//
//  MetronomeWidget.swift
//  MetronomeWidget
//
//  Created by Claude on 12/23/25.
//

import WidgetKit
import SwiftUI
import AppIntents

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), bpm: 180, isPlaying: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let sharedState = SharedMetronomeState.shared
        let entry = SimpleEntry(
            date: Date(),
            bpm: sharedState.bpm,
            isPlaying: sharedState.isPlaying
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let sharedState = SharedMetronomeState.shared
        let entry = SimpleEntry(
            date: Date(),
            bpm: sharedState.bpm,
            isPlaying: sharedState.isPlaying
        )

        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let bpm: Int
    let isPlaying: Bool
}

struct MetronomeWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        HStack(spacing: 8) {
            // BPM decrease button
            Button(intent: DecrementBPMIntent()) {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            // BPM display
            VStack(spacing: 2) {
                Text("\(entry.bpm)")
                    .font(.system(size: 24, weight: .bold))
                Text("BPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 50)

            // BPM increase button
            Button(intent: IncrementBPMIntent()) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Divider()

            // Play/Stop button
            Button(intent: entry.isPlaying ? StopMetronomeIntent() : StartMetronomeIntent()) {
                Image(systemName: entry.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(entry.isPlaying ? .red : .green)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
    }
}

struct MetronomeWidget: Widget {
    let kind: String = "MetronomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MetronomeWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Metronome")
        .description("Control your metronome from the lock screen")
        .supportedFamilies([.accessoryRectangular])
    }
}
```

**Step 2: Add SharedMetronomeState to widget target (XCODE STEP)**

1. In Project Navigator, select `SharedMetronomeState.swift`
2. In File Inspector (right panel), under "Target Membership"
3. Check the box next to `MetronomeWidget` (in addition to MetronomeApp)

**Step 3: Build widget**

Run: `cd MetronomeApp && xcodebuild build -scheme MetronomeWidget -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add MetronomeApp/MetronomeWidget/MetronomeWidget.swift MetronomeApp/MetronomeApp.xcodeproj
git commit -m "feat: implement lock screen widget UI"
```

---

## Task 9: Test Background Audio

**Manual Testing Steps:**

1. Build and run the app on a real device or simulator
2. Start the metronome
3. Lock the device
4. Verify metronome continues playing
5. Unlock and verify it's still playing
6. Switch to another app
7. Verify metronome continues playing in background

**Expected Result:** Metronome plays continuously regardless of app state

---

## Task 10: Test Lock Screen Widget

**Manual Testing Steps:**

1. Build and run the app
2. Long-press on the lock screen
3. Tap "Customize"
4. Tap the widget area below the time
5. Search for "Metronome"
6. Add the Metronome widget
7. Tap "Done"
8. Lock the device
9. Wake the screen (don't unlock)
10. Verify widget shows current BPM
11. Tap the + button, verify BPM increases
12. Tap the - button, verify BPM decreases
13. Tap the play button, verify metronome starts
14. Tap the stop button, verify metronome stops
15. Unlock device and open app
16. Verify app state matches widget state

**Expected Result:** All widget buttons work and sync with app state

---

## Final Verification

**Step 1: Build all targets**

Run: `cd MetronomeApp && xcodebuild build -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: BUILD SUCCEEDED

**Step 2: Run unit tests**

Run: `make test-unit`

Expected: All tests pass

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete lock screen widget implementation

- Background audio playback enabled
- App Group for state sharing
- Interactive lock screen widget
- BPM controls on lock screen
- Play/stop from lock screen
"
```

---

## Notes for Engineer

**App Groups:** The App Group ID must match exactly in:
- Main app target capabilities
- Widget extension target capabilities
- SharedMetronomeState.swift appGroupID constant

**WidgetKit Import:** The `#if canImport(WidgetKit)` check in SharedMetronomeState prevents build errors when WidgetKit isn't available.

**Lock Screen Widgets:** Only `.accessoryRectangular` family works on lock screen. This provides a rectangular widget space.

**Testing on Simulator:** Lock screen widget customization works on iOS 17+ simulator. Background audio testing is best done on a real device.

**Xcode Steps:** Tasks marked with (XCODE STEP) require manual Xcode GUI interaction. Claude cannot automate these but should verify the results.
