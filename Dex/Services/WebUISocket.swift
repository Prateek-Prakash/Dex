//
//  WebUISocket.swift
//  Dex
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation

/// What the server tells Dex live: a running reply, a new title, a chat
/// list that changed.
enum WebUIEvent: Equatable, Sendable {
    /// More of a reply's text.
    case text(chatID: String, messageID: String, delta: String)
    /// More of a reply's thinking.
    case reasoning(chatID: String, messageID: String, itemID: String, delta: String)
    /// A reply step began or finished: a lookup, its result, a thought.
    /// The server sends a finished step more than once.
    case item(chatID: String, messageID: String, item: WebUIOutputItem, isDone: Bool)
    /// The reply is done; `output` is the whole of it.
    case finished(chatID: String, messageID: String, output: [WebUIOutputItem], usage: WebUIUsage?)
    case failed(chatID: String, messageID: String, message: String)
    /// The reply was stopped, from here or another client.
    case cancelled(chatID: String, messageID: String)
    /// The chat was marked read, here or by another client.
    case read(chatID: String, at: Date)
    case title(chatID: String, title: String)
    case tags(chatID: String, tags: [String])
    /// A reply started or stopped running in the chat.
    case active(chatID: String, isActive: Bool)
    case listChanged(chatID: String?)
    /// The connection dropped; connect again to hear more.
    case disconnected

    /// Decodes the body of an `events` message; nil for the kinds Dex ignores.
    static func decode(_ data: Data) -> WebUIEvent? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        let chatID = envelope.chatID ?? ""
        let messageID = envelope.messageID ?? ""
        let inner = envelope.data
        switch inner.type {
        case "response:completion":
            guard let event = inner.data?.decode(ResponseEvent.self) else { return nil }
            switch event.type {
            case "response.output_text.delta":
                return event.delta.map { .text(chatID: chatID, messageID: messageID, delta: $0) }
            case "response.reasoning_text.delta":
                guard let delta = event.delta else { return nil }
                return .reasoning(chatID: chatID, messageID: messageID, itemID: event.itemID ?? "", delta: delta)
            case "response.output_item.added", "response.output_item.done":
                return event.item.map { .item(chatID: chatID, messageID: messageID, item: $0,
                                              isDone: event.type == "response.output_item.done") }
            default:
                return nil
            }
        case "chat:completion":
            guard let completion = inner.data?.decode(Completion.self) else { return nil }
            if let error = completion.error {
                return .failed(chatID: chatID, messageID: messageID, message: error.content ?? "The reply failed")
            }
            guard completion.done == true else { return nil }
            return .finished(chatID: chatID, messageID: messageID, output: completion.output ?? [], usage: completion.usage)
        case "chat:title":
            return inner.data?.decode(String.self).map { .title(chatID: chatID, title: $0) }
        case "chat:tags":
            return inner.data?.decode([String].self).map { .tags(chatID: chatID, tags: $0) }
        case "chat:active":
            return inner.data?.decode(Active.self).map { .active(chatID: chatID, isActive: $0.active) }
        case "chat:list":
            if let read = inner.data?.decode(Read.self), let lastReadAt = read.lastReadAt {
                return .read(chatID: read.chatID ?? chatID, at: Date(timeIntervalSince1970: lastReadAt))
            }
            return .listChanged(chatID: envelope.chatID)
        case "chat:tasks:cancel":
            return .cancelled(chatID: chatID, messageID: messageID)
        case "chat:message:error":
            let error = inner.data?.decode(Completion.self)?.error
            return .failed(chatID: chatID, messageID: messageID, message: error?.content ?? "The reply failed")
        default:
            return nil
        }
    }

    private struct Envelope: Decodable {
        let chatID: String?
        let messageID: String?
        let data: Inner
        enum CodingKeys: String, CodingKey {
            case data
            case chatID = "chat_id"
            case messageID = "message_id"
        }
    }

    private struct Inner: Decodable {
        let type: String
        let data: RawJSON?
    }

    private struct ResponseEvent: Decodable {
        let type: String
        let delta: String?
        let itemID: String?
        let item: WebUIOutputItem?
        enum CodingKeys: String, CodingKey {
            case type, delta, item
            case itemID = "item_id"
        }
    }

    private struct Completion: Decodable {
        struct Failure: Decodable { let content: String? }
        let done: Bool?
        let output: [WebUIOutputItem]?
        let usage: WebUIUsage?
        let error: Failure?
    }

    private struct Active: Decodable { let active: Bool }

    private struct Read: Decodable {
        let chatID: String?
        let lastReadAt: Double?
        enum CodingKeys: String, CodingKey {
            case chatID = "chat_id"
            case lastReadAt = "last_read_at"
        }
    }

    /// Any JSON, kept as bytes until its type is known.
    private struct RawJSON: Decodable {
        let data: Data
        init(from decoder: Decoder) throws {
            data = try JSONEncoder().encode(try JSONValue(from: decoder))
        }
        func decode<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(type, from: data) }
    }
}

/// One Engine.IO / Socket.IO text frame, the parts Dex speaks.
enum SocketPacket: Equatable {
    /// The transport opened.
    case open
    case ping
    /// The Socket.IO session is up, with the id replies are sent to.
    case connected(sid: String)
    case connectError(String)
    case event(name: String, payload: Data)
    case ack(id: Int, payload: Data)
    case disconnect
    case other

    static func parse(_ text: String) -> SocketPacket {
        guard let engine = text.first else { return .other }
        switch engine {
        case "0": return .open
        case "1": return .disconnect
        case "2": return .ping
        case "4": break
        default: return .other
        }
        let body = text.dropFirst()
        guard let kind = body.first else { return .other }
        // A namespace other than "/" would sit here, before a comma; Dex uses none.
        let rest = body.dropFirst()
        switch kind {
        case "0":
            struct Connect: Decodable { let sid: String }
            guard let connect = try? JSONDecoder().decode(Connect.self, from: Data(rest.utf8)) else { return .other }
            return .connected(sid: connect.sid)
        case "1":
            return .disconnect
        case "2":
            // `["name", payload]`
            guard let array = try? JSONSerialization.jsonObject(with: Data(rest.utf8)) as? [Any],
                  let name = array.first as? String else { return .other }
            let payload = array.count > 1 ? (try? JSONSerialization.data(withJSONObject: array[1], options: .fragmentsAllowed)) : nil
            return .event(name: name, payload: payload ?? Data("null".utf8))
        case "3":
            let digits = rest.prefix { $0.isNumber }
            guard let id = Int(digits) else { return .other }
            return .ack(id: id, payload: Data(rest.dropFirst(digits.count).utf8))
        case "4":
            struct Failure: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(Failure.self, from: Data(rest.utf8)))?.message
            return .connectError(message ?? String(rest))
        default:
            return .other
        }
    }

    /// An event to send, with an ack id when an answer is wanted.
    static func event(_ name: String, _ payload: Any, ack: Int? = nil) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [name, payload]) else { return nil }
        return "42" + (ack.map(String.init) ?? "") + String(decoding: data, as: UTF8.self)
    }
}

/// Open WebUI's live channel: Socket.IO over a plain WebSocket, spoken by
/// hand so Dex needs no package. One connection per `connect()`; after
/// `.disconnected`, connect again.
actor WebUISocket {
    enum Failure: LocalizedError {
        case closed
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .closed: "The live connection closed"
            case .refused(let message): message
            }
        }
    }

    let baseURL: URL
    let auth: WebUIAuth
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<WebUIEvent>.Continuation?
    private var sid: String?

    init(baseURL: URL, auth: WebUIAuth, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.auth = auth
        self.session = session
    }

    /// The socket's address: wss for https, ws for http.
    static func url(for baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme?.lowercased() == "http" ? "ws" : "wss"
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + "/ws/socket.io/"
        components.queryItems = [URLQueryItem(name: "EIO", value: "4"), URLQueryItem(name: "transport", value: "websocket")]
        return components.url
    }

    /// Connects and joins as the signed-in user. Returns the session id a
    /// reply request names, and the events from here on.
    func connect() async throws -> (sid: String, events: AsyncStream<WebUIEvent>) {
        disconnect()
        var token = try await auth.validToken()
        do {
            return try await open(token: token)
        } catch Failure.refused {
            // The server joins nobody on a stale token; renew it once.
            disconnect()
            token = try await auth.renew(rejected: token)
        } catch {
            disconnect()
            throw error
        }
        do {
            return try await open(token: token)
        } catch {
            disconnect()
            throw error
        }
    }

    /// Marks a chat read, as opening it in the web UI does.
    func markRead(chatID: String) {
        guard let frame = SocketPacket.event("events:chat", ["chat_id": chatID, "data": ["type": "last_read_at"]]) else { return }
        task?.send(.string(frame)) { _ in }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        sid = nil
        continuation?.yield(.disconnected)
        continuation?.finish()
        continuation = nil
    }

    private func open(token: String) async throws -> (sid: String, events: AsyncStream<WebUIEvent>) {
        guard let url = Self.url(for: baseURL) else { throw Failure.closed }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        // Open, then the Socket.IO connect with the token, then user-join,
        // whose answer names the user only when the token was accepted.
        guard case .open = try await next(task) else { throw Failure.closed }
        try await send(task, "40" + Self.json(["token": token]))
        var joined: String?
        while joined == nil {
            switch try await next(task) {
            case .connected(let id): joined = id
            case .connectError(let message): throw Failure.refused(message)
            case .ping: try await send(task, "3")
            case .disconnect: throw Failure.closed
            default: continue
            }
        }
        guard let frame = SocketPacket.event("user-join", ["auth": ["token": token]], ack: 0) else { throw Failure.closed }
        try await send(task, frame)
        while true {
            switch try await next(task) {
            case .ack(0, let payload):
                let users = (try? JSONSerialization.jsonObject(with: payload)) as? [Any]
                guard let user = users?.first as? [String: Any], user["id"] != nil else {
                    throw Failure.refused("Sign in again")
                }
            case .ping:
                try await send(task, "3")
                continue
            case .disconnect: throw Failure.closed
            default: continue
            }
            break
        }

        let (events, continuation) = AsyncStream.makeStream(of: WebUIEvent.self)
        self.continuation = continuation
        let sid = joined ?? ""
        self.sid = sid
        Task { await self.receive(task) }
        return (sid, events)
    }

    /// Hands events on until the connection drops.
    private func receive(_ task: URLSessionWebSocketTask) async {
        while self.task === task {
            guard let packet = try? await next(task) else { break }
            switch packet {
            case .ping:
                try? await send(task, "3")
            case .event("events", let payload):
                if let event = WebUIEvent.decode(payload) { continuation?.yield(event) }
            case .disconnect:
                break
            default:
                continue
            }
            if case .disconnect = packet { break }
        }
        if self.task === task { disconnect() }
    }

    private func next(_ task: URLSessionWebSocketTask) async throws -> SocketPacket {
        switch try await task.receive() {
        case .string(let text): return SocketPacket.parse(text)
        case .data(let data): return SocketPacket.parse(String(decoding: data, as: UTF8.self))
        @unknown default: return .other
        }
    }

    private func send(_ task: URLSessionWebSocketTask, _ text: String) async throws {
        try await task.send(.string(text))
    }

    private static func json(_ object: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: object)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
