//
//  DrawerItemTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/6/26.
//

import Testing
@testable import Dex

struct DrawerItemTests {
    private let folder = DrawerItem(title: "Home Lab", kind: .folder)
    private let chat = DrawerItem(title: "Gemma Notes", kind: .chat)

    @Test func iconFollowsKind() {
        #expect(DrawerItem(title: "A", kind: .folder).icon == .folder)
        #expect(DrawerItem(title: "B", kind: .folderChat).icon == .folder)
        #expect(DrawerItem(title: "C", kind: .chat).icon == .chat)
    }

    @Test func sectionsWithNoItemsAreLeftOut() {
        #expect(DrawerItem.sections(pinned: [], recent: []).isEmpty)
        #expect(DrawerItem.sections(pinned: [folder], recent: []).map(\.title) == ["Pinned"])
        #expect(DrawerItem.sections(pinned: [], recent: [chat]).map(\.title) == ["Recent"])
        #expect(DrawerItem.sections(pinned: [folder], recent: [chat]).map(\.title) == ["Pinned", "Recent"])
    }
}
