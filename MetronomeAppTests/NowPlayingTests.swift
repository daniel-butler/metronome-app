//
//  NowPlayingTests.swift
//  MetronomeAppTests
//
//  Tests that MPNowPlayingInfoCenter is updated when engine state changes.
//

import XCTest
import MediaPlayer
@testable import MetronomeApp

@MainActor
final class NowPlayingTests: XCTestCase {

    private var engine: MetronomeEngine!

    override func setUp() {
        engine = MetronomeEngine()
        engine.setup()
    }

    override func tearDown() {
        engine.teardown()
        engine = nil
    }

    func testNowPlayingSetOnSetup() {
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertNotNil(info, "Now Playing info should be set after setup")
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "180 SPM")
        XCTAssertEqual(info?[MPMediaItemPropertyArtist] as? String, "Stopped")
    }

    func testNowPlayingUpdatesOnToggle() {
        engine.togglePlayback()

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "180 SPM")
        XCTAssertEqual(info?[MPMediaItemPropertyArtist] as? String, "Playing")
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.0)

        engine.togglePlayback()

        let stoppedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(stoppedInfo?[MPMediaItemPropertyArtist] as? String, "Stopped")
        XCTAssertEqual(stoppedInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0.0)
    }

    func testNowPlayingUpdatesOnBPMChange() {
        engine.incrementBPM()

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "181 SPM")

        engine.decrementBPM()
        engine.decrementBPM()

        let info2 = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info2?[MPMediaItemPropertyTitle] as? String, "179 SPM")
    }

    func testNowPlayingUpdatesOnSetBPM() {
        engine.setBPM(200)

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "200 SPM")
    }

    func testPlaybackStateMatchesEngine() {
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)

        engine.togglePlayback()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)

        engine.togglePlayback()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
    }

    func testRemoteCommandsRegistered() {
        let commandCenter = MPRemoteCommandCenter.shared()
        // Commands should be enabled (have targets) after setup
        XCTAssertTrue(commandCenter.playCommand.isEnabled)
        XCTAssertTrue(commandCenter.pauseCommand.isEnabled)
        XCTAssertTrue(commandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertTrue(commandCenter.nextTrackCommand.isEnabled)
        XCTAssertTrue(commandCenter.previousTrackCommand.isEnabled)
    }
}
