//
//  ChatTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation
import Testing
@testable import Dex

extension StubbedNetworkTests {
    /// The chat stream and the in-memory chat built on it.
    @Suite(.serialized)
    @MainActor
    struct ChatTests {
        private static func model(_ name: String = "gemma4:12b", capabilities: [String]? = ["completion"]) -> OllamaModel {
            OllamaModel(name: name, size: 0, digest: "",
                        details: .init(format: nil, family: nil, parameterSize: nil, quantizationLevel: nil),
                        capabilities: capabilities)
        }

        private static func body(_ request: URLRequest?) throws -> [String: Any] {
            let data = try #require(request?.httpBody)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        @Test func requestCarriesWindowAndOmitsUnsetThinking() async throws {
            let client = OllamaStubProtocol.client { _ in
                .init(contentType: "application/x-ndjson", body: #"{"message":{"content":"Hi"},"done":true}"# + "\n")
            }
            let request = OllamaChatRequest(model: "gemma4:12b", messages: [.init(role: "user", content: "Hello")])
            for try await _ in client.chat(request) {}
            let sent = OllamaStubProtocol.requests.first
            #expect(sent?.url?.path == "/api/chat")
            #expect(sent?.httpMethod == "POST")
            let body = try Self.body(sent)
            #expect(body["model"] as? String == "gemma4:12b")
            #expect(body["stream"] as? Bool == true)
            #expect(body["keep_alive"] as? String == "30m")
            #expect((body["options"] as? [String: Any])?["num_ctx"] as? Int == 65_536)
            #expect(body["think"] == nil)
            #expect((body["messages"] as? [[String: String]]) == [["role": "user", "content": "Hello"]])
        }

        @Test func replyStreamsThinkingContentAndTokens() async throws {
            let client = OllamaStubProtocol.client { _ in
                .init(contentType: "application/x-ndjson", body: """
                {"message":{"role":"assistant","content":"","thinking":"Let me "}}
                {"message":{"role":"assistant","content":"","thinking":"see."}}
                {"message":{"role":"assistant","content":"Hello"}}
                {"message":{"role":"assistant","content":" there"}}
                {"message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":120,"eval_count":30}

                """)
            }
            let chat = ChatVM()
            chat.send("  Hi  ", client: client, model: Self.model(capabilities: ["completion", "thinking"]))
            await chat.waitForReply()

            #expect(chat.messages.count == 2)
            #expect(chat.messages[0].role == .user)
            #expect(chat.messages[0].content == "Hi")
            let reply = chat.messages[1]
            #expect(reply.status == .done)
            #expect(reply.content == "Hello there")
            #expect(reply.thinking == "Let me see.")
            #expect(reply.model == "gemma4:12b")
            #expect(reply.sequence == 1)
            #expect(chat.contextUsed == 150)
            #expect(try Self.body(OllamaStubProtocol.requests.first)["think"] as? Bool == true)
        }

        @Test func replyWithoutFinalLineFails() async {
            let client = OllamaStubProtocol.client { _ in
                .init(contentType: "application/x-ndjson", body: #"{"message":{"content":"Half an"}}"# + "\n")
            }
            let chat = ChatVM()
            chat.send("Hi", client: client, model: Self.model())
            await chat.waitForReply()
            #expect(chat.messages.last?.status == .failed)
            #expect(chat.messages.last?.content == "Half an")
            #expect(chat.messages.last?.error == "The answer was cut off before it finished.")
            #expect(chat.canRetry)
        }

        @Test func replyCutByLengthFails() async {
            let client = OllamaStubProtocol.client { _ in
                .init(contentType: "application/x-ndjson", body: #"{"message":{"content":"Long"},"done":true,"done_reason":"length"}"# + "\n")
            }
            let chat = ChatVM()
            chat.send("Hi", client: client, model: Self.model())
            await chat.waitForReply()
            #expect(chat.messages.last?.status == .failed)
            #expect(chat.messages.last?.error == "The answer reached the model's length limit and was cut off.")
        }

        @Test func emptyReplyFails() async {
            let client = OllamaStubProtocol.client { _ in
                .init(contentType: "application/x-ndjson", body: #"{"message":{"content":"","thinking":"Hmm"},"done":true}"# + "\n")
            }
            let chat = ChatVM()
            chat.send("Hi", client: client, model: Self.model())
            await chat.waitForReply()
            #expect(chat.messages.last?.status == .failed)
            #expect(chat.messages.last?.error == "No answer came back.")
        }

        @Test func streamedErrorFails() async {
            let client = OllamaStubProtocol.client { _ in
                .init(contentType: "application/x-ndjson", body: """
                {"message":{"content":"Partial"}}
                {"error":"model runner has unexpectedly stopped"}

                """)
            }
            let chat = ChatVM()
            chat.send("Hi", client: client, model: Self.model())
            await chat.waitForReply()
            #expect(chat.messages.last?.status == .failed)
            #expect(chat.messages.last?.error == "Ollama stopped with an error: model runner has unexpectedly stopped")
        }

        @Test func modelThatCannotThinkIsAskedAgainWithout() async throws {
            let client = OllamaStubProtocol.client { request in
                let body = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                if body?["think"] != nil {
                    return .init(status: 400, body: #"{"error":"\"gemma4:12b\" does not support thinking"}"#)
                }
                return .init(contentType: "application/x-ndjson", body: #"{"message":{"content":"Hi"},"done":true}"# + "\n")
            }
            let chat = ChatVM()
            chat.send("Hi", client: client, model: Self.model(capabilities: ["thinking"]))
            await chat.waitForReply()
            #expect(OllamaStubProtocol.requests.count == 2)
            #expect(chat.messages.last?.status == .done)
            #expect(chat.messages.last?.content == "Hi")
        }

        @Test func missingModelOnServerReadsPlainly() async {
            let client = OllamaStubProtocol.client { _ in
                .init(status: 404, body: #"{"error":"model 'gemma4:12b' not found"}"#)
            }
            let chat = ChatVM()
            chat.send("Hi", client: client, model: Self.model())
            await chat.waitForReply()
            #expect(chat.messages.last?.error == "The server has no model named gemma4:12b. Pick another below.")
        }

        @Test func noServerOrModelFailsWithoutARequest() {
            let chat = ChatVM()
            chat.send("Hi", client: nil, model: Self.model())
            #expect(chat.messages.last?.error == "No server is set. Add one in Settings.")
            chat.retry(client: OllamaStubProtocol.client { _ in .init() }, model: nil)
            #expect(chat.messages.count == 2)
            #expect(chat.messages.last?.error == "No model is picked. Pick one below.")
        }

        @Test func retryReplacesTheFailedReplyAndSendsHistory() async throws {
            var calls = 0
            let client = OllamaStubProtocol.client { _ in
                calls += 1
                if calls == 1 { return .init(status: 500, body: #"{"error":"boom"}"#) }
                return .init(contentType: "application/x-ndjson", body: #"{"message":{"content":"Fixed"},"done":true}"# + "\n")
            }
            let chat = ChatVM()
            chat.send("Hi", client: client, model: Self.model())
            await chat.waitForReply()
            #expect(chat.messages.last?.error == "HTTP 500: boom")
            chat.retry(client: client, model: Self.model())
            await chat.waitForReply()
            #expect(chat.messages.map(\.content) == ["Hi", "Fixed"])
            #expect(chat.messages.map(\.sequence) == [0, 1])
            // The failed reply never reached the model.
            let messages = try Self.body(OllamaStubProtocol.requests.last)["messages"] as? [[String: String]]
            #expect(messages == [["role": "user", "content": "Hi"]])
        }

        @Test func historyKeepsUserMessagesAndRepliesWithText() {
            let messages = [
                ChatMessage(role: .user, content: "One", sequence: 0),
                ChatMessage(role: .assistant, content: "Partial", thinking: "secret", sequence: 1, status: .stopped),
                ChatMessage(role: .user, content: "Two", sequence: 2),
                ChatMessage(role: .assistant, content: "Broken", sequence: 3, status: .failed),
                ChatMessage(role: .assistant, content: "", sequence: 4, status: .stopped),
                ChatMessage(role: .user, content: "Three", sequence: 5),
            ]
            #expect(ChatVM.history(messages.reversed()) == [
                .init(role: "user", content: "One"),
                .init(role: "assistant", content: "Partial"),
                .init(role: "user", content: "Two"),
                .init(role: "user", content: "Three"),
            ])
        }

        @Test func blankMessagesAreNotSent() {
            let chat = ChatVM()
            chat.send("  \n ", client: nil, model: nil)
            #expect(chat.messages.isEmpty)
        }

        @Test func resetEmptiesTheChatAndLeavesIncognito() async {
            let client = OllamaStubProtocol.client { _ in
                .init(contentType: "application/x-ndjson", body: #"{"message":{"content":"Hi"},"done":true}"# + "\n")
            }
            let chat = ChatVM()
            chat.isIncognito = true
            chat.send("Hi", client: client, model: Self.model())
            chat.reset()
            await chat.waitForReply()
            #expect(chat.messages.isEmpty)
            #expect(!chat.isIncognito)
        }

        @Test(arguments: [
            (URLError(.timedOut) as Error, "Ollama took too long to answer. The model may still be loading; try again in a minute."),
            (URLError(.notConnectedToInternet) as Error, "Couldn't reach Ollama. Check the server address and that the server is on."),
            (OllamaClient.Failure.http(status: 530, message: "") as Error, "Couldn't reach Ollama (530). Check that the server is on and Ollama is running."),
            (OllamaClient.Failure.http(status: 524, message: "") as Error, "Ollama took too long to start answering. The model may still be loading; try again in a minute."),
            (OllamaClient.Failure.accessDenied as Error, "Cloudflare Access refused the request. Check the Access Client ID and Secret in Settings."),
        ])
        func errorsReadPlainly(_ error: Error, _ expected: String) {
            #expect(ChatVM.describe(error, model: "gemma4:12b") == expected)
        }

        @Test func contextNeverShrinksWhenOllamaCountsOnlyUncachedTokens() {
            func reply(_ sequence: Int, prompt: Int, output: Int) -> ChatMessage {
                ChatMessage(role: .assistant, content: "r", sequence: sequence, promptTokens: prompt, outputTokens: output)
            }
            let user = { (sequence: Int) in ChatMessage(role: .user, content: "q", sequence: sequence) }
            #expect(ChatVM.contextUsed([user(0)]) == nil)
            // Full counts: the last reply's prompt plus output.
            #expect(ChatVM.contextUsed([user(0), reply(1, prompt: 100, output: 50), user(2), reply(3, prompt: 180, output: 40)]) == 220)
            // A cached turn reports a small prompt: the running total stands in.
            #expect(ChatVM.contextUsed([user(0), reply(1, prompt: 100, output: 50), user(2), reply(3, prompt: 12, output: 40)]) == 190)
            // A stopped reply without counts leaves the last known size.
            let stopped = ChatMessage(role: .assistant, content: "p", sequence: 5, status: .stopped)
            #expect(ChatVM.contextUsed([user(0), reply(1, prompt: 100, output: 50), user(4), stopped]) == 150)
        }
    }
}

/// The transcript's scroll rules: turns, what's pinned, the room left for
/// a reply, the end, and what stops following.
struct TranscriptLayoutTests {
    private func message(_ role: ChatMessage.Role, _ sequence: Int, _ status: ChatMessage.Status = .done) -> ChatMessage {
        ChatMessage(role: role, content: "\(sequence)", sequence: sequence, status: status)
    }

    @Test func turnsGroupEachMessageWithItsReplies() {
        let a = message(.user, 0), b = message(.assistant, 1), c = message(.user, 2), d = message(.assistant, 3)
        #expect(TranscriptLayout.turns([a, b, c, d]).map { $0.map(\.sequence) } == [[0, 1], [2, 3]])
        #expect(TranscriptLayout.turns([a, c]).map { $0.map(\.sequence) } == [[0], [2]])
        #expect(TranscriptLayout.turns([]).isEmpty)
    }

    @Test func theMessageSentIsPinnedWhileItsReplyComes() {
        let first = message(.user, 0), reply = message(.assistant, 1)
        let next = message(.user, 2), coming = message(.assistant, 3, .streaming)
        #expect(TranscriptLayout.pinTarget([first, reply, next, coming]) == next.id)
        // An opened chat, its replies done: nothing to pin.
        #expect(TranscriptLayout.pinTarget([first, reply]) == nil)
        #expect(TranscriptLayout.pinTarget([]) == nil)
    }

    @Test func roomShrinksToNothingAsTheReplyGrows() {
        #expect(TranscriptLayout.room(viewport: 600, turn: 100, padding: 16) == 484)
        #expect(TranscriptLayout.room(viewport: 600, turn: 584, padding: 16) == 0)
        #expect(TranscriptLayout.room(viewport: 600, turn: 900, padding: 16) == 0)
    }

    @Test func theEndIgnoresTheAreaUnderTheComposer() {
        // Scrolled to the end: the visible rect runs on under the composer.
        #expect(TranscriptLayout.isAtBottom(visibleMaxY: 1145, bottomInset: 145, contentHeight: 1000))
        // The newest lines under the composer: not at the end.
        #expect(!TranscriptLayout.isAtBottom(visibleMaxY: 1000, bottomInset: 145, contentHeight: 1000 + 145))
        // A line or two short still counts.
        #expect(TranscriptLayout.isAtBottom(visibleMaxY: 1095, bottomInset: 145, contentHeight: 1000))
    }

    @Test func onlyTheReadersScrollUpStopsFollowing() {
        #expect(TranscriptLayout.stopsFollowing(from: 500, to: 480, isReaderScrolling: true))
        #expect(!TranscriptLayout.stopsFollowing(from: 500, to: 520, isReaderScrolling: true))
        // Growth, or this view's own scroll, never does.
        #expect(!TranscriptLayout.stopsFollowing(from: 500, to: 480, isReaderScrolling: false))
    }
}
