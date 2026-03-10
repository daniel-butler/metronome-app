//
//  StateChangeObserverTests.swift
//  MetronomeAppTests
//

import XCTest
@testable import MetronomeApp

final class StateChangeObserverTests: XCTestCase {

    private var observer: StateChangeObserver!

    override func setUp() {
        super.setUp()
        observer = StateChangeObserver()
    }

    override func tearDown() {
        observer.stopObserving()
        observer = nil
        super.tearDown()
    }

    func testStartCommandCallsOnPlayCommand() {
        let expectation = expectation(description: "play command received")

        observer.startObserving(
            onStateChanged: { XCTFail("Should not call onStateChanged for a play command") },
            onPlayCommand: { expectation.fulfill() },
            onStopCommand: { XCTFail("Should not call onStopCommand for a play command") }
        )

        // Post play command Darwin notification
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(MetronomeNotification.commandStart as CFString),
            nil, nil, true
        )

        waitForExpectations(timeout: 2)
    }

    func testStopCommandCallsOnStopCommand() {
        let expectation = expectation(description: "stop command received")

        observer.startObserving(
            onStateChanged: { XCTFail("Should not call onStateChanged for a stop command") },
            onPlayCommand: { XCTFail("Should not call onPlayCommand for a stop command") },
            onStopCommand: { expectation.fulfill() }
        )

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(MetronomeNotification.commandStop as CFString),
            nil, nil, true
        )

        waitForExpectations(timeout: 2)
    }

    func testStateChangedCallsOnStateChanged() {
        let expectation = expectation(description: "state changed received")

        observer.startObserving(
            onStateChanged: { expectation.fulfill() },
            onPlayCommand: { XCTFail("Should not call onPlayCommand for a state change") },
            onStopCommand: { XCTFail("Should not call onStopCommand for a state change") }
        )

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(MetronomeNotification.stateChanged as CFString),
            nil, nil, true
        )

        waitForExpectations(timeout: 2)
    }
}
