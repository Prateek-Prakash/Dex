//
//  StackResetTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/9/26.
//

import Testing
@testable import Dex

/// Anything on the navigation stack deleted elsewhere clears it all to a
/// new chat; these say when that is.
struct StackResetTests {
    private func check(page: RootView.Page = .chat, routes: [Route] = [], heldChatGone: Bool = false,
                       folders: Set<String> = ["work"], chats: Set<String> = ["plan"]) -> Bool {
        RootView.hasDeletedPage(page: page, routes: routes, heldChatGone: heldChatGone,
                                folderExists: folders.contains, chatExists: chats.contains)
    }

    @Test func everythingStillThereChangesNothing() {
        #expect(!check(page: .folders, routes: [.folder("work"), .chat("plan")]))
        #expect(!check(page: .folder("work"), routes: [.newChat("work")]))
        #expect(!check())
    }

    @Test func aDeletedChatOrFolderAnywhereOnTheStackResets() {
        // Folders → Work → Q3 Plan, and the chat is deleted.
        #expect(check(page: .folders, routes: [.folder("work"), .chat("plan")], chats: []))
        // The folder is deleted (its chats with it).
        #expect(check(page: .folders, routes: [.folder("work"), .chat("plan")], folders: [], chats: []))
        // A folder's New Session, and the folder is deleted.
        #expect(check(page: .folder("work"), routes: [.newChat("work")], folders: []))
        // The drawer's folder page itself.
        #expect(check(page: .folder("work"), folders: []))
    }

    @Test func theChatUnderAPushedFolderResetsToo() {
        // Chat → its folder chip → the chat underneath is deleted.
        #expect(check(routes: [.folder("work")], heldChatGone: true))
    }
}
