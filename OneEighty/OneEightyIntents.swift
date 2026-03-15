//
//  OneEightyIntents.swift
//  OneEighty
//
//  Created by Claude on 12/23/25.
//

import AppIntents
import Foundation
import os

private let logger = Logger(subsystem: "com.danielbutler.OneEighty", category: "Intents")

struct ToggleOneEightyIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle OneEighty"
    static var description = IntentDescription("Toggles metronome playback on/off")

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = SharedStateStore.shared
        let wasPlaying = store.isPlaying
        let nowPlaying = !wasPlaying
        logger.info("ToggleOneEightyIntent — wasPlaying=\(wasPlaying), nowPlaying=\(nowPlaying)")

        store.isPlaying = nowPlaying
        let bpm = store.bpm
        IntentActivityDebouncer.shared.submit(bpm: bpm, isPlaying: nowPlaying, priority: .critical)

        store.postCommand(nowPlaying ? .start : .stop)
        return .result()
    }
}

struct StartOneEightyIntent: AppIntent {
    static var title: LocalizedStringResource = "Start OneEighty"
    static var description = IntentDescription("Starts the metronome playback")

    @MainActor
    func perform() async throws -> some IntentResult {
        logger.info("StartOneEightyIntent.perform()")
        let store = SharedStateStore.shared
        store.isPlaying = true
        let bpm = store.bpm
        IntentActivityDebouncer.shared.submit(bpm: bpm, isPlaying: true, priority: .critical)
        store.postCommand(.start)
        return .result()
    }
}

struct StopOneEightyIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop OneEighty"
    static var description = IntentDescription("Stops the metronome playback")

    @MainActor
    func perform() async throws -> some IntentResult {
        logger.info("StopOneEightyIntent.perform()")
        let store = SharedStateStore.shared
        store.isPlaying = false
        let bpm = store.bpm
        IntentActivityDebouncer.shared.submit(bpm: bpm, isPlaying: false, priority: .critical)
        store.postCommand(.stop)
        return .result()
    }
}

struct IncrementBPMIntent: AppIntent {
    static var title: LocalizedStringResource = "Increment SPM"
    static var description = IntentDescription("Increases SPM by 1")

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = SharedStateStore.shared
        let currentBPM = store.bpm
        logger.info("IncrementBPMIntent — current=\(currentBPM)")
        if currentBPM < 230 {
            let newBPM = currentBPM + 1
            store.bpm = newBPM
            let isPlaying = store.isPlaying
            IntentActivityDebouncer.shared.submit(bpm: newBPM, isPlaying: isPlaying, priority: .normal)
        }
        return .result()
    }
}

struct DecrementBPMIntent: AppIntent {
    static var title: LocalizedStringResource = "Decrement SPM"
    static var description = IntentDescription("Decreases SPM by 1")

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = SharedStateStore.shared
        let currentBPM = store.bpm
        logger.info("DecrementBPMIntent — current=\(currentBPM)")
        if currentBPM > 150 {
            let newBPM = currentBPM - 1
            store.bpm = newBPM
            let isPlaying = store.isPlaying
            IntentActivityDebouncer.shared.submit(bpm: newBPM, isPlaying: isPlaying, priority: .normal)
        }
        return .result()
    }
}
