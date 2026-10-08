//
//  DrawerItemTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/6/26.
//

import Foundation
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

/// The main screen's stack: pushing, and going back instead of pushing a
/// page that's already there.
struct RouteTests {
    private let lab = UUID()
    private let recipes = UUID()
    private let notes = UUID()
    private let trip = UUID()

    @Test func newPagesPush() {
        #expect(Route.pushing(.folder(lab), onto: [], root: .folders, rootChatID: nil) == [.folder(lab)])
        #expect(Route.pushing(.chat(notes), onto: [.folder(lab)], root: .folders, rootChatID: nil)
                == [.folder(lab), .chat(notes)])
    }

    @Test func aPageAlreadyThereIsGoneBackTo() {
        // Folders → Lab → Notes; Notes' chip asks for Lab: back to it.
        #expect(Route.pushing(.folder(lab), onto: [.folder(lab), .chat(notes)], root: .folders, rootChatID: nil)
                == [.folder(lab)])
        // Lab from the drawer → Notes; the chip asks for the root page.
        #expect(Route.pushing(.folder(lab), onto: [.chat(notes)], root: .folder(lab), rootChatID: nil) == [])
        // Trip → its folder Lab → Trip again: back to the chat page.
        #expect(Route.pushing(.chat(trip), onto: [.folder(lab)], root: .chat, rootChatID: trip) == [])
    }

    @Test func folderNewSessionPushesAndItsChipGoesBack() {
        // Lab from the drawer → New Session → the chip asks for Lab.
        let pushed = Route.pushing(.newChat(lab), onto: [], root: .folder(lab), rootChatID: nil)
        #expect(pushed == [.newChat(lab)])
        #expect(Route.pushing(.folder(lab), onto: pushed, root: .folder(lab), rootChatID: nil) == [])
        // Folders → Lab → New Session → chip: back to Lab.
        #expect(Route.pushing(.folder(lab), onto: [.folder(lab), .newChat(lab)], root: .folders, rootChatID: nil)
                == [.folder(lab)])
        #expect(Route.newChat(lab).isChat && Route.chat(notes).isChat && !Route.folder(lab).isChat)
    }

    @Test func anotherFolderStillPushes() {
        #expect(Route.pushing(.folder(recipes), onto: [.folder(lab), .chat(notes)], root: .folders, rootChatID: nil)
                == [.folder(lab), .chat(notes), .folder(recipes)])
        #expect(Route.pushing(.folder(recipes), onto: [], root: .folder(lab), rootChatID: nil) == [.folder(recipes)])
    }
}
