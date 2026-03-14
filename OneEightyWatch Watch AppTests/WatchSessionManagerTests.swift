//
//  WatchSessionManagerTests.swift
//  OneEightyWatch Watch AppTests
//
//  Tests for WatchSessionManager optimistic updates and state management.
//

import XCTest
@testable import OneEightyWatch_Watch_App

@MainActor
final class WatchSessionManagerTests: XCTestCase {

    private var session: WatchSessionManager!

    override func setUp() {
        session = WatchSessionManager()
    }

    override func tearDown() {
        session = nil
    }

    // MARK: - Default State

    func testDefaultBPM() {
        XCTAssertEqual(session.bpm, 180)
    }

    func testDefaultIsPlaying() {
        XCTAssertFalse(session.isPlaying)
    }

    func testDefaultIsReachable() {
        XCTAssertFalse(session.isReachable)
    }

    // MARK: - Optimistic Toggle (Bug 2 fix)

    func testToggleUpdatesIsPlayingLocally() {
        XCTAssertFalse(session.isPlaying)
        session.toggle()
        XCTAssertTrue(session.isPlaying, "toggle() should optimistically update isPlaying")
        session.toggle()
        XCTAssertFalse(session.isPlaying, "toggle() should flip isPlaying back")
    }

    // MARK: - Optimistic BPM (Bug 1 fix)

    func testIncrementBPMUpdatesLocally() {
        let initial = session.bpm
        session.incrementBPM()
        XCTAssertEqual(session.bpm, initial + 1, "incrementBPM() should optimistically update bpm")
    }

    func testDecrementBPMUpdatesLocally() {
        let initial = session.bpm
        session.decrementBPM()
        XCTAssertEqual(session.bpm, initial - 1, "decrementBPM() should optimistically update bpm")
    }

    func testIncrementBPMRespectsUpperBound() {
        session.bpm = 230
        session.incrementBPM()
        XCTAssertEqual(session.bpm, 230, "incrementBPM() should not exceed 230")
    }

    func testDecrementBPMRespectsLowerBound() {
        session.bpm = 150
        session.decrementBPM()
        XCTAssertEqual(session.bpm, 150, "decrementBPM() should not go below 150")
    }

    // MARK: - Rapid Operations

    func testRapidIncrements() {
        session.bpm = 195
        for _ in 0..<15 {
            session.incrementBPM()
        }
        XCTAssertEqual(session.bpm, 210, "15 increments from 195 should reach 210")
    }

    func testRapidIncrementsClampAtMax() {
        session.bpm = 220
        for _ in 0..<20 {
            session.incrementBPM()
        }
        XCTAssertEqual(session.bpm, 230, "Rapid increments should clamp at 230")
    }

    func testRapidToggles() {
        // Even number of toggles should return to original state
        let initial = session.isPlaying
        for _ in 0..<10 {
            session.toggle()
        }
        XCTAssertEqual(session.isPlaying, initial, "10 toggles should return to original state")
    }

    func testOddTogglesFlipState() {
        let initial = session.isPlaying
        for _ in 0..<7 {
            session.toggle()
        }
        XCTAssertNotEqual(session.isPlaying, initial, "7 toggles should flip state")
    }
}
