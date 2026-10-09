//
//  ChatTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation
import SwiftData
import Testing
@testable import Dex

extension StubbedNetworkTests {
    /// Replies run on the server: started as jobs, streamed over the live
    /// channel, stopped, retried, and read back when the channel drops.
    @Suite(.serialized)
    @MainActor
    struct ChatTests {
        static let model = "gemma4:12b"

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

        /// Sends `text` and waits for the server to take the reply.
        private static func send(_ text: String, _ vm: ChatVM) async {
            vm.send(text, model: model)
            await vm.waitForReply()
        }

        /// The live channel's reply to the last request: text, then done.
        private static func answer(_ text: String, _ vm: ChatVM, _ server: FakeServer, prompt: Int = 10, output: Int = 5) throws {
            let id = try #require(vm.messages.last?.id)
            let chat = vm.chat?.id ?? ""
            server.send(.text(chatID: chat, messageID: id, delta: "\n" + text))
            server.send(.finished(chatID: chat, messageID: id, output: [.message(id: "m", text: text)],
                                  usage: WebUIUsage(promptTokens: prompt, completionTokens: output)))
        }

        @Test func newChatStartsAJobAndIsSavedUnderTheServersID() async throws {
            let (vm, server, context) = Self.vm()
            await Self.send("Hi there", vm)
            let body = try #require(server.lastReply)
            #expect(body["parent_id"] is NSNull)
            #expect(body["chat_id"] == nil)
            #expect(body["session_id"] as? String == "sid")
            #expect(body["model"] as? String == Self.model)
            #expect(body["messages"] as? [[String: String]] == [["role": "user", "content": "Hi there"]])
            #expect(body["background_tasks"] != nil)
            #expect((body["params"] as? [String: Int])?["num_ctx"] == 65_536)
            #expect((body["features"] as? [String: Bool])?["web_search"] == true)
            let user = try #require(body["user_message"] as? [String: Any])
            #expect(user["id"] as? String == vm.messages[0].id)
            #expect(user["childrenIds"] as? [String] == [vm.messages[1].id])
            #expect(body["id"] as? String == vm.messages[1].id)

            let chat = try #require(try Self.chats(context).first)
            #expect(chat.id == "c1")
            #expect(chat.title == "Hi there")
            #expect(chat.sortedMessages.map(\.status) == ["done", "streaming"])
            #expect(vm.isStreaming)
            #expect(vm.streamingChatIDs == ["c1"])
        }

        @Test func liveEventsBuildTheReplyAndFinishSavesIt() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("Weather?", vm)
            let id = try #require(vm.messages.last?.id)
            server.send(.reasoning(chatID: "c1", messageID: id, itemID: "r1", delta: "Look it up."))
            server.send(.item(chatID: "c1", messageID: id, item: .functionCall(id: "x", callID: "k", name: "search_web",
                                                                              arguments: #"{"query": "paris weather"}"#), isDone: true))
            #expect(vm.messages.last?.lookups?.first?.label == "Searching “paris weather”…")
            server.send(.item(chatID: "c1", messageID: id, item: .functionCallOutput(callID: "k", text: #"[{"title":"BBC","link":"https://bbc.com/w"}]"#), isDone: true))
            server.send(.text(chatID: "c1", messageID: id, delta: "Sunny"))
            server.send(.finished(chatID: "c1", messageID: id, output: [
                .reasoning(id: "r1", text: "Look it up.", duration: 1),
                .functionCall(id: "x", callID: "k", name: "search_web", arguments: #"{"query": "paris weather"}"#),
                .functionCallOutput(callID: "k", text: #"[{"title":"BBC","link":"https://bbc.com/w"}]"#),
                .message(id: "m", text: "Sunny, 17°C."),
            ], usage: WebUIUsage(promptTokens: 40, completionTokens: 8)))

            let reply = try #require(vm.messages.last)
            #expect(reply.status == .done)
            #expect(reply.content == "Sunny, 17°C.")
            #expect(reply.thinking == "Look it up.")
            #expect(reply.lookups == [WebLookup(kind: .search, subject: "paris weather", state: .done,
                                                sources: [.init(title: "BBC", url: "https://bbc.com/w")])])
            #expect(reply.lookups?.first?.label == "Searched “paris weather”")
            #expect(vm.contextUsed == 48)
            let stored = try #require(vm.chat?.sortedMessages.last)
            #expect(stored.status == "done")
            #expect(stored.content == "Sunny, 17°C.")
            #expect(stored.promptTokens == 40)
            #expect(!vm.isStreaming)
            #expect(vm.streamingChatIDs.isEmpty)
            #expect(server.readChats == ["c1"])
        }

        @Test func eventsForOtherRepliesAreIgnored() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("Hi", vm)
            server.send(.text(chatID: "c9", messageID: "someone-else", delta: "Nope"))
            server.send(.finished(chatID: "c9", messageID: "someone-else", output: [.message(id: "m", text: "Nope")], usage: nil))
            #expect(vm.messages.last?.content == "")
            #expect(vm.isStreaming)
        }

        @Test func followUpLeavesHistoryToTheServer() async throws {
            let (vm, server, context) = Self.vm()
            await Self.send("First", vm)
            try Self.answer("One", vm, server)
            let firstReply = try #require(vm.messages.last?.id)
            await Self.send("Second", vm)
            let body = try #require(server.lastReply)
            #expect(body["chat_id"] as? String == "c1")
            #expect(body["parent_id"] as? String == firstReply)
            #expect(body["messages"] == nil)
            #expect(body["background_tasks"] == nil)
            #expect((body["user_message"] as? [String: Any])?["parentId"] as? String == firstReply)
            try Self.answer("Two", vm, server)
            let chat = try #require(try Self.chats(context).first)
            #expect(try Self.chats(context).count == 1)
            #expect(chat.sortedMessages.map(\.content) == ["First", "One", "Second", "Two"])
            #expect(chat.sortedMessages.map(\.sequence) == [0, 1, 2, 3])
            // Each message lists the next: the reply now lists the follow-up.
            #expect(chat.sortedMessages[1].childrenIds == [chat.sortedMessages[2].id])
        }

        @Test func failedReplyCanBeRetriedAsASibling() async throws {
            let (vm, server, context) = Self.vm()
            await Self.send("Hi", vm)
            let failed = try #require(vm.messages.last?.id)
            server.send(.failed(chatID: "c1", messageID: failed, message: "Model crashed"))
            #expect(vm.messages.last?.status == .failed)
            #expect(vm.messages.last?.error == "Model crashed")
            #expect(vm.canRetry)

            vm.retry(model: Self.model)
            await vm.waitForReply()
            let body = try #require(server.lastReply)
            let question = try #require(vm.messages.first)
            let retried = try #require(vm.messages.last?.id)
            #expect(retried != failed)
            #expect(body["parent_id"] is NSNull)
            #expect(body["chat_id"] as? String == "c1")
            let user = try #require(body["user_message"] as? [String: Any])
            #expect(user["id"] as? String == question.id)
            // The failed reply stays listed: the server keeps it as a sibling.
            #expect(user["childrenIds"] as? [String] == [failed, retried])
            try Self.answer("Hello", vm, server)
            #expect(vm.messages.map(\.content) == ["Hi", "Hello"])
            let stored = try #require(try Self.chats(context).first).sortedMessages
            #expect(stored.map(\.id) == [question.id, retried])
            #expect(stored[0].childrenIds == [failed, retried])
        }

        @Test func stopEndsTheJobAndSavesWhatShowed() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("Tell me a story", vm)
            let id = try #require(vm.messages.last?.id)
            server.send(.text(chatID: "c1", messageID: id, delta: "Once upon"))
            // What arrives after the last redraw still counts.
            server.send(.text(chatID: "c1", messageID: id, delta: " a time"))
            server.state.setChat("c1", FakeServer.chatJSON(id: "c1", messages: [
                (vm.messages[0].id, "user", "Tell me a story", nil), (id, "assistant", "", false),
            ]))
            vm.stop()
            #expect(vm.messages.last?.status == .stopped)
            #expect(vm.messages.last?.content == "Once upon a time")
            #expect(vm.canRetry)
            // Late events change nothing.
            server.send(.text(chatID: "c1", messageID: id, delta: " more"))
            #expect(vm.messages.last?.content == "Once upon a time")
            try await Task.sleep(for: .milliseconds(300))
            #expect(server.state.stops == ["c1"])
            let saved = try #require(server.state.saves.last)
            let message = ((saved["chat"] as? [String: Any])?["history"] as? [String: Any])?["messages"] as? [String: Any]
            let reply = try #require(message?[id] as? [String: Any])
            #expect(reply["content"] as? String == "Once upon a time")
            #expect(reply["done"] as? Bool == true)
            #expect(reply["dex_stopped"] as? Bool == true)
            #expect(reply["parentId"] as? String == vm.messages[0].id)
        }

        @Test func replyFinishedBeforeTheServerAnsweredIsStillSaved() async throws {
            let (vm, server, context) = Self.vm()
            server.state.duringReply = {
                let id = vm.messages.last?.id ?? ""
                server.send(.finished(chatID: "c1", messageID: id, output: [.message(id: "m", text: "Quick")], usage: nil))
            }
            await Self.send("Hi", vm)
            #expect(vm.messages.last?.status == .done)
            let chat = try #require(try Self.chats(context).first)
            #expect(chat.sortedMessages.map(\.content) == ["Hi", "Quick"])
            #expect(chat.sortedMessages.map(\.status) == ["done", "done"])
        }

        @Test func stoppedWhileStartingStopsTheJobOnceNamed() async throws {
            let (vm, server, context) = Self.vm()
            server.state.duringReply = { vm.stop() }
            server.state.setChat("c1", FakeServer.chatJSON(id: "c1", messages: [("u", "user", "Hi", nil), ("a", "assistant", "", false)]))
            await Self.send("Hi", vm)
            #expect(vm.messages.last?.status == .stopped)
            try await Task.sleep(for: .milliseconds(300))
            #expect(server.state.stops == ["c1"])
            #expect(try Self.chats(context).first?.sortedMessages.last?.status == "stopped")
        }

        @Test func channelDroppedWhileStartingIsFollowed() async throws {
            let (vm, server, _) = Self.vm()
            server.state.duringReply = { server.send(.disconnected) }
            vm.send("Hi", model: Self.model)
            let id = try #require(vm.messages.last?.id)
            server.state.setChat("c1", FakeServer.chatJSON(id: "c1", messages: [
                (vm.messages[0].id, "user", "Hi", nil), (id, "assistant", "Read back", true),
            ]))
            await vm.waitForReply()
            try await Task.sleep(for: .milliseconds(100))
            await vm.waitForReply()
            #expect(vm.messages.last?.status == .done)
            #expect(vm.messages.last?.content == "Read back")
        }

        @Test func messagesTheServerNeverTookAreNoParent() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("First", vm)
            try Self.answer("One", vm, server)
            let firstReply = try #require(vm.messages.last?.id)
            server.state.replyStatus = 500
            await Self.send("Lost", vm)
            #expect(vm.messages.last?.status == .failed)
            #expect(vm.chat?.sortedMessages.count == 2)
            server.state.replyStatus = 200
            await Self.send("Next", vm)
            // Attached after the last message the server has, not the lost ones.
            #expect(server.lastReply?["parent_id"] as? String == firstReply)
            #expect(vm.messages.map(\.content).prefix(4) == ["First", "One", "Lost", ""])
        }

        @Test func nothingCanBeSentWhileAReplyStarts() async throws {
            let (vm, server, _) = Self.vm()
            server.state.duringReply = {
                vm.stop()
                #expect(vm.isStreaming)
                vm.send("Again", model: Self.model)
            }
            await Self.send("Hi", vm)
            #expect(server.state.replies.count == 1)
            #expect(!vm.isStreaming)
            #expect(vm.messages.map(\.content) == ["Hi", ""])
        }

        @Test func newChatKeepsTheFolderItWasSentFrom() async throws {
            let (vm, server, context) = Self.vm()
            let lab = Folder(name: "Lab")
            let trip = Folder(name: "Trip")
            context.insert(lab)
            context.insert(trip)
            vm.reset(into: lab)
            // Another folder's New Session opens before the server answers.
            server.state.duringReply = { vm.reset(into: trip) }
            vm.send("Hi", model: Self.model)
            await vm.waitForReply()
            let chat = try #require(try Self.chats(context).first)
            #expect(chat.folder === lab)
            #expect(vm.newChatFolder === trip)
            // In the folder on the server too.
            #expect(server.state.folderOps == ["move c1 \(lab.id)"])
        }

        @Test func pinFollowsWhatWasAsked() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("Hi", vm)
            try Self.answer("Hello", vm, server)
            let chat = try #require(vm.chat)
            func pins() -> Int { StubProtocol.requests.filter { $0.url?.path == "/api/v1/chats/c1/pin" }.count }
            // The pretend server always answers "not pinned": pinning flips again.
            vm.togglePin(chat)
            try await Task.sleep(for: .milliseconds(200))
            #expect(pins() == 2)
            vm.togglePin(chat)
            try await Task.sleep(for: .milliseconds(200))
            #expect(pins() == 3)
        }

        @Test func deletingAFolderDeletesItOnTheServer() async throws {
            let (vm, server, context) = Self.vm()
            let lab = Folder(name: "Lab")
            context.insert(lab)
            vm.reset(into: lab)
            await Self.send("Hi", vm)
            try Self.answer("Hello", vm, server)
            vm.delete(lab)
            try await Task.sleep(for: .milliseconds(200))
            // One request: the server deletes the folder's chats with it.
            #expect(server.state.folderOps.last == "delete \(lab.id)")
        }

        @Test func renamePinAndDeleteReachTheServer() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("Hi", vm)
            try Self.answer("Hello", vm, server)
            let chat = try #require(vm.chat)
            vm.rename(chat, to: "Trip")
            vm.togglePin(chat)
            try await Task.sleep(for: .milliseconds(200))
            vm.delete(chat)
            try await Task.sleep(for: .milliseconds(200))
            let sent = StubProtocol.requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }
            #expect(sent.contains("POST /api/v1/chats/c1"))
            #expect(sent.contains("POST /api/v1/chats/c1/pin"))
            #expect(sent.contains("DELETE /api/v1/chats/c1"))
            #expect(server.state.saves.contains { ($0["chat"] as? [String: Any])?["title"] as? String == "Trip" })
        }

        @Test func replyStoppedInTheWebUIStopsHere() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("Hi", vm)
            let id = try #require(vm.messages.last?.id)
            server.send(.text(chatID: "c1", messageID: id, delta: "Hel"))
            server.send(.cancelled(chatID: "c1", messageID: id))
            #expect(vm.messages.last?.status == .stopped)
            #expect(vm.messages.last?.content == "Hel")
            #expect(vm.canRetry)
            // Not stopped again from here.
            try await Task.sleep(for: .milliseconds(100))
            #expect(server.state.stops.isEmpty)
        }

        @Test func droppedChannelReadsTheReplyFromTheServer() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("Hi", vm)
            let id = try #require(vm.messages.last?.id)
            server.state.setTasks("c1", ["t1"])
            server.state.setChat("c1", FakeServer.chatJSON(id: "c1", messages: [
                (vm.messages[0].id, "user", "Hi", nil), (id, "assistant", "Hel", false),
            ]))
            server.send(.disconnected)
            try await Task.sleep(for: .milliseconds(100))
            #expect(vm.messages.last?.content == "Hel")
            #expect(vm.isStreaming)
            server.state.setChat("c1", FakeServer.chatJSON(id: "c1", messages: [
                (vm.messages[0].id, "user", "Hi", nil), (id, "assistant", "Hello", true),
            ]))
            await vm.waitForReply()
            #expect(vm.messages.last?.status == .done)
            #expect(vm.messages.last?.content == "Hello")
            #expect(vm.chat?.sortedMessages.last?.content == "Hello")
        }

        @Test func replyWithNoJobLeftIsCutOff() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("Hi", vm)
            let id = try #require(vm.messages.last?.id)
            server.state.setChat("c1", FakeServer.chatJSON(id: "c1", messages: [
                (vm.messages[0].id, "user", "Hi", nil), (id, "assistant", "", false),
            ]))
            server.send(.disconnected)
            await vm.waitForReply()
            #expect(vm.messages.last?.status == .stopped)
            #expect(vm.canRetry)
        }

        @Test func reopenedChatStillReplyingIsFollowed() async throws {
            let (vm, server, context) = Self.vm()
            // A chat stored mid-reply by an earlier launch.
            let chat = Chat(id: "c7", title: "Old")
            context.insert(chat)
            for (index, (id, role, status)) in [("u", "user", "done"), ("a", "assistant", "streaming")].enumerated() {
                let message = Message(id: id)
                context.insert(message)
                message.chat = chat
                message.role = role
                message.status = status
                message.sequence = index
            }
            try context.save()
            server.state.setChat("c7", FakeServer.chatJSON(id: "c7", title: "Old", messages: [
                ("u", "user", "Q", nil), ("a", "assistant", "Finished meanwhile", true),
            ]))
            vm.open(chat)
            await vm.waitForReply()
            try await Task.sleep(for: .milliseconds(100))
            #expect(vm.messages.last?.status == .done)
            #expect(vm.messages.last?.content == "Finished meanwhile")
            #expect(server.readChats.contains("c7"))
        }

        @Test func openingTakesTheServersCopy() async throws {
            let (vm, server, context) = Self.vm()
            let chat = Chat(id: "c8", title: "Mine")
            context.insert(chat)
            try context.save()
            server.state.setChat("c8", FakeServer.chatJSON(id: "c8", title: "Named There", messages: [
                ("u1", "user", "From the web", nil), ("a1", "assistant", "Answered there", true),
            ]))
            vm.open(chat)
            try await Task.sleep(for: .milliseconds(200))
            #expect(vm.messages.map(\.content) == ["From the web", "Answered there"])
            #expect(chat.title == "Named There")
            #expect(chat.messagesSyncedAt != nil)
            // Opened, what came in is read.
            #expect(!chat.isUnread)
            #expect(server.readChats.contains("c8"))
            #expect(try context.fetch(FetchDescriptor<Message>()).count == 2)
        }

        @Test func openingTakesARenameMadeElsewhere() async throws {
            let (vm, server, context) = Self.vm()
            let chat = Chat(id: "c8", title: "Old Name")
            context.insert(chat)
            // Messages already current: a rename doesn't touch them or the date.
            chat.messagesSyncedAt = Date(timeIntervalSince1970: 2_000_000_000)
            try context.save()
            server.state.setChat("c8", FakeServer.chatJSON(id: "c8", title: "Renamed On Web", updatedAt: 2_000_000_000,
                                                           messages: [("u1", "user", "Hi", nil)]))
            vm.open(chat)
            try await Task.sleep(for: .milliseconds(200))
            #expect(chat.title == "Renamed On Web")
            #expect(chat.messages.isEmpty)
        }

        @Test func serverTitleNamesTheChatUnlessRenamed() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("hi there", vm)
            try Self.answer("Hello", vm, server)
            server.send(.title(chatID: "c1", title: "friendly greeting exchange"))
            #expect(vm.chat?.title == "Friendly Greeting Exchange")
            vm.rename(try #require(vm.chat), to: "Mine")
            server.send(.title(chatID: "c1", title: "Another"))
            #expect(vm.chat?.title == "Mine")
        }

        @Test func incognitoUsesATemporaryChatAndSavesNothing() async throws {
            let (vm, server, context) = Self.vm()
            vm.isIncognito = true
            await Self.send("Secret", vm)
            let body = try #require(server.lastReply)
            #expect(body["chat_id"] as? String == "local:sid")
            #expect(body["background_tasks"] == nil)
            try Self.answer("Shh", vm, server)
            await Self.send("More", vm)
            // Never saved, so it brings its whole history every time.
            #expect(server.lastReply?["messages"] as? [[String: String]] == [
                ["role": "user", "content": "Secret"], ["role": "assistant", "content": "Shh"], ["role": "user", "content": "More"],
            ])
            #expect(try Self.chats(context).isEmpty)
            #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
            #expect(vm.chat == nil)
        }

        @Test func leavingIncognitoMidReplyStopsIt() async throws {
            let (vm, server, _) = Self.vm()
            vm.isIncognito = true
            await Self.send("Secret", vm)
            vm.reset()
            #expect(vm.messages.isEmpty)
            #expect(!vm.isIncognito)
            try await Task.sleep(for: .milliseconds(200))
            #expect(server.state.stops == ["local:sid"])
        }

        @Test func leavingMidReplyLetsItFinish() async throws {
            let (vm, server, _) = Self.vm()
            await Self.send("Hi", vm)
            let chat = try #require(vm.chat)
            let id = try #require(vm.messages.last?.id)
            vm.reset()
            #expect(vm.streamingChatIDs == ["c1"])
            server.send(.finished(chatID: "c1", messageID: id, output: [.message(id: "m", text: "Hello")], usage: nil))
            #expect(vm.streamingChatIDs.isEmpty)
            #expect(chat.sortedMessages.last?.content == "Hello")
            vm.open(chat)
            #expect(vm.messages.map(\.content) == ["Hi", "Hello"])
        }

        @Test func refusedReplyFailsAndNewChatIsNotSaved() async throws {
            let (vm, server, context) = Self.vm()
            server.state.replyStatus = 400
            await Self.send("Hi", vm)
            #expect(vm.messages.last?.status == .failed)
            #expect(vm.messages.last?.error == "The server has no model named gemma4:12b. Pick another below.")
            #expect(try Self.chats(context).isEmpty)
            // Retried once the server takes it: a new chat after all.
            server.state.replyStatus = 200
            vm.retry(model: Self.model)
            await vm.waitForReply()
            #expect(try Self.chats(context).map(\.id) == ["c1"])
            #expect(server.lastReply?["chat_id"] == nil)
        }

        @Test func noLiveChannelFails() async throws {
            let (vm, server, _) = Self.vm()
            server.connectError = WebUISocket.Failure.refused("Sign in again")
            await Self.send("Hi", vm)
            #expect(vm.messages.last?.status == .failed)
            #expect(vm.messages.last?.error == "Couldn't open the live connection: Sign in again")
        }

        @Test func noServerOrModelFailsWithoutARequest() async {
            let vm = ChatVM()
            vm.send("Hi", model: Self.model)
            #expect(vm.messages.last?.error == "No server is set. Add one in Settings.")
            let (other, server, _) = Self.vm()
            other.send("Hi", model: nil)
            #expect(other.messages.last?.error == "No model is picked. Pick one below.")
            #expect(server.state.replies.isEmpty)
        }

        @Test func blankMessagesAreNotSent() {
            let vm = ChatVM()
            vm.send("  \n ", model: Self.model)
            #expect(vm.messages.isEmpty)
        }

        @Test func historyKeepsUserMessagesAndRepliesWithText() {
            let messages = [
                ChatMessage(role: .user, content: "A", sequence: 0),
                ChatMessage(role: .assistant, content: "", sequence: 1, status: .failed),
                ChatMessage(role: .assistant, content: "B", sequence: 2),
                ChatMessage(id: "q", role: .user, content: "C", sequence: 3),
                ChatMessage(role: .assistant, content: "D", sequence: 4),
            ]
            #expect(ChatVM.history(messages, upTo: "q") == [
                ["role": "user", "content": "A"], ["role": "assistant", "content": "B"], ["role": "user", "content": "C"],
            ])
        }

        @Test(arguments: [
            (URLError(.timedOut) as Error, "The server took too long to answer. Try again in a minute."),
            (URLError(.notConnectedToInternet) as Error, "Couldn't reach the server. Check the address in Settings and that the server is on."),
            (WebUIClient.Failure.http(status: 530, message: "") as Error, "Couldn't reach the server (530). Check that it is on and Open WebUI is running."),
            (WebUIAuth.Failure.noPassword as Error, "Sign in to the server in Settings."),
            (WebUIAuth.Failure.signIn("Wrong password") as Error, "The server turned down the sign-in: Wrong password. Check Settings."),
        ])
        func errorsReadPlainly(_ error: Error, _ expected: String) {
            #expect(ChatVM.describe(error, model: "gemma4:12b") == expected)
        }

        @Test func contextNeverShrinksWhenTheServerCountsOnlyUncachedTokens() {
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
        // The turn's top padding and the gap: 16 + 8.
        #expect(TranscriptLayout.room(viewport: 600, turn: 100, padding: 24) == 476)
        #expect(TranscriptLayout.room(viewport: 600, turn: 576, padding: 24) == 0)
        #expect(TranscriptLayout.room(viewport: 600, turn: 900, padding: 24) == 0)
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
