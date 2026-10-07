//
//  SupportTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI
import Testing
@testable import Dex

/// The small pieces the app leans on: pull persistence, pull status text,
/// the drawer's swipe decision, and hex colors.
struct SupportTests {
    // In-progress pulls persist through this encoding; a bad stored value
    // must fall back to the default rather than crash or keep junk.
    @Test func pullsDictionaryRoundTrips() {
        let pulls = ["gemma4:12b": "PULLING ABC... 25%", "qwen3.5:9b": "FAILED... OFFLINE"]
        #expect([String: String](rawValue: pulls.rawValue) == pulls)
        #expect([String: String](rawValue: [String: String]().rawValue) == [:])
    }

    @Test func corruptPullsDictionaryIsRejected() {
        #expect([String: String](rawValue: "not json") == nil)
        #expect([String: String](rawValue: #"["a", "b"]"#) == nil)
    }

    @Test(arguments: [
        (OllamaPullProgress(status: "pulling manifest", total: nil, completed: nil, error: nil), "PULLING MANIFEST..."),
        (OllamaPullProgress(status: "pulling abc", total: 200, completed: 50, error: nil), "PULLING ABC... 25%"),
        (OllamaPullProgress(status: "pulling abc", total: 0, completed: 0, error: nil), "PULLING ABC..."),
        (OllamaPullProgress(status: "pulling abc", total: 100, completed: 120, error: nil), "PULLING ABC... 100%"),
        (OllamaPullProgress(status: nil, total: nil, completed: nil, error: nil), "..."),
    ])
    func pullStatus(_ progress: OllamaPullProgress, _ expected: String) {
        #expect(ModelsVM.pullStatus(progress) == expected)
    }

    @Test func failedPullsAreMarkedForResumeToSkip() {
        #expect(ModelsVM.failedStatus("Pull ended before it finished") == "FAILED... PULL ENDED BEFORE IT FINISHED")
        #expect(ModelsVM.failedStatus("x").contains("FAILED"))
    }

    @Test(arguments: [
        (false, 0.5, true),    // dragged open past the threshold
        (false, 0.2, false),   // not far enough: springs back closed
        (false, -0.5, false),  // pushed the wrong way
        (true, -0.5, false),   // dragged closed past the threshold
        (true, -0.2, true),    // not far enough: stays open
        (true, 0.5, true),     // pushed further open
    ])
    func drawerSettles(_ wasOpen: Bool, _ travel: CGFloat, _ open: Bool) {
        #expect(RootView.settlesOpen(wasOpen: wasOpen, travel: travel, threshold: 0.35) == open)
    }

    @Test func edgeSwipeGoesBackOnlyWithABackButton() {
        #expect(RootView.edgeSwipeGoesBack(canGoBack: true, isDrawerOpen: false))
        #expect(!RootView.edgeSwipeGoesBack(canGoBack: false, isDrawerOpen: false))
        #expect(!RootView.edgeSwipeGoesBack(canGoBack: true, isDrawerOpen: true))
    }

    @Test func hexColorsParse() {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        UIColor(rgb: 0xF3E21A).getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(Int((r * 255).rounded()) == 0xF3)
        #expect(Int((g * 255).rounded()) == 0xE2)
        #expect(Int((b * 255).rounded()) == 0x1A)
        #expect(a == 1)
    }

    // The context ring warns in two steps: orange past 80%, red past 95%.
    @Test(arguments: [
        (0.0, ContextMeter.Level.normal), (0.8, .normal), (0.81, .warning),
        (0.95, .warning), (0.951, .critical), (1.0, .critical),
    ])
    func contextMeterLevel(_ share: Double, _ expected: ContextMeter.Level) {
        #expect(ContextMeter.level(share) == expected)
    }
}
