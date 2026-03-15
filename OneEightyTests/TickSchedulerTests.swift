//
//  TickSchedulerTests.swift
//  OneEightyTests
//
//  Tests for TickScheduler sample-position math.
//

import XCTest
import AVFoundation
@testable import OneEighty

final class TickSchedulerTests: XCTestCase {

    // MARK: - Sample interval math

    func testSamplesPerBeatAt180BPM() {
        // 60 / 180 = 0.3333s * 24000 Hz = 8000 samples
        let samples = TickScheduler.samplesPerBeat(bpm: 180, sampleRate: 24000)
        XCTAssertEqual(samples, 8000)
    }

    func testSamplesPerBeatAt150BPM() {
        // 60 / 150 = 0.4s * 24000 Hz = 9600 samples
        let samples = TickScheduler.samplesPerBeat(bpm: 150, sampleRate: 24000)
        XCTAssertEqual(samples, 9600)
    }

    func testSamplesPerBeatAt230BPM() {
        // 60 / 230 = 0.26087s * 24000 Hz = 6260.87 -> 6261 samples (rounded)
        let samples = TickScheduler.samplesPerBeat(bpm: 230, sampleRate: 24000)
        XCTAssertEqual(samples, 6261)
    }

    func testSamplesPerBeatAt44100Hz() {
        // 60 / 180 = 0.3333s * 44100 Hz = 14700 samples
        let samples = TickScheduler.samplesPerBeat(bpm: 180, sampleRate: 44100)
        XCTAssertEqual(samples, 14700)
    }

    // MARK: - Beat position sequences

    func testBeatPositionsAreEvenlySpaced() {
        let interval = TickScheduler.samplesPerBeat(bpm: 180, sampleRate: 24000)
        let positions = (0..<5).map { AVAudioFramePosition($0) * interval }
        XCTAssertEqual(positions, [0, 8000, 16000, 24000, 32000])
    }

    func testBPMChangeProducesNewInterval() {
        // Simulate: 3 beats at 180, then switch to 200
        let rate: Double = 24000
        let interval180 = TickScheduler.samplesPerBeat(bpm: 180, sampleRate: rate) // 8000
        let interval200 = TickScheduler.samplesPerBeat(bpm: 200, sampleRate: rate) // 7200

        // Beat 3 ends at sample 24000. Next beat at new tempo:
        let transitionPoint = AVAudioFramePosition(3) * interval180 // 24000
        let nextBeat = transitionPoint + interval200 // 31200

        XCTAssertEqual(interval180, 8000)
        XCTAssertEqual(interval200, 7200)
        XCTAssertEqual(nextBeat, 31200)
    }

    func testSamplesPerBeatNeverZero() {
        // Even at extreme BPMs, interval should be positive
        let samples = TickScheduler.samplesPerBeat(bpm: 300, sampleRate: 24000)
        XCTAssertGreaterThan(samples, 0)
    }
}
