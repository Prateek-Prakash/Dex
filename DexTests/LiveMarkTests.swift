//
//  LiveMarkTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation
import Testing
@testable import Dex

/// The main screen mark's motion.
struct LiveMarkTests {
    @Test func atRestThereAreNoRipplesAndNoBreathing() {
        #expect(LiveMark.ripples(at: 3.7, life: 0).isEmpty)
        #expect(LiveMark.breath(at: 3.7, life: 0) == 1)
        #expect(LiveMark.breath(at: 3.7, phase: 1.4, life: 0) == 1)
    }

    @Test func ripplesAreEvenlySpacedAndFadeOut() {
        let ripples = LiveMark.ripples(at: 0, life: 1)
        #expect(ripples.count == 3)
        #expect(ripples.map(\.progress) == [0, 1.0 / 3.0, 2.0 / 3.0])
        // Born invisible, then each fades as it grows.
        #expect(ripples[0].opacity == 0)
        #expect(ripples[1].opacity > ripples[2].opacity)
        // One period later they are back where they started.
        let later = LiveMark.ripples(at: LiveMark.ripplePeriod, life: 1)
        for (a, b) in zip(ripples, later) {
            #expect(abs(a.progress - b.progress) < 1e-9)
        }
        // Halfway through the fade, half as strong.
        #expect(abs(LiveMark.ripples(at: 0.5, life: 0.5)[1].opacity * 2 - LiveMark.ripples(at: 0.5, life: 1)[1].opacity) < 1e-9)
    }

    @Test func haloIsBrightestWhenTheDotsAre() {
        let period = LiveMark.breathPeriod
        let samples = stride(from: 0.0, to: period, by: period / 48).map { $0 }
        let dotsBrightest = try! #require(samples.max { LiveMark.breath(at: $0, life: 1) < LiveMark.breath(at: $1, life: 1) })
        let haloBrightest = try! #require(samples.max { LiveMark.halo(at: $0) < LiveMark.halo(at: $1) })
        #expect(abs(dotsBrightest - haloBrightest) < 1e-9)
        #expect(samples.allSatisfy { LiveMark.halo(at: $0) >= 0.4 - 1e-9 })
        #expect(samples.allSatisfy { LiveMark.breath(at: $0, life: 1) >= 0.65 - 1e-9 })
    }
}
