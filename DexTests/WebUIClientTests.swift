//
//  WebUIClientTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation
import Testing
@testable import Dex

extension StubbedNetworkTests {
    @Suite(.serialized)
    final class WebUIClientTests {
        static let base = URL(string: "https://webui.example.com")!
        let passwordAccount = "tests.webui.password"
        let tokenAccount = "tests.webui.token"

        init() {
            KeychainService.save("secret", for: passwordAccount)
            KeychainService.save("", for: tokenAccount)
        }

        deinit {
            KeychainService.save("", for: passwordAccount)
            KeychainService.save("", for: tokenAccount)
        }

        /// The sign-ins sent so far.
        var signIns: [URLRequest] { StubProtocol.requests.filter { $0.url?.path == "/api/v1/auths/signin" } }

        func auth(session: URLSession, now: Date = Date(timeIntervalSince1970: 1_000_000), email: String = "me@example.com") -> WebUIAuth {
            WebUIAuth(baseURL: Self.base, email: email, passwordAccount: passwordAccount, tokenAccount: tokenAccount,
                      session: session, now: { now })
        }

        func client(now: Date = Date(timeIntervalSince1970: 1_000_000),
                    _ handler: @escaping (URLRequest) -> StubProtocol.Reply) -> WebUIClient {
            let session = StubProtocol.session(handler)
            return WebUIClient(baseURL: Self.base, auth: auth(session: session, now: now), session: session)
        }

        static func signIn(token: String = "jwt1", expiresAt: Int? = 3_000_000) -> StubProtocol.Reply {
            .init(body: #"{"id":"u","email":"me@example.com","role":"admin","token":"\#(token)","token_type":"Bearer","expires_at":\#(expiresAt.map(String.init) ?? "null")}"#)
        }

        static func body(_ request: URLRequest) -> [String: Any] {
            (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        }

        // MARK: Sign-in

        @Test func signsInOnceAndSendsToken() async throws {
            let client = client { request in
                if request.url?.path == "/api/v1/auths/signin" { return Self.signIn() }
                return .init(body: #"{"version":"0.11.4","deployment_id":""}"#)
            }
            #expect(try await client.version() == "0.11.4")
            #expect(try await client.version() == "0.11.4")
            #expect(signIns.count == 1)
            let signIn = try #require(signIns.first)
            #expect(Self.body(signIn) as? [String: String] == ["email": "me@example.com", "password": "secret"])
            let calls = StubProtocol.requests.filter { $0.url?.path == "/api/version" }
            #expect(calls.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer jwt1", "Bearer jwt1"])
        }

        @Test func cachedTokenOutlivesLaunch() async throws {
            let session = StubProtocol.session { request in
                request.url?.path == "/api/v1/auths/signin" ? Self.signIn() : .init(body: #"{"version":"1"}"#)
            }
            _ = try await WebUIClient(baseURL: Self.base, auth: auth(session: session), session: session).version()
            // A new launch: fresh auth, same Keychain.
            _ = try await WebUIClient(baseURL: Self.base, auth: auth(session: session), session: session).version()
            #expect(signIns.count == 1)
            // Another account doesn't reuse it.
            _ = try await WebUIClient(baseURL: Self.base, auth: auth(session: session, email: "other@example.com"), session: session).version()
            #expect(signIns.count == 2)
        }

        @Test func renewsTokenNearExpiry() async throws {
            // A 30-day token, 12 hours from expiring: inside the one-day margin.
            var now = Date(timeIntervalSince1970: 1_000_000)
            var issued = 0
            let session = StubProtocol.session { _ in
                issued += 1
                return Self.signIn(token: "jwt\(issued)", expiresAt: Int(now.timeIntervalSince1970) + 30 * 86_400)
            }
            let auth = WebUIAuth(baseURL: Self.base, email: "me@example.com", passwordAccount: passwordAccount,
                                 tokenAccount: tokenAccount, session: session, now: { now })
            #expect(try await auth.validToken() == "jwt1")
            now += 28 * 86_400
            #expect(try await auth.validToken() == "jwt1")
            now += 86_400 + 12 * 3600
            #expect(try await auth.validToken() == "jwt2")
            #expect(try await auth.validToken() == "jwt2")
        }

        @Test func shortLivedTokenIsStillReused() async throws {
            // A one-hour token: inside the one-day margin from the start, so
            // it is replaced at a quarter of its life instead.
            var now = Date(timeIntervalSince1970: 1_000_000)
            var issued = 0
            let session = StubProtocol.session { _ in
                issued += 1
                return Self.signIn(token: "jwt\(issued)", expiresAt: Int(now.timeIntervalSince1970) + 3600)
            }
            let auth = WebUIAuth(baseURL: Self.base, email: "me@example.com", passwordAccount: passwordAccount,
                                 tokenAccount: tokenAccount, session: session, now: { now })
            #expect(try await auth.validToken() == "jwt1")
            now += 2000
            #expect(try await auth.validToken() == "jwt1")
            now += 800
            #expect(try await auth.validToken() == "jwt2")
        }

        @Test func tokenWithoutExpiryNeverRenews() async throws {
            let session = StubProtocol.session { _ in Self.signIn(expiresAt: nil) }
            let auth = auth(session: session, now: Date(timeIntervalSince1970: 9_999_999_999))
            _ = try await auth.validToken()
            _ = try await auth.validToken()
            #expect(signIns.count == 1)
        }

        @Test func rejectedTokenIsRenewedOnce() async throws {
            var issued = 0
            let client = client { request in
                if request.url?.path == "/api/v1/auths/signin" {
                    issued += 1
                    return Self.signIn(token: "jwt\(issued)")
                }
                // The first token was revoked on the server.
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt1" {
                    return .init(status: 401, body: #"{"detail":"401 Unauthorized"}"#)
                }
                return .init(body: #"{"version":"1"}"#)
            }
            #expect(try await client.version() == "1")
            #expect(signIns.count == 2)
        }

        @Test func stillRejectedSurfacesError() async throws {
            let client = client { request in
                request.url?.path == "/api/v1/auths/signin" ? Self.signIn() : .init(status: 401, body: #"{"detail":"401 Unauthorized"}"#)
            }
            await #expect(throws: WebUIClient.Failure.http(status: 401, message: "401 Unauthorized")) { try await client.version() }
            #expect(signIns.count == 2)
        }

        @Test func missingChatIsNotFoundWithoutSigningIn() async throws {
            let client = client { request in
                request.url?.path == "/api/v1/auths/signin" ? Self.signIn()
                    : .init(status: 401, body: #"{"detail":"We could not find what you're looking for :/"}"#)
            }
            await #expect(throws: WebUIClient.Failure.notFound) { try await client.chat(id: "gone") }
            #expect(signIns.count == 1)
        }

        @Test func wrongPasswordSaysWhy() async throws {
            let client = client { _ in
                .init(status: 400, body: #"{"detail":"The email or password provided is incorrect."}"#)
            }
            await #expect(throws: WebUIAuth.Failure.signIn("The email or password provided is incorrect.")) { try await client.version() }
        }

        @Test func noPasswordDoesNotCallServer() async throws {
            KeychainService.save("", for: passwordAccount)
            let client = client { _ in Self.signIn() }
            await #expect(throws: WebUIAuth.Failure.noPassword) { try await client.version() }
            #expect(StubProtocol.requests.isEmpty)
        }

        @Test func signOutForgetsToken() async throws {
            let session = StubProtocol.session { _ in Self.signIn() }
            let auth = auth(session: session)
            _ = try await auth.validToken()
            await auth.signOut()
            #expect(KeychainService.load(tokenAccount) == "")
            _ = try await auth.validToken()
            #expect(signIns.count == 2)
        }

        // MARK: Endpoints

        @Test func chatListAsksForEverything() async throws {
            let client = client { request in
                request.url?.path == "/api/v1/auths/signin" ? Self.signIn()
                    : .init(body: #"[{"id":"c1","title":"T","updated_at":2,"created_at":1,"last_read_at":1,"snippet":null,"active":false,"archived":false}]"#)
            }
            let chats = try await client.chats()
            #expect(chats.map(\.id) == ["c1"])
            #expect(chats.first?.isUnread == true)
            let request = try #require(StubProtocol.requests.last)
            #expect(request.url?.path == "/api/v1/chats/list")
            #expect(request.url?.query == "include_pinned=true&include_folders=true")
        }

        @Test func folderChatsReadEveryPage() async throws {
            let client = client { request in
                if request.url?.path == "/api/v1/auths/signin" { return Self.signIn() }
                switch request.url?.query {
                case "page=1": return .init(body: #"[{"id":"a","title":"A","updated_at":1,"created_at":1}]"#)
                case "page=2": return .init(body: #"[{"id":"b","title":"B","updated_at":1,"created_at":1}]"#)
                default: return .init(body: "[]")
                }
            }
            #expect(try await client.chats(inFolder: "f1").map(\.id) == ["a", "b"])
            #expect(StubProtocol.requests.last?.url?.path == "/api/v1/chats/folder/f1/list")
        }

        @Test func foldersKeepTrailingSlash() async throws {
            let client = client { request in
                if request.url?.path == "/api/v1/auths/signin" { return Self.signIn() }
                return .init(body: #"[{"id":"f1","name":"Work","meta":null,"parent_id":null,"is_expanded":false,"unread_count":0,"created_at":1,"updated_at":2}]"#)
            }
            #expect(try await client.folders().map(\.name) == ["Work"])
            #expect(StubProtocol.requests.last?.url?.absoluteString == "https://webui.example.com/api/v1/folders/")
        }

        @Test func chatEditsSendServerShapes() async throws {
            let client = client { request in
                if request.url?.path == "/api/v1/auths/signin" { return Self.signIn() }
                if request.url?.path.hasSuffix("/pin") == true { return .init(body: #"{"id":"c1","pinned":true}"#) }
                return .init(body: "true")
            }
            try await client.rename(chat: "c1", to: "New")
            #expect(Self.body(StubProtocol.requests.last!) as? [String: [String: String]] == ["chat": ["title": "New"]])
            try await client.move(chat: "c1", toFolder: nil)
            let move = StubProtocol.requests.last!
            #expect(move.url?.path == "/api/v1/chats/c1/folder")
            #expect(Self.body(move)["folder_id"] is NSNull)
            #expect(try await client.togglePin(chat: "c1"))
            try await client.delete(chat: "c1")
            #expect(StubProtocol.requests.last?.httpMethod == "DELETE")
        }

        @Test func startReplyReturnsChatID() async throws {
            let client = client { request in
                request.url?.path == "/api/v1/auths/signin" ? Self.signIn()
                    : .init(body: #"{"status":true,"task_ids":["t1"],"chat_id":"c9"}"#)
            }
            let request = WebUIReplyRequest(
                model: "m", sessionID: "sid", id: "a1", chatID: nil, parentID: nil,
                userMessage: .init(id: "u1", parentId: nil, childrenIds: ["a1"], content: "Hi", timestamp: 1, models: ["m"]))
            #expect(try await client.startReply(request) == "c9")
            #expect(StubProtocol.requests.last?.url?.path == "/api/chat/completions")
        }

        @Test func stoppedReplyKeepsItsPlaceInTree() async throws {
            let client = client { request in
                if request.url?.path == "/api/v1/auths/signin" { return Self.signIn() }
                if request.httpMethod == "GET" { return .init(body: WebUIFixtures.chat) }
                return .init(body: "{}")
            }
            try await client.save(reply: "a2", chat: "c1", content: "Partial")
            let post = try #require(StubProtocol.requests.last)
            #expect(post.httpMethod == "POST")
            #expect(post.url?.path == "/api/v1/chats/c1")
            let chat = Self.body(post)["chat"] as? [String: Any]
            let messages = (chat?["history"] as? [String: Any])?["messages"] as? [String: Any]
            #expect(messages?.count == 1)
            let reply = try #require(messages?["a2"] as? [String: Any])
            #expect(reply["content"] as? String == "Partial")
            #expect(reply["done"] as? Bool == true)
            #expect(reply["parentId"] as? String == "u1")
            #expect(reply["model"] as? String == "gemma4:12b")
        }

        @Test(arguments: [
            (#"{"name":"Open WebUI","default_models":"gemma4:12b, qwen3.5:9b"}"#, ["gemma4:12b", "qwen3.5:9b"]),
            (#"{"name":"Open WebUI","default_models":null}"#, []),
            (#"{"name":"Open WebUI","default_models":""}"#, []),
        ])
        func defaultModelsSplitServerSetting(_ body: String, _ expected: [String]) async throws {
            let client = client { request in
                request.url?.path == "/api/v1/auths/signin" ? Self.signIn() : .init(body: body)
            }
            #expect(try await client.defaultModels() == expected)
            #expect(StubProtocol.requests.last?.url?.path == "/api/config")
        }

        @Test func modelsComeSorted() async throws {
            let client = client { request in
                request.url?.path == "/api/v1/auths/signin" ? Self.signIn() : .init(body: WebUIFixtures.models)
            }
            #expect(try await client.models().map(\.id) == ["arena-model", "dolphin3:8b", "gemma4:12b", "qwen3.5:9b"])
        }

        @Test func pullGoesThroughProxy() async throws {
            let client = client { request in
                request.url?.path == "/api/v1/auths/signin" ? Self.signIn()
                    : .init(contentType: "application/x-ndjson", body: #"{"status":"pulling"}"# + "\n" + #"{"status":"success"}"# + "\n")
            }
            var statuses: [String] = []
            for try await progress in client.pull(model: "gemma4:2b") { statuses.append(progress.status ?? "") }
            #expect(statuses == ["pulling", "success"])
            #expect(StubProtocol.requests.last?.url?.path == "/ollama/api/pull")
        }

        @Test func pullThatStopsShortFails() async throws {
            let client = client { request in
                request.url?.path == "/api/v1/auths/signin" ? Self.signIn() : .init(body: #"{"status":"pulling"}"#)
            }
            await #expect(throws: WebUIClient.Failure.stream("Pull ended before it finished")) {
                for try await _ in client.pull(model: "x") {}
            }
        }
    }
}
