//
//  CompactionTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/15/26.
//

import Foundation
import SwiftData
import Testing
@testable import Dex

/// The server compacting long chats: its summary, its live status, and the
/// context ring starting over.
@MainActor
struct CompactionTests {
    @Test func summariesDecodeAndAreKept() throws {
        let json = #"{"id":"u3","parentId":"a2","childrenIds":[],"role":"user","content":"Next","contextSummary":"  User has three leagues.  "}"#
        let remote = try JSONDecoder().decode(WebUIMessage.self, from: Data(json.utf8))
        #expect(remote.contextSummary == "  User has three leagues.  ")
        #expect(CacheSync.message(remote, sequence: 0).contextSummary == "  User has three leagues.  ")
        let blank = try JSONDecoder().decode(WebUIMessage.self, from: Data(#"{"id":"x","role":"user","content":"","contextSummary":"  "}"#.utf8))
        #expect(blank.contextSummary == nil)

        let record = Message(id: "m")
        record.update(from: ChatMessage(id: "m", role: .user, contextSummary: "Kept", sequence: 0))
        #expect(ChatMessage(record).contextSummary == "Kept")
    }

    @Test func compactingEventsDecode() {
        func event(_ data: String) -> WebUIEvent? {
            WebUIEvent.decode(Data(#"{"chat_id":"c1","message_id":"a1","data":{"type":"context_compaction","data":\#(data)}}"#.utf8))
        }
        #expect(event(#"{"action":"context_compaction","description":"Compacting context","done":false}"#)
                == .compacting(chatID: "c1", messageID: "a1", isDone: false))
        #expect(event(#"{"description":"Compacted","done":true}"#) == .compacting(chatID: "c1", messageID: "a1", isDone: true))
        #expect(WebUIEvent.compacting(chatID: "c", messageID: "a", isDone: true).messageID == "a")
    }

    @Test func theRingDropsWhenTheServerCompacts() {
        // As in "Sleeper Fantasy Lineup": the summary sits on a message well
        // before the replies measured before compaction (41.7K to 46.2K).
        let messages = [
            ChatMessage(id: "u1", role: .user, contextSummary: "Earlier: leagues found.", sequence: 0),
            ChatMessage(id: "a1", role: .assistant, sequence: 1, promptTokens: 41_744, outputTokens: 588),
            ChatMessage(id: "u2", role: .user, sequence: 2),
            ChatMessage(id: "a2", role: .assistant, sequence: 3, promptTokens: 45_717, outputTokens: 433),
            ChatMessage(id: "u3", role: .user, sequence: 4),
            // Compacted before this reply: its prompt is the summary and recent messages.
            ChatMessage(id: "a3", role: .assistant, sequence: 5, promptTokens: 15_459, outputTokens: 1_286),
        ]
        // Seen happening here, or (in a chat compacted elsewhere) told by the
        // summary and a prompt that fell by more than half.
        var seen = messages
        seen[5].compactedBefore = true
        seen[0].contextSummary = nil
        #expect(ChatVM.contextUsed(seen) == 16_745)
        #expect(ChatVM.contextUsed(messages) == 16_745)
        // No summary anywhere: a small prompt is a cached turn, not a compaction.
        var cached = messages
        cached[0].contextSummary = nil
        #expect(ChatVM.contextUsed(cached) == 47_436)
        // After the compaction, a cached turn's small prompt doesn't reset it again.
        let later = messages + [
            ChatMessage(id: "u4", role: .user, sequence: 6),
            ChatMessage(id: "a4", role: .assistant, sequence: 7, promptTokens: 20_000, outputTokens: 500),
            ChatMessage(id: "u5", role: .user, sequence: 8),
            ChatMessage(id: "a5", role: .assistant, sequence: 9, promptTokens: 3_000, outputTokens: 400),
        ]
        #expect(ChatVM.contextUsed(later) == 20_900)
    }

    @Test func rereadingAChatKeepsWhereItWasCompacted() throws {
        let context = ModelContext(Storage.inMemory())
        let chat = Chat(id: "c1", title: "T")
        context.insert(chat)
        let record = Message(id: "a1")
        context.insert(record)
        record.chat = chat
        record.update(from: ChatMessage(id: "a1", role: .assistant, compactedBefore: true, sequence: 1))
        let json = #"{"id":"c1","title":"T","pinned":false,"updated_at":5,"created_at":1,"chat":{"history":{"currentId":"a1","messages":{"u1":{"id":"u1","parentId":null,"childrenIds":["a1"],"role":"user","content":"Q","timestamp":1},"a1":{"id":"a1","parentId":"u1","childrenIds":[],"role":"assistant","content":"A","done":true,"timestamp":1}}}}}"#
        let remote = try JSONDecoder().decode(WebUIChat.self, from: Data(json.utf8))
        CacheSync.store(remote, into: chat, context: context)
        #expect(ChatMessage(record).compactedBefore)
    }

    @Test func summaryCoversWhatCameBefore() {
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        let messages = [
            ChatMessage(id: "u1", role: .user, createdAt: start, sequence: 0),
            ChatMessage(id: "a1", role: .assistant, createdAt: start.addingTimeInterval(60), sequence: 1),
            ChatMessage(id: "u2", role: .user, contextSummary: "S", createdAt: start.addingTimeInterval(120), sequence: 2),
        ]
        let selection = ContextSummarySelection(at: messages[2], in: messages)
        #expect(selection.count == 2)
        #expect(selection.summary == "S")
        #expect(selection.covers.hasPrefix("2 Messages, "))
    }
}

extension StubbedNetworkTests {
    @Suite(.serialized)
    @MainActor
    struct CompactionChatTests {
        @Test func aReplyThatCompactedShowsItThenPicksUpTheSummary() async throws {
            let context = ModelContext(Storage.inMemory())
            let server = FakeServer()
            let vm = ChatVM()
            vm.context = context
            vm.server = server
            vm.send("Hello", model: "gemma4:12b")
            await vm.waitForReply()
            let reply = try #require(vm.messages.last)
            let question = try #require(vm.messages.first)
            let chatID = try #require(vm.chat?.id)

            server.send(.compacting(chatID: chatID, messageID: reply.id, isDone: false))
            #expect(vm.messages.last?.isCompacting == true)
            server.send(.compacting(chatID: chatID, messageID: reply.id, isDone: true))
            #expect(vm.messages.last?.isCompacting == false)
            #expect(vm.messages.last?.compactedBefore == true)

            // The server saved its summary on the question, without touching the chat's time.
            server.state.setChat(chatID, #"{"id":"\#(chatID)","title":"T","pinned":false,"updated_at":1,"created_at":1,"chat":{"history":{"currentId":"\#(reply.id)","messages":{"\#(question.id)":{"id":"\#(question.id)","parentId":null,"childrenIds":["\#(reply.id)"],"role":"user","content":"Hello","contextSummary":"Earlier talk.","timestamp":1},"\#(reply.id)":{"id":"\#(reply.id)","parentId":"\#(question.id)","childrenIds":[],"role":"assistant","content":"Hi","done":true,"timestamp":1}}}}}"#)
            server.send(.finished(chatID: chatID, messageID: reply.id, output: [.message(id: "m", text: "Hi")], usage: nil))
            try await Task.sleep(for: .milliseconds(200))
            #expect(vm.messages.first?.contextSummary == "Earlier talk.")
            #expect(vm.messages.last?.content == "Hi")
        }
    }
}
