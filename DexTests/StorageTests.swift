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

        @Test func leavingMidReplySavesItStopped() async throws {
            let (vm, context) = Self.vm()
            // Left before the reply's task gets to run.
            vm.send("Hi", client: Self.client(), model: Self.model)
            let chat = try #require(vm.chat)
            vm.reset()
            await vm.waitForReply()
            #expect(chat.sortedMessages.last?.status == "stopped")
            #expect(try context.fetch(FetchDescriptor<Message>()).count == 2)

            vm.open(chat)
            #expect(vm.canRetry)
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
