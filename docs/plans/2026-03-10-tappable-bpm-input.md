# Tappable BPM Input Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users tap the BPM number to type a value directly via number keyboard.

**Architecture:** Add inline editing state to ContentView. Tap toggles between static `Text` and a `TextField` with `.numberPad` keyboard. On commit or focus loss, clamp to 150–230 and apply.

**Tech Stack:** SwiftUI (`TextField`, `@FocusState`)

---

### Task 1: Add tappable inline BPM editing

**Files:**
- Modify: `MetronomeApp/MetronomeApp/ContentView.swift:14-49`

**Step 1: Add state properties**

Add these three properties after the existing `@State` declarations (after line 26):

```swift
@State private var isEditingBPM: Bool = false
@State private var bpmText: String = ""
@FocusState private var isBPMFieldFocused: Bool
```

**Step 2: Add the commitBPM helper**

Add this method in the `// MARK: - BPM Control` section (after `handleBPMChange()`):

```swift
private func commitBPM() {
    isEditingBPM = false
    isBPMFieldFocused = false
    guard let typed = Int(bpmText) else { return }
    let clamped = min(230, max(150, typed))
    if clamped != bpm {
        bpm = clamped
        sharedState.bpm = clamped
        if isPlaying {
            handleBPMChange()
        }
        Task { @MainActor in
            LiveActivityManager.shared.updateActivity(bpm: bpm, isPlaying: isPlaying)
        }
    }
}
```

**Step 3: Replace the BPM Display section**

Replace the current BPM Display block (lines 42-49):

```swift
            // BPM Display
            VStack(spacing: 8) {
                Text("\(bpm)")
                    .font(.system(size: 80, weight: .bold))
                Text("SPM")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
```

With:

```swift
            // BPM Display
            VStack(spacing: 8) {
                if isEditingBPM {
                    TextField("BPM", text: $bpmText)
                        .font(.system(size: 80, weight: .bold))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .focused($isBPMFieldFocused)
                        .onSubmit { commitBPM() }
                        .onChange(of: isBPMFieldFocused) { _, focused in
                            if !focused { commitBPM() }
                        }
                        .frame(width: 200)
                } else {
                    Text("\(bpm)")
                        .font(.system(size: 80, weight: .bold))
                        .onTapGesture {
                            bpmText = "\(bpm)"
                            isEditingBPM = true
                            isBPMFieldFocused = true
                        }
                }
                Text("SPM")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
```

**Step 4: Build and test manually**

Run: `cd /Users/danielbutler/code/metronome-app && xcodebuild build -project MetronomeApp/MetronomeApp.xcodeproj -scheme MetronomeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

Manual test:
1. Launch app in simulator
2. Tap the BPM number — should switch to text field with number keyboard
3. Type a value (e.g. 200) — should accept
4. Tap elsewhere — should apply and revert to static text
5. Type 999 — should clamp to 230
6. Type 50 — should clamp to 150

**Step 5: Commit**

```bash
cd /Users/danielbutler/code/metronome-app/MetronomeApp
git add MetronomeApp/ContentView.swift
git commit -m "feat: tap BPM display to type a value directly"
```
