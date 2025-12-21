# Running Metronome App Design

**Date:** 2025-12-21
**Purpose:** iOS metronome app for running cadence tracking

## Overview

Simple, focused metronome app for runners to maintain consistent cadence. Supports 150-230 BPM range with precise timing, background playback, and minimal UI for easy use while running.

## Requirements

### Core Features
1. **BPM Control**: Adjust cadence from 150-230 BPM using +/- buttons (±1 BPM per tap)
2. **Volume Control**: Slider to adjust tick volume (default 40%)
3. **Start/Stop**: Single button to control playback
4. **Background Playback**: Continue playing when screen is locked or app is backgrounded

### Non-Requirements
- Visual metronome animation (not needed)
- BPM presets or favorites
- Different time signatures
- Multiple sound options

## Architecture

### Component Structure

**Three-layer architecture:**

1. **UI Layer (SwiftUI)**: Single screen with controls
2. **Metronome Engine**: Timing and audio playback
3. **Audio Session Manager**: Background playback configuration

### Technology Stack

- **UI**: SwiftUI with `@Observable` (or `ObservableObject`) for state management
- **Audio**: `AVAudioEngine` with `AVAudioPlayerNode` for precise timing
- **Background Audio**: `AVAudioSession` with `.playback` category
- **Timing**: `Timer.scheduledTimer` with BPM-calculated intervals

### State Management

**MetronomeViewModel holds:**
- Current BPM: 150-230 range, default 180
- Volume level: 0.0-1.0, default 0.4 (40%)
- Playing state: Boolean
- Was playing before interruption: Boolean (for auto-resume)

## User Interface

### Layout (top to bottom)

1. **BPM Display Area**:
   - Large, bold BPM number
   - Label: "BPM" or "Steps/Min"
   - Clean, minimal design for at-a-glance reading

2. **BPM Controls**:
   - Minus button (left) - circular, outlined
   - BPM number display (center)
   - Plus button (right) - circular, outlined
   - Large touch targets (minimum 44x44 points)

3. **Volume Control**:
   - Speaker icon (left)
   - Horizontal slider (middle)
   - Visual feedback as volume increases

4. **Start/Stop Button**:
   - Full-width button
   - Text: "START" when stopped, "STOP" when playing
   - Visual state change when active
   - High contrast for outdoor visibility

### Design Principles

- Clean, minimal interface
- Large touch targets for easy interaction while running
- High contrast for outdoor visibility
- Light background with dark text

## Metronome Engine

### Audio Setup

**AVAudioEngine Architecture:**
1. Create `AVAudioEngine` instance with `AVAudioPlayerNode`
2. Load tick sound from bundled WAV file into `AVAudioPCMBuffer`
3. Connect player node to engine's main mixer node
4. Apply volume to mixer node

**Timing Mechanism:**
1. Calculate interval from BPM: `interval = 60.0 / BPM` seconds
2. Use `Timer.scheduledTimer` with calculated interval
3. On each timer fire, schedule tick sound on player node
4. Alternative consideration: `AVAudioEngine`'s sample-accurate scheduling for better precision

**Background Audio Configuration:**
1. Set `AVAudioSession.Category` to `.playback`
2. Set mode to `.default`
3. Enable `.mixWithOthers` option (optional, allows playing alongside music)
4. Activate session before starting playback

### State Transitions

**Start:**
1. Configure audio session
2. Start engine
3. Schedule timer
4. Begin playing ticks

**Stop:**
1. Invalidate timer
2. Stop player node
3. Optionally deactivate audio session

**BPM Change (while playing):**
1. Use 0.3 second debounce delay
2. After delay: stop current timer
3. Recalculate interval
4. Restart timer with new interval
5. Next tick happens at new BPM interval

**Volume Change:**
- Update mixer node's output volume in real-time (no restart needed)

### Debouncing Strategy

- 0.3 second debounce delay on BPM changes while playing
- Cancel pending debounce if user stops metronome
- Prevents timing glitches from rapid button tapping
- Only applies when metronome is active

## Error Handling & Edge Cases

### Audio Session Management

**Interruptions (phone calls, alarms):**
1. Listen for `AVAudioSession.interruptionNotification`
2. Automatically stop metronome when interrupted
3. Track "was playing before interruption" state
4. Auto-resume when interruption ends (if was playing)

**Audio Engine Failures:**
1. Log error if engine fails to start
2. Show alert: "Unable to start audio"
3. Disable START button until resolved

### State Validation

**BPM Bounds:**
- Disable minus button when BPM = 150
- Disable plus button when BPM = 230
- Validate any programmatic BPM changes

**Volume Bounds:**
- Clamp slider values to 0.0-1.0 range
- Handle edge case: volume at 0% (silent but timing continues)

**Debounce Edge Cases:**
- Cancel pending debounce on stop
- Handle rapid start/stop cycles
- Ensure debounce doesn't block immediate stop

### Background Behavior

- Metronome continues when screen locks
- Metronome continues when app backgrounds
- No special handling needed with proper AVAudioSession configuration

## Testing Strategy

### Manual Testing Focus Areas

1. **BPM Accuracy**: Use external metronome to verify timing precision
2. **Background Playback**: Lock screen and verify ticks continue
3. **Interruption Handling**: Test with phone calls and alarms, verify auto-resume
4. **BPM Changes While Playing**: Verify smooth transition with debouncing
5. **Button States**: Verify +/- buttons disable at bounds (150/230)
6. **Volume Control**: Verify slider affects tick volume properly

### Edge Cases to Test

- Rapidly tapping +/- buttons (debounce should handle gracefully)
- Changing BPM immediately after starting
- Starting/stopping rapidly in succession
- Volume at 0% (silent but timing continues)
- Volume at 100% (not distorted)
- App switching and returning to foreground
- Interruption during BPM change debounce period

## Implementation Plan

### Phase 1: Basic UI
- Layout BPM display with large number
- Add +/- buttons with proper sizing
- Add volume slider with speaker icon
- Add START/STOP button
- Wire up basic state management

### Phase 2: Audio Engine
- Set up AVAudioEngine and AVAudioPlayerNode
- Find/create and bundle tick sound WAV file
- Load sound into AVAudioPCMBuffer
- Implement basic playback test

### Phase 3: Timing
- Implement timer-based tick scheduling
- BPM-to-interval conversion
- Connect +/- buttons to BPM state
- Connect START/STOP to playback

### Phase 4: Background Audio
- Configure AVAudioSession for background playback
- Test with screen lock
- Test with app backgrounding

### Phase 5: Polish
- Implement debouncing for BPM changes
- Add interruption handling with auto-resume
- Implement button state management (disable at bounds)
- Set default values (180 BPM, 40% volume)

## Sound Asset

- Use bundled WAV file for tick sound
- Classic metronome "tick" sound
- Short duration (50-100ms)
- Clean, distinct sound audible during outdoor running
