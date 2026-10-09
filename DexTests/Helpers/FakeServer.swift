//
//  FakeServer.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation
import Testing
@testable import Dex

/// A pretend Open WebUI for `ChatVM`: its REST answers come from `state`
/// through `StubProtocol`, and its live channel is whatever a test sends.
@MainActor
final class FakeServer: ReplyServer {
    /// What the pretend server holds and was asked. Read by the stub on
    /// URLSession's queue, so behind a lock.
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _replies: [[String: Any]] = []
        private var _chats: [String: String] = [:]
        private var _tasks: [String: [String]] = [:]
        private var _stops: [String] = []
        private var _saves: [[String: Any]] = []
        private var nextChat = 0
        private var nextFolder = 0
        private var _list = "[]"
        private var _pinned = "[]"
        private var _folders = "[]"
        private var _folderChats: [String: String] = [:]
        private var _folderOps: [String] = []
        private var _listFetches = 0
        private var _missingChats: Set<String> = []
        /// The status a reply request gets; anything but 200 refuses it.
        var replyStatus = 200
        /// Runs on the main actor while a reply request is out, before it's
        /// answered: for what happens meanwhile.
        var duringReply: (@MainActor () -> Void)?
        /// Folder creation fails, as for a name the server already has.
        var refusesFolders = false
        /// The same, while the chat list is being fetched.
        var duringList: (@MainActor () -> Void)?

        func locked<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }

        /// Every reply request's body, in order.
        var replies: [[String: Any]] { locked { _replies } }
        var stops: [String] { locked { _stops } }
        var saves: [[String: Any]] { locked { _saves } }

        /// The chat list, pinned list and folder list, as JSON arrays.
        func setList(_ json: String) { locked { _list = json } }
        func setPinned(_ json: String) { locked { _pinned = json } }
        func setFolders(_ json: String) { locked { _folders = json } }
        /// A folder's chats, as a JSON array (all on page 1).
        func setFolderChats(_ id: String, _ json: String) { locked { _folderChats[id] = json } }
        /// Folder requests made, e.g. "create Lab", "update f1 {…}", "delete f1".
        var folderOps: [String] { locked { _folderOps } }
        var listFetches: Int { locked { _listFetches } }
        /// Chats the server says it can't find when moved.
        func setMissing(_ ids: Set<String>) { locked { _missingChats = ids } }

        /// What `GET /api/v1/chats/{id}` answers; nil is "not found".
        func setChat(_ id: String, _ json: String?) { locked { _chats[id] = json } }
        func setTasks(_ id: String, _ tasks: [String]) { locked { _tasks[id] = tasks } }

        func answer(_ request: URLRequest) -> StubProtocol.Reply {
            let path = request.url?.path ?? ""
            let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            return locked {
                switch (request.httpMethod ?? "GET", path) {
                case ("POST", "/api/v1/auths/signin"):
                    return .init(body: #"{"token":"jwt","expires_at":null}"#)
                case ("POST", "/api/chat/completions"):
                    _replies.append(body)
                    if let duringReply {
                        // The main actor is waiting on this request, so free to run it.
                        lock.unlock()
                        DispatchQueue.main.sync { MainActor.assumeIsolated { duringReply() } }
                        lock.lock()
                    }
                    guard replyStatus == 200 else {
                        return .init(status: replyStatus, body: #"{"detail":"Model not found"}"#)
                    }
                    let chatID = (body["chat_id"] as? String) ?? {
                        nextChat += 1
                        return "c\(nextChat)"
                    }()
                    return .init(body: #"{"status":true,"task_ids":["t1"],"chat_id":"\#(chatID)"}"#)
                case ("GET", let path) where path.hasPrefix("/api/tasks/chat/"):
                    let id = String(path.dropFirst("/api/tasks/chat/".count))
                    let tasks = (_tasks[id] ?? []).map { #""\#($0)""# }.joined(separator: ",")
                    return .init(body: #"{"task_ids":[\#(tasks)]}"#)
                case ("POST", let path) where path.hasPrefix("/api/tasks/chat/") && path.hasSuffix("/stop"):
                    _stops.append(String(path.dropFirst("/api/tasks/chat/".count).dropLast("/stop".count)))
                    return .init(body: #"{"status":true}"#)
                case ("GET", "/api/v1/chats/list"):
                    _listFetches += 1
                    if let duringList {
                        lock.unlock()
                        DispatchQueue.main.sync { MainActor.assumeIsolated { duringList() } }
                        lock.lock()
                    }
                    return .init(body: _list)
                case ("GET", "/api/v1/chats/pinned"):
                    return .init(body: _pinned)
                case ("GET", let path) where path.hasPrefix("/api/v1/chats/folder/"):
                    let id = path.dropFirst("/api/v1/chats/folder/".count).split(separator: "/").first.map(String.init) ?? ""
                    let page = request.url?.query ?? ""
                    return .init(body: page == "page=1" ? (_folderChats[id] ?? "[]") : "[]")
                case ("GET", "/api/v1/folders/"), ("GET", "/api/v1/folders"):
                    return .init(body: _folders)
                case ("POST", "/api/v1/folders/"), ("POST", "/api/v1/folders"):
                    if refusesFolders { return .init(status: 400, body: #"{"detail":"Folder already exists"}"#) }
                    nextFolder += 1
                    let name = body["name"] as? String ?? ""
                    _folderOps.append("create \(name)")
                    return .init(body: #"{"id":"f\#(nextFolder)","name":"\#(name)","parent_id":null,"created_at":1,"updated_at":1}"#)
                case ("POST", let path) where path.hasPrefix("/api/v1/folders/") && path.hasSuffix("/update"):
                    let id = path.dropFirst("/api/v1/folders/".count).dropLast("/update".count)
                    let data = (try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys)) ?? Data()
                    _folderOps.append("update \(id) \(String(decoding: data, as: UTF8.self))")
                    return .init(body: "{}")
                case ("DELETE", let path) where path.hasPrefix("/api/v1/folders/"):
                    _folderOps.append("delete \(path.dropFirst("/api/v1/folders/".count))")
                    return .init(body: "true")
                case ("POST", let path) where path.hasPrefix("/api/v1/chats/") && path.hasSuffix("/folder"):
                    let id = path.dropFirst("/api/v1/chats/".count).dropLast("/folder".count)
                    if _chats[String(id)] == nil, _missingChats.contains(String(id)) {
                        return .init(status: 401, body: #"{"detail":"We could not find what you're looking for :/"}"#)
                    }
                    _folderOps.append("move \(id) \((body["folder_id"] as? String) ?? "none")")
                    return .init(body: "{}")
                case ("GET", let path) where path.hasPrefix("/api/v1/chats/"):
                    guard let chat = _chats[String(path.dropFirst("/api/v1/chats/".count))] else {
                        return .init(status: 401, body: #"{"detail":"We could not find what you're looking for :/"}"#)
                    }
                    return .init(body: chat)
                case ("POST", let path) where path.hasPrefix("/api/v1/chats/"):
                    _saves.append(body)
                    return .init(body: "{}")
                default:
                    return .init(status: 404, body: #"{"detail":"Not Found"}"#)
                }
            }
        }
    }

    let client: WebUIClient
    let state = State()
    var onEvent: (WebUIEvent) -> Void = { _ in }
    /// Thrown instead of connecting, when set.
    var connectError: Error?
    private(set) var readChats: [String] = []

    static let passwordAccount = "tests.fake.password"
    static let tokenAccount = "tests.fake.token"

    init() {
        KeychainService.save("secret", for: Self.passwordAccount)
        KeychainService.save("", for: Self.tokenAccount)
        let state = state
        let session = StubProtocol.session { state.answer($0) }
        let base = URL(string: "https://webui.example.com")!
        let auth = WebUIAuth(baseURL: base, email: "me@example.com", passwordAccount: Self.passwordAccount,
                             tokenAccount: Self.tokenAccount, session: session)
        client = WebUIClient(baseURL: base, auth: auth, session: session)
    }

    /// How many times the live channel was asked for.
    private(set) var connections = 0

    func sessionID() async throws -> String {
        connections += 1
        if let connectError { throw connectError }
        return "sid"
    }

    func markRead(chatID: String) {
        readChats.append(chatID)
    }

    /// Sends a live event, as the server's channel would.
    func send(_ event: WebUIEvent) {
        onEvent(event)
    }

    /// The last reply request's body.
    var lastReply: [String: Any]? { state.replies.last }

    /// A saved chat's JSON: `messages` in order, each answering the one
    /// before; the last is on show.
    static func chatJSON(id: String, title: String = "New Chat", updatedAt: Int = 2_000_000_000,
                         messages: [(id: String, role: String, content: String, done: Bool?)]) -> String {
        var entries: [String] = []
        for (index, message) in messages.enumerated() {
            let parent = index == 0 ? "null" : #""\#(messages[index - 1].id)""#
            let children = index + 1 < messages.count ? #"["\#(messages[index + 1].id)"]"# : "[]"
            let done = message.done.map { #","done":\#($0)"# } ?? ""
            let content = String(decoding: try! JSONEncoder().encode(message.content), as: UTF8.self)
            entries.append(#""\#(message.id)":{"id":"\#(message.id)","parentId":\#(parent),"childrenIds":\#(children),"role":"\#(message.role)","content":\#(content),"model":"gemma4:12b","timestamp":1\#(done)}"#)
        }
        let current = messages.last.map { #""\#($0.id)""# } ?? "null"
        return #"{"id":"\#(id)","title":"\#(title)","pinned":false,"updated_at":\#(updatedAt),"created_at":1,"chat":{"history":{"currentId":\#(current),"messages":{\#(entries.joined(separator: ","))}}}}"#
    }
}
