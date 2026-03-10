//
//  MetronomeNotificationTests.swift
//  MetronomeAppTests
//

import XCTest
@testable import MetronomeApp

final class MetronomeNotificationTests: XCTestCase {

    func testNotificationNamesAreDefined() {
        // Three distinct notification names should exist
        XCTAssertFalse(MetronomeNotification.stateChanged.isEmpty)
        XCTAssertFalse(MetronomeNotification.commandStart.isEmpty)
        XCTAssertFalse(MetronomeNotification.commandStop.isEmpty)
    }

    func testNotificationNamesAreDistinct() {
        // Each notification name must be unique to avoid cross-talk
        XCTAssertNotEqual(MetronomeNotification.stateChanged, MetronomeNotification.commandStart)
        XCTAssertNotEqual(MetronomeNotification.stateChanged, MetronomeNotification.commandStop)
        XCTAssertNotEqual(MetronomeNotification.commandStart, MetronomeNotification.commandStop)
    }
}
