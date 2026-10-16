//
//  AppVersionTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/15/26.
//

import Foundation
import Testing
@testable import Dex

struct AppVersionTests {
    @Test func joinsVersionAndBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "7"]
        #expect(AppVersion.label(from: info) == "1.0.0+7")
    }

    @Test func fallsBackWhenKeysMissing() {
        #expect(AppVersion.label(from: nil) == "0.0.0+0")
    }

    /// The shipped label comes from the build settings, so it must match the
    /// release tag shape 1.0.0+N.
    @Test func bundleLabelMatchesTagFormat() {
        let label = AppVersion.label
        #expect(label.wholeMatch(of: /\d+\.\d+\.\d+\+\d+/) != nil, "\(label)")
        #expect(label == AppVersion.label(from: Bundle.main.infoDictionary))
    }
}
