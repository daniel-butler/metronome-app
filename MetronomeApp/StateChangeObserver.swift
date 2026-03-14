//
//  StateChangeObserver.swift
//  MetronomeApp
//
//  Created by Claude on 2/11/26.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.danielbutler.MetronomeApp", category: "Observer")

class StateChangeObserver {
    private var onStateChanged: (() -> Void)?
    private var onPlayCommand: (() -> Void)?
    private var onStopCommand: (() -> Void)?
    private var isObserving = false

    func startObserving(
        onStateChanged: @escaping () -> Void,
        onPlayCommand: @escaping () -> Void,
        onStopCommand: @escaping () -> Void
    ) {
        self.onStateChanged = onStateChanged
        self.onPlayCommand = onPlayCommand
        self.onStopCommand = onStopCommand
        isObserving = true

        let observer = Unmanaged.passUnretained(self).toOpaque()
        let center = CFNotificationCenterGetDarwinNotifyCenter()

        // Observe state changes (preferences like bpm)
        CFNotificationCenterAddObserver(
            center, observer,
            { (_, observer, name, _, _) in
                guard let observer else { return }
                let instance = Unmanaged<StateChangeObserver>.fromOpaque(observer).takeUnretainedValue()
                logger.info("Darwin notification: stateChanged")
                Task { @MainActor in instance.onStateChanged?() }
            },
            MetronomeNotification.stateChanged as CFString,
            nil, .deliverImmediately
        )

        // Observe play command
        CFNotificationCenterAddObserver(
            center, observer,
            { (_, observer, name, _, _) in
                guard let observer else { return }
                let instance = Unmanaged<StateChangeObserver>.fromOpaque(observer).takeUnretainedValue()
                logger.info("Darwin notification: commandStart")
                Task { @MainActor in instance.onPlayCommand?() }
            },
            MetronomeNotification.commandStart as CFString,
            nil, .deliverImmediately
        )

        // Observe stop command
        CFNotificationCenterAddObserver(
            center, observer,
            { (_, observer, name, _, _) in
                guard let observer else { return }
                let instance = Unmanaged<StateChangeObserver>.fromOpaque(observer).takeUnretainedValue()
                logger.info("Darwin notification: commandStop")
                Task { @MainActor in instance.onStopCommand?() }
            },
            MetronomeNotification.commandStop as CFString,
            nil, .deliverImmediately
        )

        logger.info("Started observing Darwin notifications (stateChanged, commandStart, commandStop)")
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, nil, nil)
        onStateChanged = nil
        onPlayCommand = nil
        onStopCommand = nil
    }

    deinit {
        stopObserving()
    }
}
