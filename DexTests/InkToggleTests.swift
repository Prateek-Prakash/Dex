//
//  InkToggleTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/9/26.
//

import SwiftUI
import Testing
import UIKit
@testable import Dex

@MainActor
struct InkToggleTests {
    /// A row with the ink switch is as tall as one with the system's.
    @Test func matchesTheSystemSwitch() {
        let fits = CGSize(width: 400, height: 400)
        let system = UIHostingController(rootView: Toggle("Web Search", isOn: .constant(true))).sizeThatFits(in: fits)
        let ink = UIHostingController(rootView: Toggle("Web Search", isOn: .constant(true)).toggleStyle(.ink)).sizeThatFits(in: fits)
        #expect(ink.height == system.height)
        #expect(InkToggleStyle.trackSize == UISwitch().intrinsicContentSize)
    }
}
