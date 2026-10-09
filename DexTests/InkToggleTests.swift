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
    /// The switch is the system's size, and its row is as tall as a row of
    /// plain text, like the Settings rows around it.
    @Test func rowIsAsTallAsText() {
        let fits = CGSize(width: 400, height: 400)
        let text = UIHostingController(rootView: Text("Web Search")).sizeThatFits(in: fits)
        let ink = UIHostingController(rootView: Toggle("Web Search", isOn: .constant(true)).toggleStyle(.ink)).sizeThatFits(in: fits)
        #expect(ink.height == text.height)
        #expect(InkToggleStyle.trackSize == UISwitch().intrinsicContentSize)
    }
}
