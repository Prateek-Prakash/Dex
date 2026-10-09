//
//  StorageTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation
import SwiftData
import Testing
@testable import Dex

/// Chat titles: the fallback and the cleanup of the model's answer.
struct ChatTitleTests {
    @Test func fallbackIsFirstLineCutAtAWord() {
        #expect(ChatTitle.fallback("Hello there") == "Hello there")
        #expect(ChatTitle.fallback("\n  What is a tensor?  \nMore") == "What is a tensor?")
        #expect(ChatTitle.fallback("How do I set up a Cloudflare tunnel for my Ollama server")
                == "How do I set up a Cloudflare tunnel for…")
        #expect(ChatTitle.fallback(String(repeating: "a", count: 50)) == String(repeating: "a", count: 40) + "…")
    }

    @Test func cleanKeepsFourWordsInTitleCase() {
        #expect(ChatTitle.clean("setting up a cloudflare tunnel today") == "Setting up a Cloudflare")
        #expect(ChatTitle.clean("\"The Art of War\"") == "The Art of War")
        #expect(ChatTitle.clean("**Title:** SwiftUI and iOS layout.") == "SwiftUI and iOS Layout")
        #expect(ChatTitle.clean("Title: C++ vs C# Basics!") == "C++ vs C# Basics")
        #expect(ChatTitle.clean("<think>hmm</think>\n\nGPU Memory Limits\nExtra line") == "GPU Memory Limits")
        #expect(ChatTitle.clean("  \n \"\" ") == nil)
        #expect(ChatTitle.clean("# Docker Networking") == "Docker Networking")
    }
}

extension StubbedNetworkTests {
    /// Saving chats: what is stored, when, and what isn't.
    @Suite(.serialized)
    @MainActor
    struct ChatStorageTests {
        private static func vm() -> (ChatVM, FakeServer, ModelContext) {
            let context = ModelContext(Storage.inMemory())
            let server = FakeServer()
            let vm = ChatVM()
            vm.context = context
            vm.server = server
            vm.followInterval = .milliseconds(10)
            return (vm, server, context)
        }

        private static func chats(_ context: ModelContext) throws -> [Chat] {
            try context.fetch(FetchDescriptor<Chat>())
        }

        /// Sends `text` and has the server answer `reply`.
        private static func exchange(_ text: String, _ reply: String, _ vm: ChatVM, _ server: FakeServer) async throws {
            vm.send(text, model: "gemma4:12b")
            await vm.waitForReply()
            let id = try #require(vm.messages.last?.id)
            server.send(.finished(chatID: vm.chat?.id ?? "", messageID: id, output: [.message(id: "m", text: reply)], usage: nil))
        }

        @Test func renameTrimsAndIgnoresBlank() async throws {
            let (vm, server, _) = Self.vm()
            try await Self.exchange("Hi there", "Hello", vm, server)
            let chat = try #require(vm.chat)
            vm.rename(chat, to: "  Trip Plans \n")
            #expect(chat.title == "Trip Plans")
            vm.rename(chat, to: "   ")
            #expect(chat.title == "Trip Plans")
        }

        @Test func renameLeavesRecentOrderAlone() async throws {
            let (vm, server, _) = Self.vm()
            try await Self.exchange("Hi", "Hello", vm, server)
            let chat = try #require(vm.chat)
            let updatedAt = chat.updatedAt
            vm.rename(chat, to: "Renamed")
            vm.togglePin(chat)
            #expect(chat.updatedAt == updatedAt)
        }

        @Test func messagesChainParentsAndChildren() async throws {
            let (vm, server, _) = Self.vm()
            try await Self.exchange("First", "One", vm, server)
            try await Self.exchange("Second", "Two", vm, server)
            let stored = try #require(vm.chat).sortedMessages
            #expect(stored.map(\.parentId) == [nil, stored[0].id, stored[1].id, stored[2].id])
            #expect(stored.map(\.childrenIds) == [[stored[1].id], [stored[2].id], [stored[3].id], []])
            // Ids take the server's form: lowercase UUIDs.
            #expect(stored.allSatisfy { $0.id == $0.id.lowercased() && UUID(uuidString: $0.id) != nil })
        }

        @Test func ownMessagesLeaveAChatRead() async throws {
            let (vm, server, _) = Self.vm()
            try await Self.exchange("Hi", "Hello", vm, server)
            let chat = try #require(vm.chat)
            #expect(!chat.isUnread)
            // Something arriving later, as a reply finished while away would.
            chat.updatedAt = .now.addingTimeInterval(60)
            #expect(chat.isUnread)
        }

        @Test func sequenceFollowsMessagesStoredWhileOpen() async throws {
            let (vm, server, context) = Self.vm()
            try await Self.exchange("First", "One", vm, server)
            let chat = try #require(vm.chat)
            for sequence in [2, 3] {
                let stored = Message(id: Storage.newID())
                context.insert(stored)
                stored.chat = chat
                stored.sequence = sequence
            }
            try await Self.exchange("Second", "Two", vm, server)
            #expect(chat.sortedMessages.map(\.sequence) == [0, 1, 2, 3, 4, 5])
            #expect(Array(chat.sortedMessages.suffix(2).map(\.content)) == ["Second", "Two"])
        }

        @Test func refreshShowsWhatLandedInTheStore() async throws {
            let (vm, server, context) = Self.vm()
            try await Self.exchange("First", "One", vm, server)
            let chat = try #require(vm.chat)
            let stored = Message(id: Storage.newID())
            context.insert(stored)
            stored.chat = chat
            stored.sequence = 2
            stored.content = "Landed"
            try context.save()
            vm.refresh()
            #expect(vm.messages.map(\.content) == ["First", "One", "Landed"])
        }

        @Test func refreshAfterDeleteClearsTheScreen() async throws {
            let (vm, server, context) = Self.vm()
            try await Self.exchange("Hi", "Hello", vm, server)
            context.delete(try #require(vm.chat))
            try context.save()
            vm.refresh()
            #expect(vm.chat == nil)
            #expect(vm.messages.isEmpty)
        }

        @Test func mergeKeepsTheReplyStreamingHere() {
            let user = ChatMessage(role: .user, content: "Hi", sequence: 0)
            let local = ChatMessage(role: .assistant, content: "Half an ans", sequence: 1, status: .streaming)
            var storedReply = local
            storedReply.content = ""
            storedReply.status = .stopped
            let landed = ChatMessage(role: .user, content: "Landed", sequence: 2)
            #expect(ChatVM.merge(local: [user, local], stored: [user, storedReply, landed], replyID: local.id) == [user, local, landed])
            // Gone from the store: kept, saved again when it ends.
            #expect(ChatVM.merge(local: [user, local], stored: [user], replyID: local.id) == [user, local])
            // Nothing streaming here: the store wins.
            #expect(ChatVM.merge(local: [user, storedReply], stored: [user], replyID: nil) == [user])
        }

        @Test func deletingAChatReplyingOffScreenLetsItGo() async throws {
            let (vm, server, context) = Self.vm()
            vm.send("Hi", model: "gemma4:12b")
            await vm.waitForReply()
            let chat = try #require(vm.chat)
            let id = try #require(vm.messages.last?.id)
            vm.reset()
            vm.delete(chat)
            #expect(vm.streamingChatIDs.isEmpty)
            server.send(.finished(chatID: "c1", messageID: id, output: [.message(id: "m", text: "Late")], usage: nil))
            #expect(try Self.chats(context).isEmpty)
            #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
        }

        @Test func deletingOpenChatClearsScreenAndMessages() async throws {
            let (vm, server, context) = Self.vm()
            try await Self.exchange("Hi", "Hello", vm, server)
            vm.delete(try #require(vm.chat))
            #expect(vm.messages.isEmpty)
            #expect(vm.chat == nil)
            #expect(try Self.chats(context).isEmpty)
            #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
        }

        @Test func inChatFindsOnlyThatChatsMessages() throws {
            let context = ModelContext(Storage.inMemory())
            let mine = Chat(title: "Mine")
            let other = Chat(title: "Other")
            context.insert(mine)
            context.insert(other)
            for (chat, content) in [(mine, "A"), (mine, "B"), (other, "C")] {
                let message = Message(id: Storage.newID())
                context.insert(message)
                message.chat = chat
                message.content = content
            }
            try context.save()
            let found = try context.fetch(FetchDescriptor<Message>(predicate: Message.inChat(mine.id)))
            #expect(Set(found.map(\.content)) == ["A", "B"])
        }
    }
}

/// Folders: the names a new or renamed one may have, the Folders page's
/// order. Making and renaming them on the server is in `ListSyncTests`.
@MainActor
struct FolderTests {
    @Test func newNamesAreTrimmedAndUnique() throws {
        let context = ModelContext(Storage.inMemory())
        #expect(Folder.check("  Home Lab \n", in: context) == nil)
        guard case .blank = Folder.check("   ", in: context) else {
            Issue.record("not blank"); return
        }
        context.insert(Folder(name: "Home Lab"))
        guard case .taken(let name) = Folder.check(" home LAB ", in: context) else {
            Issue.record("not refused"); return
        }
        #expect(name == "home LAB")
        #expect(Folder.check("Home Lab 2", in: context) == nil)
    }

    @Test func renamesFollowTheUniqueRule() throws {
        let context = ModelContext(Storage.inMemory())
        let lab = Folder(name: "Home Lab")
        context.insert(lab)
        context.insert(Folder(name: "Recipes"))
        guard case .taken(let name) = Folder.check(renaming: lab, to: " recipes ", in: context) else {
            Issue.record("not refused"); return
        }
        #expect(name == "recipes")
        guard case .unchanged = Folder.check(renaming: lab, to: "   ", in: context),
              case .unchanged = Folder.check(renaming: lab, to: "Home Lab", in: context) else {
            Issue.record("changed"); return
        }
        // Only the case changing is fine: the folder it matches is itself.
        #expect(Folder.check(renaming: lab, to: "home lab", in: context) == nil)
        #expect(Folder.check(renaming: lab, to: "  Servers ", in: context) == nil)
    }

    @Test func foldersListNewestFirst() throws {
        let context = ModelContext(Storage.inMemory())
        context.insert(Folder(name: "Old"))
        let newer = Folder(name: "New")
        newer.createdAt = Date().addingTimeInterval(60)
        context.insert(newer)
        let folders = try context.fetch(FetchDescriptor<Folder>(sortBy: Folder.newestFirst))
        #expect(folders.map(\.name) == ["New", "Old"])
    }

    @Test func chatCountLine() {
        #expect(Folder.chatCount(0) == "No Chats")
        #expect(Folder.chatCount(1) == "1 Chat")
        #expect(Folder.chatCount(7) == "7 Chats")
    }

    @Test func deletingAFolderDeletesItsChatsAndClearsTheScreen() throws {
        let context = ModelContext(Storage.inMemory())
        let folder = Folder(name: "Lab")
        context.insert(folder)
        let inside = Chat(title: "Inside")
        let outside = Chat(title: "Outside")
        context.insert(inside)
        context.insert(outside)
        inside.folder = folder
        try context.save()

        let vm = ChatVM()
        vm.context = context
        vm.open(inside)
        vm.delete(folder)
        #expect(vm.chat == nil)
        #expect(try context.fetch(FetchDescriptor<Folder>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Chat>()).map(\.title) == ["Outside"])
    }
}

/// Pinning a chat; the drawer's sections are in `CacheApplyTests`.
@MainActor
struct PinTests {
    @Test func togglePinFlipsIt() throws {
        let context = ModelContext(Storage.inMemory())
        let chat = Chat(title: "Notes")
        context.insert(chat)
        let vm = ChatVM()
        vm.context = context
        vm.togglePin(chat)
        #expect(chat.isPinned)
        #expect(!context.hasChanges)
        vm.togglePin(chat)
        #expect(!chat.isPinned)
    }
}

extension StubbedNetworkTests {
    /// Organize: moving chats into and out of folders, and a folder's New Session.
    @Suite(.serialized)
    @MainActor
    struct OrganizeTests {
        private static func vm() -> (ChatVM, ModelContext) {
            let context = ModelContext(Storage.inMemory())
            let vm = ChatVM()
            vm.context = context
            vm.server = FakeServer()
            return (vm, context)
        }

        /// Sends `text` and waits for the server to take it, saving the chat.
        private static func send(_ text: String, _ vm: ChatVM) async {
            vm.send(text, model: "gemma4:12b")
            await vm.waitForReply()
            // Ready for the next message: the reply isn't awaited.
            vm.stop()
        }

        @Test func moveIntoAcrossAndOutKeepsRecentOrder() throws {
            let (vm, context) = Self.vm()
            let lab = Folder(name: "Lab")
            let recipes = Folder(name: "Recipes")
            let chat = Chat(title: "Notes")
            [lab, recipes].forEach(context.insert)
            context.insert(chat)
            let updatedAt = chat.updatedAt

            vm.move(chat, to: lab)
            #expect(chat.folder === lab)
            #expect(DrawerItem(chat).kind == .folderChat)
            vm.move(chat, to: recipes)
            #expect(chat.folder === recipes)
            #expect(lab.chats.isEmpty)
            vm.move(chat, to: nil)
            #expect(chat.folder == nil)
            #expect(DrawerItem(chat).kind == .chat)
            #expect(chat.updatedAt == updatedAt)
            #expect(!context.hasChanges)
        }

        @Test func folderNewSessionJoinsTheFolderWithItsFirstMessage() async throws {
            let (vm, context) = Self.vm()
            let lab = Folder(name: "Lab")
            context.insert(lab)

            // Abandoned before a message: nothing lands in the folder.
            vm.reset(into: lab)
            vm.reset()
            await Self.send("Loose", vm)
            #expect(vm.chat?.folder == nil)

            vm.reset(into: lab)
            await Self.send("Inside", vm)
            #expect(vm.chat?.folder === lab)
            // Only the first chat after it: the next new one is on its own.
            vm.reset()
            await Self.send("After", vm)
            #expect(vm.chat?.folder == nil)

            // Opening a saved chat drops a pending folder.
            let saved = Chat(title: "Saved")
            context.insert(saved)
            vm.reset(into: lab)
            vm.open(saved)
            vm.reset()
            await Self.send("Fresh", vm)
            #expect(vm.chat?.folder == nil)
            #expect(try context.fetch(FetchDescriptor<Chat>(predicate: Chat.inFolder(lab.id))).map(\.title) == ["Inside"])
        }

        @Test func folderDeletedBeforeTheFirstMessageIsLeftOut() async throws {
            let (vm, context) = Self.vm()
            let lab = Folder(name: "Lab")
            context.insert(lab)
            try context.save()
            vm.reset(into: lab)
            context.delete(lab)
            try context.save()
            await Self.send("Hi", vm)
            #expect(vm.chat?.folder == nil)
        }
    }
}

/// The cache itself: one row per server id, and the old store's files gone.
@MainActor
struct CacheTests {
    @Test func sameIDIsOneRow() throws {
        let context = ModelContext(Storage.inMemory())
        context.insert(Chat(id: "c1", title: "First"))
        try context.save()
        context.insert(Chat(id: "c1", title: "Again"))
        try context.save()
        let chats = try context.fetch(FetchDescriptor<Chat>())
        #expect(chats.map(\.title) == ["Again"])
    }

    @Test func oldStoreFilesAreRemoved() throws {
        let directory = URL.temporaryDirectory.appending(path: "DexOldStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["default.store", "default.store-shm", "default.store-wal", "Dex Cache.store"] {
            try Data("x".utf8).write(to: directory.appending(path: name))
        }
        for folder in ["default_ckAssets", ".default_SUPPORT/_EXTERNAL_DATA"] {
            try FileManager.default.createDirectory(at: directory.appending(path: folder), withIntermediateDirectories: true)
        }
        Storage.removeOldStore(in: directory)
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path())
        #expect(left == ["Dex Cache.store"])
    }
}
