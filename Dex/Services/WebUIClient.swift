//
//  WebUIClient.swift
//  Dex
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation

/// A thin `URLSession` client for the parts of the Open WebUI API Dex uses.
/// Every request carries the login token from `auth`; one the server turns
/// down is renewed once and the request sent again.
struct WebUIClient: Sendable {
    let baseURL: URL
    let auth: WebUIAuth
    var session: URLSession = .shared

    enum Failure: LocalizedError, Equatable {
        case http(status: Int, message: String)
        /// The chat or folder is gone, e.g. deleted in the web UI.
        case notFound
        case stream(String)

        var errorDescription: String? {
            switch self {
            case .http(let status, let message): message.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(message)"
            case .notFound: "Not found"
            case .stream(let message): message
            }
        }
    }

    /// The typed address as a server root, or nil when it isn't one.
    /// A bare host gets https; a port is optional.
    static func serverURL(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    /// The server's "not found", which it sends as a 401 after the token checked out.
    static let notFoundDetail = "We could not find what you're looking for :/"

    /// The `detail` an error body carries, if any.
    static func detail(_ data: Data) -> String? {
        struct Body: Decodable { let detail: String }
        return try? JSONDecoder().decode(Body.self, from: data).detail
    }

    // MARK: Server

    /// The server's version; doubles as the connection check.
    func version() async throws -> String {
        struct Response: Decodable { let version: String }
        return try decode(Response.self, from: await send("api/version")).version
    }

    /// Every model, hidden ones included; `isListed` picks Dex's.
    func models() async throws -> [WebUIModel] {
        struct Response: Decodable { let data: [WebUIModel] }
        return try decode(Response.self, from: await send("api/models")).data
            .sorted { $0.id.compare($1.id, options: .numeric) == .orderedAscending }
    }

    /// The server's default models (Admin Panel → Settings → Models), first
    /// choice first; empty when none is set.
    func defaultModels() async throws -> [String] {
        struct Response: Decodable {
            let defaultModels: String?
            enum CodingKeys: String, CodingKey { case defaultModels = "default_models" }
        }
        return (try decode(Response.self, from: await send("api/config")).defaultModels ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Download progress through the server's Ollama proxy, until the pull succeeds.
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        let client = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // A long idle timeout: big models go quiet for minutes while verifying.
                    let bytes = try await client.stream("ollama/api/pull", body: ["model": model], timeout: 600)
                    var lastStatus: String?
                    for try await line in bytes.lines {
                        guard let progress = try? JSONDecoder().decode(OllamaPullProgress.self, from: Data(line.utf8)) else { continue }
                        if let error = progress.error { throw Failure.stream(error) }
                        lastStatus = progress.status
                        continuation.yield(progress)
                    }
                    // A dropped connection ends the stream cleanly too; only
                    // Ollama's closing "success" means the model is installed.
                    guard lastStatus == "success" else { throw Failure.stream("Pull ended before it finished") }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A model's base model, maker and license, through Ollama's `show`.
    func info(model: String) async throws -> WebUIModelInfo {
        try decode(WebUIModelInfo.self, from: await send("ollama/api/show", method: "POST", body: ["model": model], timeout: 30))
    }

    func delete(model: String) async throws {
        _ = try await send("ollama/api/delete", method: "DELETE", body: ["model": model])
    }

    // MARK: Chats

    /// Every chat, newest first, pinned and foldered ones included.
    func chats() async throws -> [WebUIChatSummary] {
        try decode([WebUIChatSummary].self, from: await send("api/v1/chats/list", query: [
            URLQueryItem(name: "include_pinned", value: "true"),
            URLQueryItem(name: "include_folders", value: "true"),
        ]))
    }

    func pinnedChats() async throws -> [WebUIChatSummary] {
        try decode([WebUIChatSummary].self, from: await send("api/v1/chats/pinned"))
    }

    /// A folder's chats, every page of them.
    func chats(inFolder id: String) async throws -> [WebUIChatSummary] {
        var all: [WebUIChatSummary] = []
        for page in 1... {
            let chats = try decode([WebUIChatSummary].self, from: await send("api/v1/chats/folder/\(id)/list", query: [
                URLQueryItem(name: "page", value: String(page)),
            ]))
            guard !chats.isEmpty else { break }
            all += chats
        }
        return all
    }

    func chat(id: String) async throws -> WebUIChat {
        try decode(WebUIChat.self, from: await send("api/v1/chats/\(id)"))
    }

    func rename(chat id: String, to title: String) async throws {
        _ = try await send("api/v1/chats/\(id)", method: "POST", body: ["chat": ["title": title]])
    }

    func delete(chat id: String) async throws {
        _ = try await send("api/v1/chats/\(id)", method: "DELETE")
    }

    /// Flips the pin; returns whether the chat is pinned now.
    func togglePin(chat id: String) async throws -> Bool {
        struct Response: Decodable { let pinned: Bool? }
        return try decode(Response.self, from: await send("api/v1/chats/\(id)/pin", method: "POST")).pinned ?? false
    }

    /// Nil takes the chat out of its folder.
    func move(chat id: String, toFolder folderID: String?) async throws {
        struct Body: Encodable {
            let folderID: String?
            enum CodingKeys: String, CodingKey { case folderID = "folder_id" }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(folderID, forKey: .folderID)
            }
        }
        _ = try await send("api/v1/chats/\(id)/folder", method: "POST", body: Body(folderID: folderID))
    }

    // MARK: Folders

    func folders() async throws -> [WebUIFolder] {
        try decode([WebUIFolder].self, from: await send("api/v1/folders/"))
    }

    func createFolder(named name: String) async throws -> WebUIFolder {
        try decode(WebUIFolder.self, from: await send("api/v1/folders/", method: "POST", body: ["name": name]))
    }

    func rename(folder id: String, to name: String) async throws {
        _ = try await send("api/v1/folders/\(id)/update", method: "POST", body: ["name": name])
    }

    func delete(folder id: String) async throws {
        _ = try await send("api/v1/folders/\(id)", method: "DELETE")
    }

    // MARK: Replies

    /// Starts a reply as a server job; it streams over the socket named by
    /// `sessionID` and is saved into the chat. Returns the chat's id, new
    /// for a new chat.
    func startReply(_ body: WebUIReplyRequest) async throws -> String {
        struct Response: Decodable {
            let status: Bool?
            let chatID: String?
            enum CodingKeys: String, CodingKey {
                case status
                case chatID = "chat_id"
            }
        }
        let response = try decode(Response.self, from: await send("api/chat/completions", method: "POST", body: body, timeout: 60))
        guard response.status == true, let chatID = response.chatID else { throw Failure.stream("The server didn't start the reply") }
        return chatID
    }

    /// The jobs still running in a chat; empty once its reply is done.
    func tasks(chat id: String) async throws -> [String] {
        struct Response: Decodable {
            let taskIDs: [String]
            enum CodingKeys: String, CodingKey { case taskIDs = "task_ids" }
        }
        return try decode(Response.self, from: await send("api/tasks/chat/\(id)")).taskIDs
    }

    /// Stops a chat's reply. The server keeps none of its text: the caller
    /// saves what it streamed with `save(reply:)`.
    func stopReply(chat id: String) async throws {
        _ = try await send("api/tasks/chat/\(id)/stop", method: "POST")
    }

    /// Writes a stopped reply's text into the chat and marks it done, and
    /// stopped (Dex's own field; the web UI ignores it). The server swaps in
    /// a sent message whole, so the stored one is read first and sent back
    /// with only those fields changed.
    func save(reply id: String, chat chatID: String, content: String) async throws {
        let stored = try JSONSerialization.jsonObject(with: await send("api/v1/chats/\(chatID)")) as? [String: Any]
        let chat = stored?["chat"] as? [String: Any]
        let history = chat?["history"] as? [String: Any]
        guard var message = (history?["messages"] as? [String: Any])?[id] as? [String: Any] else { throw Failure.notFound }
        message["content"] = content
        message["done"] = true
        message[WebUIMessage.stoppedKey] = true
        let body = try JSONSerialization.data(withJSONObject: ["chat": ["history": ["messages": [id: message]]]])
        _ = try await send("api/v1/chats/\(chatID)", method: "POST", data: body)
    }

    // MARK: Requests

    private func request(_ path: String, method: String, query: [URLQueryItem], body: Data?,
                         timeout: TimeInterval, token: String) -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        // Some routes need their trailing slash; make sure it survived.
        if path.hasSuffix("/"), !url.absoluteString.hasSuffix("/") { url = URL(string: url.absoluteString + "/") ?? url }
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func send(_ path: String, method: String = "GET", query: [URLQueryItem] = [],
                      body: (any Encodable)? = nil, timeout: TimeInterval = 15) async throws -> Data {
        try await send(path, method: method, query: query, data: body.map { try JSONEncoder().encode($0) }, timeout: timeout)
    }

    private func send(_ path: String, method: String = "GET", query: [URLQueryItem] = [],
                      data body: Data?, timeout: TimeInterval = 15) async throws -> Data {
        var token = try await auth.validToken()
        var (data, status) = try await load(request(path, method: method, query: query, body: body, timeout: timeout, token: token))
        if status == 401, Self.detail(data) != Self.notFoundDetail {
            token = try await auth.renew(rejected: token)
            (data, status) = try await load(request(path, method: method, query: query, body: body, timeout: timeout, token: token))
        }
        guard status == 200 else { throw Self.failure(status: status, data: data) }
        return data
    }

    private func load(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// `send` for a streamed answer: the bytes, once the server accepted it.
    private func stream(_ path: String, body: some Encodable, timeout: TimeInterval) async throws -> URLSession.AsyncBytes {
        let body = try JSONEncoder().encode(body)
        var token = try await auth.validToken()
        for attempt in 0..<2 {
            let (bytes, response) = try await session.bytes(for: request(path, method: "POST", query: [], body: body,
                                                                         timeout: timeout, token: token))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return bytes }
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            if status == 401, attempt == 0, Self.detail(data) != Self.notFoundDetail {
                token = try await auth.renew(rejected: token)
                continue
            }
            throw Self.failure(status: status, data: data)
        }
        throw Failure.http(status: 401, message: "")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    /// The server's own reason; its "not found" (a 401) as `.notFound`.
    private static func failure(status: Int, data: Data) -> Failure {
        if let detail = detail(data) {
            if detail == notFoundDetail { return .notFound }
            return .http(status: status, message: detail)
        }
        if status == 404 { return .notFound }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.hasPrefix("<"), text.count <= 200 else { return .http(status: status, message: "") }
        return .http(status: status, message: text)
    }
}
