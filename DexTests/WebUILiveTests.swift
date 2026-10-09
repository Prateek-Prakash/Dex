//
//  WebUILiveTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation
import SwiftData
import Testing
@testable import Dex

/// Against the real server, signing in as Dex does. Off unless asked for:
/// `Tools/live-tests.sh` reads the account from the Mac's Keychain and runs
/// these with it.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DEX_LIVE"] == "1"))
struct WebUILiveTests {
    static let environment = ProcessInfo.processInfo.environment
    static let base = URL(string: environment["DEX_LIVE_SERVER"] ?? "https://webui.teek.dev")!
    let passwordAccount = "tests.webui.live.password"
    let tokenAccount = "tests.webui.live.token"

    /// An auth for the account the script passed, with no token yet: the
    /// first request signs in.
    func auth() throws -> WebUIAuth {
        let email = try #require(Self.environment["DEX_LIVE_EMAIL"], "Run through Tools/live-tests.sh")
        let password = try #require(Self.environment["DEX_LIVE_PASSWORD"], "Run through Tools/live-tests.sh")
        KeychainService.save(password, for: passwordAccount)
        KeychainService.save("", for: tokenAccount)
        return WebUIAuth(baseURL: Self.base, email: email, passwordAccount: passwordAccount, tokenAccount: tokenAccount)
    }

    @Test(.timeLimit(.minutes(2)))
    func replyStreamsOverSocketAndIsSaved() async throws {
        defer {
            KeychainService.save("", for: tokenAccount)
            KeychainService.save("", for: passwordAccount)
        }
        let auth = try auth()
        let client = WebUIClient(baseURL: Self.base, auth: auth)
        let socket = WebUISocket(baseURL: Self.base, auth: auth)
        let (sid, events) = try await socket.connect()

        // The server's default model, so the test runs on one that is warm.
        let model = try #require(try await client.defaultModels().first, "Set a default model on the server")
        let (question, reply) = (UUID().uuidString.lowercased(), UUID().uuidString.lowercased())
        let text = "Reply with exactly: live check ok"
        let chatID = try await client.startReply(WebUIReplyRequest(
            model: model, sessionID: sid, id: reply, chatID: nil, parentID: nil,
            userMessage: .init(id: question, parentId: nil, childrenIds: [reply], content: text,
                               timestamp: Int(Date().timeIntervalSince1970), models: [model]),
            messages: [["role": "user", "content": text]], backgroundTasks: .init()))

        // Whatever happens next (a failed check, the time limit) the chat
        // goes. A detached task, so a timed-out test can't cancel it.
        do {
            try await checkReply(chatID: chatID, question: question, reply: reply, events: events, client: client, socket: socket)
        } catch {
            await Self.remove(chatID: chatID, client: client)
            await socket.disconnect()
            throw error
        }
        await Self.remove(chatID: chatID, client: client)
        await #expect(throws: WebUIClient.Failure.notFound) { try await client.chat(id: chatID) }
        await socket.disconnect()
    }

    private func checkReply(chatID: String, question: String, reply: String, events: AsyncStream<WebUIEvent>,
                            client: WebUIClient, socket: WebUISocket) async throws {
        var streamed = ""
        var finished: [WebUIOutputItem]?
        for await event in events {
            switch event {
            case .text(chatID, reply, let delta): streamed += delta
            case .finished(chatID, reply, let output, _): finished = output
            case .failed(_, _, let message): Issue.record("reply failed: \(message)")
            default: break
            }
            if finished != nil { break }
        }
        await socket.markRead(chatID: chatID)

        let output = try #require(finished)
        let final = output.compactMap { if case .message(_, let text) = $0 { text } else { nil } }.joined()
        // The saved text is trimmed; the stream isn't.
        #expect(!streamed.isEmpty)
        #expect(streamed.trimmingCharacters(in: .whitespacesAndNewlines) == final)
        let saved = try await client.chat(id: chatID)
        #expect(saved.chat.history.currentBranch.map(\.id) == [question, reply])
        #expect(saved.chat.history.messages[reply]?.done == true)
        // The job list can outlast the reply (title and tags run after it),
        // so `done` is what says a reply finished; the list only answers.
        _ = try await client.tasks(chat: chatID)
    }

    /// Stops the chat's reply if it still runs, then deletes the chat.
    private static func remove(chatID: String, client: WebUIClient) async {
        await Task.detached {
            try? await client.stopReply(chat: chatID)
            do {
                try await client.delete(chat: chatID)
            } catch {
                Issue.record("live chat \(chatID) left on the server: \(error)")
            }
        }.value
    }

    /// The whole path: `ChatVM` sends through the real server and socket,
    /// the reply streams in, is saved, and the chat goes again after.
    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func chatVMRepliesThroughTheServer() async throws {
        defer {
            KeychainService.save("", for: tokenAccount)
            KeychainService.save("", for: passwordAccount)
        }
        let auth = try auth()
        let client = WebUIClient(baseURL: Self.base, auth: auth)
        let server = WebUIServer(client: client, socket: WebUISocket(baseURL: Self.base, auth: auth))
        let model = try #require(try await client.defaultModels().first, "Set a default model on the server")
        let context = ModelContext(Storage.inMemory())
        let vm = ChatVM()
        vm.context = context
        vm.server = server
        vm.send("Reply with exactly: dex live ok", model: model, webSearch: false)
        await vm.waitForReply()
        let chatID = try #require(vm.chat?.id)
        do {
            for _ in 0..<240 where vm.isStreaming {
                try await Task.sleep(for: .milliseconds(250))
            }
            #expect(vm.messages.last?.status == .done)
            #expect(vm.messages.last?.content.localizedCaseInsensitiveContains("dex live ok") == true)
            #expect(vm.chat?.sortedMessages.last?.status == "done")
            // The model runs with the window every reply asks for.
            struct Loaded: Decodable {
                struct Model: Decodable {
                    let name: String
                    let contextLength: Int?
                    enum CodingKeys: String, CodingKey { case name; case contextLength = "context_length" }
                }
                let models: [Model]
            }
            var request = URLRequest(url: Self.base.appending(path: "ollama/api/ps"))
            request.setValue("Bearer \(try await auth.validToken())", forHTTPHeaderField: "Authorization")
            let loaded = try JSONDecoder().decode(Loaded.self, from: try await URLSession.shared.data(for: request).0)
            #expect(loaded.models.first { $0.name == model }?.contextLength == WebUIReplyRequest.contextLength)
        } catch {
            await Self.remove(chatID: chatID, client: client)
            throw error
        }
        await Self.remove(chatID: chatID, client: client)
        server.disconnect()
    }

    /// The drawer's refresh reads the real server's lists into a throwaway
    /// store; nothing is written to the server.
    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func listRefreshReadsTheRealServer() async throws {
        defer {
            KeychainService.save("", for: tokenAccount)
            KeychainService.save("", for: passwordAccount)
        }
        let auth = try auth()
        let client = WebUIClient(baseURL: Self.base, auth: auth)
        let server = WebUIServer(client: client, socket: WebUISocket(baseURL: Self.base, auth: auth))
        let snapshot = try await ServerSnapshot.fetch(client)
        let context = ModelContext(Storage.inMemory())
        let vm = ChatVM()
        vm.context = context
        vm.server = server
        await vm.refreshList()
        let chats = try context.fetch(FetchDescriptor<Chat>())
        #expect(Set(chats.map(\.id)) == Set(snapshot.chats.filter { $0.archived != true }.map(\.id)))
        #expect(try context.fetch(FetchDescriptor<Folder>()).count == snapshot.folders.count)
        server.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func staleTokenIsRenewedBySigningInAgain() async throws {
        defer {
            KeychainService.save("", for: tokenAccount)
            KeychainService.save("", for: passwordAccount)
        }
        _ = try auth()
        let email = try #require(Self.environment["DEX_LIVE_EMAIL"])
        // A cached token the server turns away, as after it was revoked.
        let token = WebUIAuth.Token(value: "not-a-token", expiresAt: nil, owner: Self.base.absoluteString + "|" + email)
        KeychainService.save(String(decoding: try JSONEncoder().encode(token), as: UTF8.self), for: tokenAccount)
        let auth = WebUIAuth(baseURL: Self.base, email: email, passwordAccount: passwordAccount, tokenAccount: tokenAccount)
        let socket = WebUISocket(baseURL: Self.base, auth: auth)
        let (sid, _) = try await socket.connect()
        #expect(!sid.isEmpty)
        #expect(try await auth.validToken() != "not-a-token")
        await socket.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func wrongPasswordSaysWhy() async throws {
        let email = try #require(Self.environment["DEX_LIVE_EMAIL"])
        KeychainService.save("definitely-not-the-password", for: passwordAccount)
        KeychainService.save("", for: tokenAccount)
        defer { KeychainService.save("", for: passwordAccount) }
        let auth = WebUIAuth(baseURL: Self.base, email: email, passwordAccount: passwordAccount, tokenAccount: tokenAccount)
        await #expect(throws: WebUIAuth.Failure.self) { try await auth.validToken() }
    }
}
