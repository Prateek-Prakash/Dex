//
//  ReplyPartsTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation
import Testing
@testable import Dex

/// Turning the server's reply steps into what the transcript shows.
struct ReplyPartsTests {
    @Test func lookupsComeFromTheServersWebTools() {
        #expect(WebLookup(name: "search_web", arguments: #"{"query": "paris"}"#) == WebLookup(kind: .search, subject: "paris"))
        #expect(WebLookup(name: "fetch_url", arguments: #"{"url": "https://a.dev"}"#) == WebLookup(kind: .fetch, subject: "https://a.dev"))
        #expect(WebLookup(name: "search_web", arguments: "") == nil)
        #expect(WebLookup(name: "run_code", arguments: #"{"code": "1"}"#) == nil)
    }

    @Test(arguments: [
        (WebLookup(kind: .search, subject: "q"), "Searching “q”…"),
        (WebLookup(kind: .search, subject: "q", state: .done), "Searched “q”"),
        (WebLookup(kind: .fetch, subject: "u"), "Reading “u”…"),
        (WebLookup(kind: .fetch, subject: "u", state: .failed), "Read “u”"),
    ])
    func labelsSayWhatIsHappening(_ lookup: WebLookup, _ label: String) {
        #expect(lookup.label == label)
    }

    @Test func searchOutputNamesItsSources() {
        var lookup = WebLookup(kind: .search, subject: "q")
        lookup.finish(output: #"[{"title":" BBC ","link":"https://bbc.com/w","snippet":"x"},{"title":"","link":"https://met.ie/a"},{"title":"No link"}]"#)
        #expect(lookup.state == .done)
        #expect(lookup.sources == [.init(title: "BBC", url: "https://bbc.com/w"), .init(title: "met.ie", url: "https://met.ie/a")])
        var page = WebLookup(kind: .fetch, subject: "https://a.dev/x")
        page.finish(output: "page text")
        #expect(page.sources == [.init(title: "a.dev", url: "https://a.dev/x")])
    }

    @Test func liveStepsBuildTheReply() {
        var parts = ReplyParts()
        parts.appendThought("Let me ", itemID: "r1")
        parts.appendThought("check.", itemID: "r1")
        // Started with no arguments yet: no row until the subject is known.
        parts.apply(.functionCall(id: "x", callID: "k", name: "search_web", arguments: ""), isDone: false)
        #expect(parts.lookups.isEmpty)
        parts.apply(.functionCall(id: "x", callID: "k", name: "search_web", arguments: #"{"query":"q"}"#), isDone: true)
        // The server sends a finished step more than once.
        parts.apply(.functionCall(id: "x", callID: "k", name: "search_web", arguments: #"{"query":"q"}"#), isDone: true)
        #expect(parts.lookups.map(\.state) == [.running])
        parts.apply(.functionCallOutput(callID: "k", text: "[]"), isDone: true)
        parts.appendThought("Found it.", itemID: "r2")
        parts.appendText("\n\nAnswer")
        #expect(parts.content == "Answer")
        #expect(parts.thinking == "Let me check.\n\nFound it.")
        #expect(parts.lookups.map(\.state) == [.done])
    }

    @Test func finishedOutputIsTheWholeReply() {
        let parts = ReplyParts(output: [
            .reasoning(id: "r1", text: "Plan.", duration: 1),
            .message(id: "m1", text: "Looking.\n"),
            .functionCall(id: "x", callID: "k", name: "fetch_url", arguments: #"{"url":"https://a.dev"}"#),
            .functionCallOutput(callID: "k", text: "text"),
            .message(id: "m2", text: "Done."),
            .other(type: "web_search_call"),
        ])
        #expect(parts.content == "Looking.\n\nDone.")
        #expect(parts.thinking == "Plan.")
        #expect(parts.lookups == [WebLookup(kind: .fetch, subject: "https://a.dev", state: .done,
                                            sources: [.init(title: "a.dev", url: "https://a.dev")])])
        #expect(ReplyParts(output: [], fallback: "Saved text").content == "Saved text")
    }

    @Test func serverMessagesBecomeChatMessages() throws {
        let chat = try JSONDecoder().decode(WebUIChat.self, from: Data(WebUIFixtures.chat.utf8))
        let messages = CacheSync.messages(chat)
        #expect(messages.map(\.id) == ["u1", "a2"])
        #expect(messages.map(\.sequence) == [0, 1])
        let reply = messages[1]
        #expect(reply.status == .done)
        #expect(reply.content == "Clear, 17°C.")
        #expect(reply.thinking == "Look it up.")
        #expect(reply.lookups?.first?.subject == "current weather in Paris")
        #expect(reply.promptTokens == 4981)
        #expect(reply.parentId == "u1")
        #expect(messages[0].childrenIds == ["a1", "a2"])
    }

    @Test func unfinishedAndFailedRepliesKeepTheirState() throws {
        let json = """
        {"currentId":"b","messages":{
          "a":{"id":"a","parentId":null,"childrenIds":["b"],"role":"user","content":"Q"},
          "b":{"id":"b","parentId":"a","childrenIds":[],"role":"assistant","content":"","done":false},
          "c":{"id":"c","parentId":"a","childrenIds":[],"role":"assistant","content":"","done":true,"error":{"content":"Out of memory"}},
          "d":{"id":"d","parentId":"a","childrenIds":[],"role":"assistant","content":"Half","done":true,"dex_stopped":true}}}
        """
        let history = try JSONDecoder().decode(WebUIHistory.self, from: Data(json.utf8))
        #expect(CacheSync.message(try #require(history.messages["b"]), sequence: 1).status == .streaming)
        let failed = CacheSync.message(try #require(history.messages["c"]), sequence: 1)
        #expect(failed.status == .failed)
        #expect(failed.error == "Out of memory")
        let stopped = CacheSync.message(try #require(history.messages["d"]), sequence: 1)
        #expect(stopped.status == .stopped)
        #expect(stopped.content == "Half")
    }
}
