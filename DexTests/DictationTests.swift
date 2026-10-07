//
//  DictationTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI
import Testing
@testable import Dex

/// Dictation's arithmetic: loudness, joining heard words to typed text, and
/// the waveform's bars. Recognition itself needs a microphone.
struct DictationTests {
    @Test(arguments: [
        (Float(0), CGFloat(0)), (0.0001, 0), (0.00316, 0), (0.01, 0.333), (0.01778, 0.5), (0.1, 1), (1, 1),
    ])
    func loudness(_ rms: Float, _ expected: CGFloat) {
        #expect(abs(Dictation.level(rms: rms) - expected) < 0.01)
    }

    @Test(arguments: [
        ("", "Hello", "Hello"),
        ("Draft", "more words", "Draft more words"),
        ("Draft ", "more", "Draft more"),
        ("Draft", "", "Draft"),
        ("Line\n", "next", "Line\nnext"),
    ])
    func joinsHeardWordsToTypedText(_ typed: String, _ heard: String, _ expected: String) {
        #expect(Dictation.joined(typed, heard) == expected)
    }

    // Claude's measurements: 3pt bars on a 6pt pitch, 3pt dots up to 36pt.
    @Test func barsEnterFromTheRightNewestFirst() {
        #expect(WaveformView.bars(levels: [], width: 30, progress: 0).isEmpty)
        let bars = WaveformView.bars(levels: [0.0, 0.25, 1.0], width: 30, progress: 0)
        #expect(bars == [.init(x: 27, height: 36), .init(x: 21, height: 9), .init(x: 15, height: 3)])
        // A full line keeps only what fits.
        #expect(WaveformView.bars(levels: Array(repeating: 0.5, count: 50), width: 30, progress: 0).count == 5)
    }

    @Test func barsSlideLeftBetweenSamples() {
        let still = WaveformView.bars(levels: [1], width: 30, progress: 0)
        let moved = WaveformView.bars(levels: [1], width: 30, progress: 0.5)
        #expect(moved[0].x == still[0].x - 3)
        #expect(WaveformView.bars(levels: [1], width: 0, progress: 0).isEmpty)
    }

    // A pause can restart the recognizer's transcription mid-task; the
    // earlier sentence must stay rather than be replaced.
    @Test(arguments: [
        ("Test, test, test.", "Another sentence", true),
        ("Hello there", "Okay", true),
        ("Hello there", "Hello there friend", false),
        ("Hello the", "Hello there", false),
        ("I", "Hi everyone", false),
        ("Test", "Okay", true),
        ("", "Anything", false),
        ("Same start", "same start, revised", false),
        ("Write the code", "Right, the code is done", false),
        ("Test, test, test.", "Test", true),
        ("Going to the store now", "Going to the store", false),
    ])
    func restartAfterPause(_ previous: String, _ next: String, _ restart: Bool) {
        #expect(Dictation.isRestart(previous: previous, next: next) == restart)
    }

    @Test(arguments: [
        ("Test test test", "Test test test."),
        ("How are you doing", "How are you doing?"),
        ("can you help me", "can you help me?"),
        ("Don't stop now", "Don't stop now."),
        ("Do it now", "Do it now."),
        ("Does it work", "Does it work?"),
        ("Do you have time", "Do you have time?"),
        ("Don't you think so", "Don't you think so?"),
        ("Is the server up", "Is the server up?"),
        ("Sounds good,", "Sounds good."),
        ("Already done.", "Already done."),
        ("Really!", "Really!"),
        ("Is it?", "Is it?"),
        ("", ""),
    ])
    func closesASentenceAfterAPause(_ sentence: String, _ expected: String) {
        #expect(Dictation.closed(sentence) == expected)
    }

    @Test func nextSentenceStartsWithACapital() {
        #expect(Dictation.continuing("and then", after: "First one.") == "And then")
        #expect(Dictation.continuing("and then", after: "First one,") == "and then")
        #expect(Dictation.continuing("and then", after: "") == "and then")
        #expect(Dictation.continuing("Already", after: "Done?") == "Already")
    }
}

