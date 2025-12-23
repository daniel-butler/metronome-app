# Lock Screen Widget Design

**Date:** 2025-12-23
**Goal:** Add background playback and interactive lock screen widget to metronome app

## Requirements

- Metronome continues playing when phone is locked or in other apps
- Lock screen widget shows BPM and control buttons
- Widget buttons: Play/Stop, +, -
- Simplest possible architecture

## Architecture

### 1. Background Audio
- Add `UIBackgroundModes` with `audio` to Info.plist
- Allows metronome to play indefinitely while locked

### 2. App Group
- Create App Group identifier (e.g., `group.com.yourname.metronome`)
- Share state between app and widget via UserDefaults in App Group
- Shared state: BPM, isPlaying, volume

### 3. Lock Screen Widget Extension
- Create WidgetKit extension target in Xcode
- Widget type: AccessoryRectangular (lock screen)
- Display: BPM number, Play/Stop button, +/- buttons

### 4. App Intents
- `StartMetronomeIntent` - Starts playback
- `StopMetronomeIntent` - Stops playback
- `IncrementBPMIntent` - Increases BPM by 1
- `DecrementBPMIntent` - Decreases BPM by 1

## Implementation Steps

1. Add background audio capability to Info.plist
2. Create App Group in Xcode
3. Create shared data manager for App Group
4. Update ContentView to use shared data
5. Create Widget Extension in Xcode
6. Implement App Intents for button actions
7. Design widget UI layout
8. Test background playback
9. Test widget interactions

## Technical Notes

- Lock screen widgets have limited space - prioritize BPM display and essential controls
- Widget refreshes when shared data changes
- App Intents execute in app process, not widget process
- Background audio requires proper audio session configuration (already in place via AudioSessionManager)
