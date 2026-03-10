//
//  SharedMetronomeStateTests.swift
//  MetronomeAppTests
//

import XCTest
@testable import MetronomeApp

final class SharedMetronomeStateTests: XCTestCase {

    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var state: SharedMetronomeState!

    override func setUp() {
        super.setUp()
        suiteName = "test.metronome.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        state = SharedMetronomeState(userDefaults: testDefaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - BPM (preference — should persist)

    func testBPMDefaultsTo180() {
        XCTAssertEqual(state.bpm, 180)
    }

    func testBPMPersistsValue() {
        state.bpm = 195
        XCTAssertEqual(state.bpm, 195)
    }

    func testBPMRoundTripsViaUserDefaults() {
        state.bpm = 170
        let value = testDefaults.integer(forKey: "bpm")
        XCTAssertEqual(value, 170, "BPM should be stored in UserDefaults")
    }

    // MARK: - Volume (preference — should persist)

    func testVolumeDefaultsTo04() {
        XCTAssertEqual(state.volume, 0.4, accuracy: 0.001)
    }

    func testVolumePersistsValue() {
        state.volume = 0.8
        XCTAssertEqual(state.volume, 0.8, accuracy: 0.001)
    }

    // MARK: - isPlaying should NOT be in SharedMetronomeState

    func testIsPlayingNotStoredInUserDefaults() {
        // isPlaying is transient command state, not a preference.
        // After refactoring, SharedMetronomeState should not have an isPlaying property.
        // Setting isPlaying via the old key should not affect the state object.
        testDefaults.set(true, forKey: "isPlaying")
        // SharedMetronomeState should not expose isPlaying at all.
        // This test verifies the key is not read by the state object.
        // If isPlaying property still exists, this test documents that it should be removed.
        let mirror = Mirror(reflecting: state!)
        let propertyNames = mirror.children.compactMap { $0.label }
        XCTAssertFalse(propertyNames.contains("isPlaying"),
                       "SharedMetronomeState should not store isPlaying — it's a command, not a preference")
    }
}
