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
        private static let model = OllamaModel(
            name: "gemma4:12b", size: 0, digest: "",
            details: .init(format: nil, family: nil, parameterSize: nil, quantizationLevel: nil),
            capabilities: ["completion", "thinking"])

        private static let reply = """
            {"message":{"content":"","thinking":"Hmm."}}
            {"message":{"content":"Hello there"}}
            {"message":{"content":""},"done":true,"done_reason":"stop","prompt_eval_count":10,"eval_count":5}

            """

        /// Chat replies stream `reply`; the naming request gets `title`.
        private static func client(title: String = "greeting the user", status: Int = 200) -> OllamaClient {
            OllamaStubProtocol.client { request in
                let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                if body.contains("Name this conversation") {
                    return .init(status: status, contentType: "application/x-ndjson",
                                 body: #"{"message":{"content":"\#(title)"},"done":true}"# + "\n")
                }
                return .init(contentType: "application/x-ndjson", body: reply)
            }
        }

        private static func vm() -> (ChatVM, ModelContext) {
            let context = ModelContext(Storage.inMemory())
            let vm = ChatVM()
            vm.context = context
            return (vm, context)
        }

        private static func chats(_ context: ModelContext) throws -> [Chat] {
            try context.fetch(FetchDescriptor<Chat>())
        }

        @Test func sentChatIsSavedAndNamed() async throws {
            let (vm, context) = Self.vm()
            vm.send("Hi there", client: Self.client(), model: Self.model)
            #expect(try Self.chats(context).first?.title == "Hi there")
            await vm.waitForReply()
            await vm.waitForTitle()

            let chat = try #require(try Self.chats(context).first)
            #expect(try Self.chats(context).count == 1)
            #expect(chat.title == "Greeting the User")
            #expect(chat.model == "gemma4:12b")
            let stored = chat.sortedMessages
            #expect(stored.map(\.role) == ["user", "assistant"])
            #expect(stored.map(\.content) == ["Hi there", "Hello there"])
            #expect(stored[1].status == "done")
            #expect(stored[1].thinking == "Hmm.")
            #expect(stored[1].promptTokens == 10)
            #expect(stored[1].outputTokens == 5)
            #expect(stored.map(\.id) == vm.messages.map(\.id))

            // Naming is a separate request, never a message, and doesn't think.
            let naming = try #require(OllamaStubProtocol.requests.last?.httpBody)
            let body = try #require(try JSONSerialization.jsonObject(with: naming) as? [String: Any])
            #expect(body["think"] as? Bool == false)
            #expect((body["options"] as? [String: Any])?["num_ctx"] as? Int == 65_536)
            #expect(vm.messages.count == 2)
        }

        @Test func renameTrimsAndIgnoresBlank() async throws {
            let (vm, _) = Self.vm()
            vm.send("Hi there", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            await vm.waitForTitle()
            let chat = try #require(vm.chat)
            let updated = chat.updatedAt
            vm.rename(chat, to: "  Trip Plans \n")
            #expect(chat.title == "Trip Plans")
            #expect(chat.updatedAt >= updated)
            vm.rename(chat, to: "   ")
            #expect(chat.title == "Trip Plans")
        }

        @Test func renameBeforeNamingFinishesWins() async throws {
            let (vm, _) = Self.vm()
            vm.send("Hi there", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            vm.rename(try #require(vm.chat), to: "Mine")
            await vm.waitForTitle()
            #expect(vm.chat?.title == "Mine")
        }

        @Test func failedNamingKeepsFallback() async throws {
            let (vm, context) = Self.vm()
            vm.send("Hi there", client: Self.client(status: 500), model: Self.model)
            await vm.waitForReply()
            await vm.waitForTitle()
            #expect(try Self.chats(context).first?.title == "Hi there")
        }

        @Test func renameDuringNamingWins() async throws {
            let (vm, context) = Self.vm()
            vm.send("Hi there", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            try Self.chats(context).first?.title = "Mine"
            await vm.waitForTitle()
            #expect(try Self.chats(context).first?.title == "Mine")
        }

        @Test func incognitoIsNeverSaved() async throws {
            let (vm, context) = Self.vm()
            vm.isIncognito = true
            vm.send("Secret", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            await vm.waitForTitle()
            #expect(try Self.chats(context).isEmpty)
            #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
            #expect(vm.chat == nil)
        }

        @Test func reopenedChatContinues() async throws {
            let (vm, context) = Self.vm()
            vm.send("First", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            await vm.waitForTitle()
            let chat = try #require(vm.chat)

            vm.reset()
            #expect(vm.messages.isEmpty)
            #expect(vm.chat == nil)
            vm.open(chat)
            #expect(vm.messages.map(\.content) == ["First", "Hello there"])
            #expect(vm.contextUsed == 15)

            vm.send("Second", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            #expect(try Self.chats(context).count == 1)
            #expect(chat.sortedMessages.map(\.sequence) == [0, 1, 2, 3])
            // Only the first reply names a chat.
            #expect(chat.title == "Greeting the User")
        }

        @Test func retryReplacesStoredReply() async throws {
            let (vm, context) = Self.vm()
            vm.send("Hi", client: OllamaStubProtocol.client { _ in
                .init(contentType: "application/x-ndjson", body: #"{"message":{"content":"Half"}}"# + "\n")
            }, model: Self.model)
            await vm.waitForReply()
            #expect(try context.fetch(FetchDescriptor<Message>()).map(\.status).sorted() == ["done", "failed"])

            vm.retry(client: Self.client(), model: Self.model)
            await vm.waitForReply()
            let stored = try #require(vm.chat).sortedMessages
            #expect(stored.map(\.status) == ["done", "done"])
            #expect(stored.last?.content == "Hello there")
            #expect(try context.fetch(FetchDescriptor<Message>()).count == 2)
        }

        @Test func leavingMidReplyLetsItFinish() async throws {
            let (vm, context) = Self.vm()
            // Left before the reply's task gets to run.
            vm.send("Hi", client: Self.client(), model: Self.model)
            let chat = try #require(vm.chat)
            vm.reset()
            #expect(vm.messages.isEmpty)
            #expect(vm.streamingChatIDs == [chat.id])
            await vm.waitForReply()
            #expect(chat.sortedMessages.map(\.status) == ["done", "done"])
            #expect(chat.sortedMessages.last?.content == "Hello there")
            #expect(vm.streamingChatIDs.isEmpty)
            #expect(try context.fetch(FetchDescriptor<Message>()).count == 2)

            vm.open(chat)
            #expect(vm.messages.map(\.content) == ["Hi", "Hello there"])
        }

        @Test func twoChatsReplyAtTheirOwnTime() async throws {
            let (vm, _) = Self.vm()
            vm.send("First", client: Self.client(), model: Self.model)
            let first = try #require(vm.chat)
            vm.reset()
            vm.send("Second", client: Self.client(), model: Self.model)
            let second = try #require(vm.chat)
            #expect(vm.streamingChatIDs == [first.id, second.id])
            await vm.waitForReply()
            #expect(vm.streamingChatIDs.isEmpty)
            for chat in [first, second] {
                #expect(chat.sortedMessages.map(\.status) == ["done", "done"])
            }
            // The one on screen shows its finished reply.
            #expect(vm.messages.map(\.content) == ["Second", "Hello there"])
        }

        @Test func reopenedMidReplyPicksUpLive() async throws {
            let (vm, _) = Self.vm()
            vm.send("Hi", client: Self.client(), model: Self.model)
            let chat = try #require(vm.chat)
            vm.reset()
            vm.open(chat)
            #expect(vm.isStreaming)
            await vm.waitForReply()
            #expect(!vm.isStreaming)
            #expect(vm.messages.last?.status == .done)
            #expect(vm.messages.last?.content == "Hello there")
        }

        @Test func leavingIncognitoMidReplyStopsIt() async throws {
            let (vm, context) = Self.vm()
            vm.isIncognito = true
            vm.send("Secret", client: Self.client(), model: Self.model)
            vm.reset()
            #expect(vm.streamingChatIDs.isEmpty)
            await vm.waitForReply()
            #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
            #expect(vm.messages.isEmpty)
        }

        @Test func deletingAChatReplyingOffScreenStopsIt() async throws {
            let (vm, context) = Self.vm()
            vm.send("Hi", client: Self.client(), model: Self.model)
            let chat = try #require(vm.chat)
            vm.reset()
            vm.delete(chat)
            #expect(vm.streamingChatIDs.isEmpty)
            await vm.waitForReply()
            #expect(try Self.chats(context).isEmpty)
            #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
        }

        @Test func sequenceFollowsMessagesSyncedInWhileOpen() async throws {
            let (vm, context) = Self.vm()
            vm.send("First", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            let chat = try #require(vm.chat)
            // Another device's exchange arrives through sync.
            for sequence in [2, 3] {
                let synced = Message(id: UUID())
                context.insert(synced)
                synced.chat = chat
                synced.sequence = sequence
            }
            vm.send("Second", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            #expect(chat.sortedMessages.map(\.sequence) == [0, 1, 2, 3, 4, 5])
            #expect(Array(chat.sortedMessages.suffix(2).map(\.content)) == ["Second", "Hello there"])
        }

        @Test func refreshShowsWhatAnotherDeviceSynced() async throws {
            let (vm, context) = Self.vm()
            vm.send("First", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            let chat = try #require(vm.chat)
            let messageCount = vm.messages.count
            // Another device's message arrives, and it rewrites the reply.
            let synced = Message(id: UUID())
            context.insert(synced)
            synced.chat = chat
            synced.sequence = 2
            synced.content = "From the iPad"
            try context.save()
            let reply = try #require(chat.sortedMessages.first { $0.role == "assistant" })
            reply.content = "Edited elsewhere"

            vm.refresh()
            #expect(vm.messages.count == messageCount + 1)
            #expect(vm.messages.map(\.sequence) == [0, 1, 2])
            #expect(vm.messages.last?.content == "From the iPad")
            #expect(vm.messages[1].content == "Edited elsewhere")
            // What arrived continues the chat: the next message follows it.
            vm.send("Next", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            #expect(chat.sortedMessages.map(\.sequence) == [0, 1, 2, 3, 4])
        }

        @Test func refreshAfterDeleteElsewhereClearsTheScreen() async throws {
            let (vm, context) = Self.vm()
            vm.send("Hi", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            await vm.waitForTitle()
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
            let synced = ChatMessage(role: .user, content: "From the iPad", sequence: 2)

            let merged = ChatVM.merge(local: [user, local], stored: [user, storedReply, synced])
            #expect(merged == [user, local, synced])
            // Retried away on another device: kept, saved again when it ends.
            #expect(ChatVM.merge(local: [user, local], stored: [user]) == [user, local])
            // Nothing streaming: the store wins, messages gone there go here.
            #expect(ChatVM.merge(local: [user, storedReply], stored: [user]) == [user])
        }

        @Test func inChatFindsOnlyThatChatsMessages() throws {
            let context = ModelContext(Storage.inMemory())
            let mine = Chat(title: "Mine")
            let other = Chat(title: "Other")
            context.insert(mine)
            context.insert(other)
            for (chat, content) in [(mine, "A"), (mine, "B"), (other, "C")] {
                let message = Message(id: UUID())
                context.insert(message)
                message.chat = chat
                message.content = content
            }
            try context.save()
            let found = try context.fetch(FetchDescriptor<Message>(predicate: Message.inChat(mine.id)))
            #expect(Set(found.map(\.content)) == ["A", "B"])
        }

        @Test func quitMidReplyReopensStopped() {
            let stored = Message(id: UUID())
            stored.role = "assistant"
            stored.status = "streaming"
            #expect(ChatMessage(stored).status == .stopped)
        }

        @Test func deletingOpenChatClearsScreenAndMessages() async throws {
            let (vm, context) = Self.vm()
            vm.send("Hi", client: Self.client(), model: Self.model)
            await vm.waitForReply()
            await vm.waitForTitle()
            vm.delete(try #require(vm.chat))
            #expect(vm.messages.isEmpty)
            #expect(vm.chat == nil)
            #expect(try Self.chats(context).isEmpty)
            #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
        }
    }
}

/// Folders: creating one, unique names, the Folders page's order.
@MainActor
struct FolderTests {
    private static func folders(_ context: ModelContext) throws -> [Folder] {
        try context.fetch(FetchDescriptor<Folder>(sortBy: Folder.newestFirst))
    }

    @Test func createTrimsTheName() throws {
        let context = ModelContext(Storage.inMemory())
        guard case .created(let folder) = Folder.create(named: "  Home Lab \n", in: context) else {
            Issue.record("not created"); return
        }
        #expect(folder.name == "Home Lab")
        #expect(try Self.folders(context).map(\.name) == ["Home Lab"])
    }

    @Test func blankNameSavesNothing() throws {
        let context = ModelContext(Storage.inMemory())
        guard case .blank = Folder.create(named: "   ", in: context) else {
            Issue.record("not blank"); return
        }
        #expect(try Self.folders(context).isEmpty)
    }

    @Test func takenNameIgnoringCaseAndSpacesSavesNothing() throws {
        let context = ModelContext(Storage.inMemory())
        _ = Folder.create(named: "Home Lab", in: context)
        guard case .taken(let name) = Folder.create(named: " home LAB ", in: context) else {
            Issue.record("not refused"); return
        }
        #expect(name == "home LAB")
        #expect(try Self.folders(context).count == 1)
        // A different name is fine.
        guard case .created = Folder.create(named: "Home Lab 2", in: context) else {
            Issue.record("not created"); return
        }
        #expect(try Self.folders(context).count == 2)
    }

    @Test func foldersListNewestFirst() throws {
        let context = ModelContext(Storage.inMemory())
        _ = Folder.create(named: "Old", in: context)
        guard case .created(let newer) = Folder.create(named: "New", in: context) else {
            Issue.record("not created"); return
        }
        newer.createdAt = Date().addingTimeInterval(60)
        #expect(try Self.folders(context).map(\.name) == ["New", "Old"])
    }
}

/// Renaming and deleting folders.
@MainActor
struct FolderActionTests {
    @Test func renameFollowsTheUniqueRule() throws {
        let context = ModelContext(Storage.inMemory())
        guard case .created(let lab) = Folder.create(named: "Home Lab", in: context),
              case .created = Folder.create(named: "Recipes", in: context) else {
            Issue.record("not created"); return
        }
        guard case .taken(let name) = Folder.rename(lab, to: " recipes ", in: context) else {
            Issue.record("not refused"); return
        }
        #expect(name == "recipes")
        #expect(lab.name == "Home Lab")
        guard case .unchanged = Folder.rename(lab, to: "   ", in: context),
              case .unchanged = Folder.rename(lab, to: "Home Lab", in: context) else {
            Issue.record("changed"); return
        }
        // Only the case changing is fine: the folder it matches is itself.
        guard case .renamed = Folder.rename(lab, to: "home lab", in: context) else {
            Issue.record("not renamed"); return
        }
        #expect(lab.name == "home lab")
        guard case .renamed = Folder.rename(lab, to: "  Servers ", in: context) else {
            Issue.record("not renamed"); return
        }
        #expect(lab.name == "Servers")
    }

    @Test func chatCountLine() {
        #expect(Folder.chatCount(0) == "No Chats")
        #expect(Folder.chatCount(1) == "1 Chat")
        #expect(Folder.chatCount(7) == "7 Chats")
    }

    @Test func deletingAFolderDeletesItsChatsAndClearsTheScreen() throws {
        let context = ModelContext(Storage.inMemory())
        guard case .created(let folder) = Folder.create(named: "Lab", in: context) else {
            Issue.record("not created"); return
        }
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

/// Pinning: the toggle, and the drawer's Pinned and Recent sections.
@MainActor
struct PinTests {
    @Test func togglePinSetsAndClearsPinnedAt() throws {
        let context = ModelContext(Storage.inMemory())
        let chat = Chat(title: "Notes")
        let folder = Folder(name: "Lab")
        context.insert(chat)
        context.insert(folder)
        let vm = ChatVM()
        vm.context = context

        vm.togglePin(chat)
        vm.togglePin(folder)
        #expect(chat.pinnedAt != nil)
        #expect(folder.pinnedAt != nil)
        #expect(!context.hasChanges)
        vm.togglePin(chat)
        vm.togglePin(folder)
        #expect(chat.pinnedAt == nil)
        #expect(folder.pinnedAt == nil)
    }

    @Test func pinnedMixesFoldersAndChatsLatestFirst() {
        let now = Date()
        let lab = Folder(name: "Lab")
        lab.pinnedAt = now.addingTimeInterval(-60)
        let recipes = Folder(name: "Recipes")
        let notes = Chat(title: "Notes")
        notes.pinnedAt = now
        let trip = Chat(title: "Trip")
        trip.pinnedAt = now.addingTimeInterval(-120)
        let loose = Chat(title: "Loose")

        let pinned = DrawerItem.pinned(folders: [lab, recipes], chats: [trip, loose, notes])
        #expect(pinned.map(\.title) == ["Notes", "Lab", "Trip"])
        #expect(pinned.map(\.kind) == [.chat, .folder, .chat])
        #expect(pinned[1].id == lab.id.uuidString)
    }

    @Test func reorderedPinsKeepTheDraggedOrder() throws {
        let context = ModelContext(Storage.inMemory())
        let lab = Folder(name: "Lab")
        let notes = Chat(title: "Notes")
        let trip = Chat(title: "Trip")
        context.insert(lab)
        context.insert(notes)
        context.insert(trip)
        let vm = ChatVM()
        vm.context = context
        [lab].forEach(vm.togglePin)
        [notes, trip].forEach(vm.togglePin)

        // Trip dragged to the top, Lab to the bottom.
        let dragged = [DrawerItem(trip), DrawerItem(notes), DrawerItem(lab)]
        let now = Date()
        vm.reorderPinned(dragged, now: now)
        #expect(DrawerItem.pinned(folders: [lab], chats: [notes, trip]).map(\.title) == ["Trip", "Notes", "Lab"])
        #expect(trip.pinnedAt == now)
        #expect(!context.hasChanges)

        // A new pin lands on top.
        let loose = Chat(title: "Loose")
        context.insert(loose)
        vm.togglePin(loose)
        #expect(DrawerItem.pinned(folders: [lab], chats: [notes, trip, loose]).first?.title == "Loose")
    }

    @Test func recentLeavesOutPinnedChatsKeepingOrder() {
        let first = Chat(title: "First")
        let pinned = Chat(title: "Pinned")
        pinned.pinnedAt = Date()
        let last = Chat(title: "Last")
        #expect(DrawerItem.recent([first, pinned, last]).map(\.title) == ["First", "Last"])
    }
}
