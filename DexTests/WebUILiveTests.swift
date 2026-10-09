//
//  WebUILiveTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation
import Testing
@testable import Dex

/// Against the real server, with the login token in `~/.webui-jwt`. Off
/// unless asked for: `TEST_RUNNER_DEX_LIVE=1 xcodebuild test …`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DEX_LIVE"] == "1"))
struct WebUILiveTests {
    static let base = URL(string: "https://webui.teek.dev")!
    static let tokenFile = "/Users/Prateek/.webui-jwt"
    let tokenAccount = "tests.webui.live.token"

    /// An auth that uses the token from disk and never signs in.
    func auth() throws -> WebUIAuth {
        let jwt = try String(contentsOfFile: Self.tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let email = "live@tests"
        let token = WebUIAuth.Token(value: jwt, expiresAt: nil, owner: Self.base.absoluteString + "|" + email)
        KeychainService.save(String(decoding: try JSONEncoder().encode(token), as: UTF8.self), for: tokenAccount)
        return WebUIAuth(baseURL: Self.base, email: email, passwordAccount: "tests.webui.live.none", tokenAccount: tokenAccount)
    }

    @Test(.timeLimit(.minutes(2)))
    func replyStreamsOverSocketAndIsSaved() async throws {
        defer { KeychainService.save("", for: tokenAccount) }
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

    @Test(.timeLimit(.minutes(1)))
    func staleTokenIsTurnedAwayBySocket() async throws {
        let email = "live@tests"
        let token = WebUIAuth.Token(value: "not-a-token", expiresAt: nil, owner: Self.base.absoluteString + "|" + email)
        KeychainService.save(String(decoding: try JSONEncoder().encode(token), as: UTF8.self), for: tokenAccount)
        defer { KeychainService.save("", for: tokenAccount) }
        let auth = WebUIAuth(baseURL: Self.base, email: email, passwordAccount: "tests.webui.live.none", tokenAccount: tokenAccount)
        // Turned away, it renews; with no password that fails as no password.
        await #expect(throws: WebUIAuth.Failure.noPassword) { try await WebUISocket(baseURL: Self.base, auth: auth).connect() }
    }
}
