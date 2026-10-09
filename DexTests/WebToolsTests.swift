//
//  WebToolsTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/8/26.
//

import Foundation
import SwiftData
import Testing
@testable import Dex

/// Web search and fetch: what is trimmed and what a reply keeps.
struct WebToolsTests {
    @Test func trimCutsLongTextAndMarksIt() {
        #expect(WebTools.trim("  short  ", to: 10) == "short")
        #expect(WebTools.trim("abcdefghij", to: 4) == "abcd […]")
    }

    @Test func searchTextListsEachHitWithItsSnippetCut() {
        let long = String(repeating: "x", count: WebTools.snippetLength + 50)
        let text = WebTools.searchText([
            .init(title: "One", url: "https://one.example", content: "First"),
            .init(title: nil, url: "https://two.example", content: long)
        ])
        #expect(text.hasPrefix("One\nhttps://one.example\nFirst\n\nhttps://two.example\n"))
        #expect(text.hasSuffix(" […]"))
        #expect(WebTools.searchText([]) == "No results.")
    }

    @Test func lookupNamesItsSubjectAndSkipsUnknownTools() {
        let search = OllamaToolCall(function: .init(name: "web_search", arguments: ["query": .string("swift 6")]))
        #expect(WebTools.lookup(for: search) == WebLookup(kind: .search, subject: "swift 6"))
        let other = OllamaToolCall(function: .init(name: "calculator", arguments: [:]))
        #expect(WebTools.lookup(for: other) == nil)
    }

    @Test func toolCallArgumentsRoundTrip() throws {
        let json = #"{"function":{"name":"web_search","arguments":{"query":"a","max_results":3,"strict":true,"tags":["x"]}}}"#
        let call = try JSONDecoder().decode(OllamaToolCall.self, from: Data(json.utf8))
        #expect(call.function.arguments["query"] == .string("a"))
        #expect(call.function.arguments["max_results"] == .number(3))
        #expect(call.function.arguments["strict"] == .bool(true))
        #expect(call.function.arguments["tags"] == .array([.string("x")]))
        let again = try JSONDecoder().decode(OllamaToolCall.self, from: JSONEncoder().encode(call))
        #expect(again == call)
    }

    @Test func webClientNeedsAKey() {
        #expect(OllamaClient.web(apiKey: "  ") == nil)
        let client = OllamaClient.web(apiKey: " key ")
        #expect(client?.baseURL.absoluteString == "https://ollama.com")
        #expect(client?.headers == ["Authorization": "Bearer key"])
    }

    @Test @MainActor func storedMessageKeepsLookups() throws {
        let context = ModelContext(Storage.inMemory())
        let lookups = [WebLookup(kind: .search, subject: "q", state: .done,
                                 sources: [.init(title: "One", url: "https://one.example")])]
        let message = ChatMessage(role: .assistant, content: "A", lookups: lookups, sequence: 1)
        let record = Message(id: message.id)
        context.insert(record)
        record.update(from: message)
        #expect(ChatMessage(record).lookups == lookups)
        record.update(from: ChatMessage(role: .assistant, content: "B", sequence: 1))
        #expect(record.lookups == nil)
    }
}

extension StubbedNetworkTests {
    /// A reply that calls tools: the loop, its limits, and what is kept.
    @Suite(.serialized)
    @MainActor
    struct WebReplyTests {
        private static func model(capabilities: [String]? = ["completion", "tools"]) -> OllamaModel {
            OllamaModel(name: "qwen3:8b", size: 0, digest: "",
                        details: .init(format: nil, family: nil, parameterSize: nil, quantizationLevel: nil),
                        capabilities: capabilities)
        }

        /// ollama.com, answered by the same stub as the server.
        private static func web() -> OllamaClient {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OllamaStubProtocol.self]
            return OllamaClient(baseURL: URL(string: "https://ollama.com")!, headers: ["Authorization": "Bearer key"],
                                session: URLSession(configuration: configuration))
        }

        private static func body(_ request: URLRequest) throws -> [String: Any] {
            let data = try #require(request.httpBody)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        private static func chats() -> [URLRequest] {
            OllamaStubProtocol.requests.filter { $0.url?.path == "/api/chat" }
        }

        private static let searchCall =
            #"{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"web_search","arguments":{"query":"ollama news"}}}]}}"#
            + "\n" + #"{"message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":100,"eval_count":10}"# + "\n"
        private static let answer =
            #"{"message":{"role":"assistant","content":"Here is the news."},"done":true,"done_reason":"stop","prompt_eval_count":900,"eval_count":20}"# + "\n"

        @Test func searchResultIsFedBackAndOnlySourcesAreKept() async throws {
            var chatCount = 0
            let client = OllamaStubProtocol.client { request in
                switch request.url?.path {
                case "/api/web_search":
                    // As ollama.com sends it: JSON labeled text/html.
                    return .init(contentType: "text/html; charset=utf-8",
                                 body: #"{"results":[{"title":"News","url":"https://news.example","content":"Big news"}]}"#)
                default:
                    chatCount += 1
                    return .init(contentType: "application/x-ndjson", body: chatCount == 1 ? Self.searchCall : Self.answer)
                }
            }
            let chat = ChatVM()
            chat.send("What's new?", client: client, model: Self.model(), web: Self.web())
            await chat.waitForReply()

            let reply = chat.messages[1]
            #expect(reply.status == .done)
            #expect(reply.content == "Here is the news.")
            #expect(reply.lookups == [WebLookup(kind: .search, subject: "ollama news", state: .done,
                                                sources: [.init(title: "News", url: "https://news.example")])])
            // The first round's prompt: what the next turn sends, without the results.
            #expect(reply.promptTokens == 100)
            #expect(reply.outputTokens == 20)

            let search = try #require(OllamaStubProtocol.requests.first { $0.url?.path == "/api/web_search" })
            #expect(search.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(try Self.body(search)["query"] as? String == "ollama news")

            let chats = Self.chats()
            #expect(chats.count == 2)
            let first = try Self.body(chats[0])
            #expect((first["tools"] as? [[String: Any]])?.count == 2)
            let messages = try #require(try Self.body(chats[1])["messages"] as? [[String: Any]])
            #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "tool"])
            #expect((messages[1]["tool_calls"] as? [Any])?.count == 1)
            #expect(messages[2]["tool_name"] as? String == "web_search")
            #expect((messages[2]["content"] as? String)?.contains("Big news") == true)

            // The next turn carries the answer, not what the search brought in.
            #expect(ChatVM.history(chat.messages).map(\.role) == ["user", "assistant"])
        }

        @Test func modelWithoutToolsOrWithoutKeyGetsNoTools() async throws {
            let client = OllamaStubProtocol.client { _ in .init(contentType: "application/x-ndjson", body: Self.answer) }
            let chat = ChatVM()
            chat.send("Hi", client: client, model: Self.model(capabilities: ["completion"]), web: Self.web())
            await chat.waitForReply()
            chat.send("Again", client: client, model: Self.model(), web: nil)
            await chat.waitForReply()
            #expect(try Self.chats().allSatisfy { try Self.body($0)["tools"] == nil })
        }

        @Test func lastRoundGoesWithoutToolsSoTheModelAnswers() async throws {
            let client = OllamaStubProtocol.client { request in
                switch request.url?.path {
                case "/api/web_search":
                    return .init(body: #"{"results":[]}"#)
                default:
                    let tools = (try? Self.body(request))?["tools"]
                    return .init(contentType: "application/x-ndjson", body: tools == nil ? Self.answer : Self.searchCall)
                }
            }
            let chat = ChatVM()
            chat.send("Loop", client: client, model: Self.model(), web: Self.web())
            await chat.waitForReply()
            #expect(chat.messages[1].status == .done)
            #expect(Self.chats().count == WebTools.maxRounds + 1)
            #expect(chat.messages[1].lookups?.count == WebTools.maxSearches)
        }

        @Test func thinkingRefusedAfterASearchKeepsTheSearch() async throws {
            var chatCount = 0
            let client = OllamaStubProtocol.client { request in
                if request.url?.path == "/api/web_search" { return .init(body: #"{"results":[]}"#) }
                chatCount += 1
                switch chatCount {
                case 1: return .init(contentType: "application/x-ndjson", body: Self.searchCall)
                case 2: return .init(status: 400, body: #"{"error":"\"qwen3:8b\" does not support thinking"}"#)
                default: return .init(contentType: "application/x-ndjson", body: Self.answer)
                }
            }
            let chat = ChatVM()
            chat.send("Hi", client: client, model: Self.model(capabilities: ["tools", "thinking"]), web: Self.web())
            await chat.waitForReply()
            #expect(chat.messages[1].status == .done)
            #expect(chat.messages[1].lookups?.count == 1)
            #expect(OllamaStubProtocol.requests.filter { $0.url?.path == "/api/web_search" }.count == 1)
            let last = try Self.body(try #require(Self.chats().last))
            #expect(last["think"] == nil)
            #expect((last["messages"] as? [[String: Any]])?.map { $0["role"] as? String } == ["user", "assistant", "tool"])
        }

        @Test(arguments: [
            (403, "<html><head><title>Just a moment...</title></head></html>",
             "The search failed (HTTP 403: ollama.com sent a web page instead of results: Just a moment)."),
            (200, "<html><body>Sign in</body></html>", "The search failed (HTTP 200: ollama.com sent a web page instead of results: Sign in)."),
            (401, "", "The search failed (HTTP 401)."),
        ])
        func blockedSearchSaysWhatCameBackNotCloudflareAccess(_ status: Int, _ html: String, _ expected: String) async {
            OllamaStubProtocol.handler = { _ in .init(status: status, contentType: html.isEmpty ? "text/plain" : "text/html", body: html) }
            OllamaStubProtocol.requests = []
            var budget = WebTools.Budget()
            let call = OllamaToolCall(function: .init(name: "web_search", arguments: ["query": .string("q")]))
            let (_, lookup) = await WebTools.run(call, client: Self.web(), budget: &budget)
            #expect(lookup?.error == expected)
        }

        @Test func systemErrorsLoseTheirPeriodInsideParentheses() {
            #expect(WebTools.reason(URLError(.timedOut)).hasSuffix(".") == false)
            #expect(WebTools.reason(OllamaClient.Failure.http(status: 429, message: "rate limited")) == "HTTP 429: rate limited")
        }

        @Test func stoppedSearchIsNotAFailure() async {
            OllamaStubProtocol.handler = { _ in .init(body: #"{"results":[]}"#) }
            OllamaStubProtocol.requests = []
            let call = OllamaToolCall(function: .init(name: "web_search", arguments: ["query": .string("q")]))
            let web = Self.web()
            // Cancelled before it starts: the main actor runs it only at the await.
            let task = Task {
                var budget = WebTools.Budget()
                return await WebTools.run(call, client: web, budget: &budget)
            }
            task.cancel()
            let (result, lookup) = await task.value
            #expect(result == "Stopped.")
            #expect(lookup?.state == .running)
            #expect(lookup?.error == nil)
        }

        @Test func spentBudgetAnswersWithoutARequest() async {
            OllamaStubProtocol.handler = { _ in .init(body: #"{"title":"Page","content":"Text"}"#) }
            OllamaStubProtocol.requests = []
            var budget = WebTools.Budget()
            budget.fetches = 0
            let call = OllamaToolCall(function: .init(name: "web_fetch", arguments: ["url": .string("https://a.example")]))
            let (result, lookup) = await WebTools.run(call, client: Self.web(), budget: &budget)
            #expect(result.hasPrefix("No page reads left"))
            #expect(lookup?.state == .failed)
            #expect(lookup?.error == "No page reads left for this answer.")
            #expect(OllamaStubProtocol.requests.isEmpty)
        }

        @Test func failedSearchIsToldToTheModel() async {
            OllamaStubProtocol.handler = { _ in .init(status: 429, body: #"{"error":"rate limited"}"#) }
            OllamaStubProtocol.requests = []
            var budget = WebTools.Budget()
            let call = OllamaToolCall(function: .init(name: "web_search", arguments: ["query": .string("q")]))
            let (result, lookup) = await WebTools.run(call, client: Self.web(), budget: &budget)
            #expect(result == "The search failed (HTTP 429: rate limited).")
            #expect(lookup?.state == .failed)
            #expect(lookup?.error == result)
            #expect(budget.searches == WebTools.maxSearches - 1)
        }
    }
}
