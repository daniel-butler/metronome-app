# Tappable BPM Input Design

## Problem

Users cannot type a specific BPM value — they must tap +/- buttons one at a time.

## Design

Tap the BPM number to switch it to an inline `TextField` with a number keyboard. The text field is focused immediately. When the user submits or taps away, the value is clamped to 150–230, applied, and the display reverts to the static `Text` view.

### State

- `@State var isEditingBPM: Bool` — toggles between `Text` and `TextField`
- `@State var bpmText: String` — holds the in-progress typed value
- `@FocusState var isBPMFieldFocused: Bool` — auto-focuses the text field on appear

### Behavior

- **On tap:** Set `isEditingBPM = true`, populate `bpmText` with current BPM string, focus the field
- **On commit/focus loss:** Parse the integer, clamp to 150–230, update `bpm`, sync shared state, update Live Activity, set `isEditingBPM = false`
- **Keyboard:** `.numberPad`
- **Visual:** Same font and size as the current `Text("\(bpm)")` so the layout doesn't jump

### Files changed

- `MetronomeApp/MetronomeApp/ContentView.swift` — replace BPM `Text` with conditional `Text`/`TextField`, add state vars, add commit logic
