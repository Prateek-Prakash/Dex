//
//  OllamaClient.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import Foundation

/// An installed model, as listed by `/api/tags`.
struct OllamaModel: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let size: Int
    let digest: String
    let details: Details
    let capabilities: [String]?

    var id: String { name }

    /// "gemma4:12b" -> "gemma4"; "library/model" names keep their namespace.
    var baseName: String { String(name.split(separator: ":", maxSplits: 1).first ?? Substring(name)) }

    /// "gemma4:12b" -> "12b"; a name without a tag is "latest".
    var tag: String {
        let parts = name.split(separator: ":", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : "latest"
    }

    struct Details: Codable, Sendable, Hashable {
        let format: String?
        let family: String?
        let parameterSize: String?
        let quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case format, family
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }
}

/// One line of a `/api/pull` stream.
struct OllamaPullProgress: Decodable, Sendable {
    let status: String?
    let total: Int?
    let completed: Int?
    let error: String?
}

/// A `/api/chat` request. Every request asks for the same window: a
/// different `num_ctx` makes Ollama reload the model.
struct OllamaChatRequest: Encodable, Sendable {
    static let contextLength = 65_536

    struct Message: Encodable, Sendable, Equatable {
        let role: String
        let content: String
        /// A reply's requests to run tools, sent back with their results.
        var toolCalls: [OllamaToolCall]?
        /// Which tool a "tool" message answers.
        var toolName: String?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
            case toolName = "tool_name"
        }
    }

    struct Options: Encodable, Sendable {
        var numCtx = OllamaChatRequest.contextLength

        enum CodingKeys: String, CodingKey {
            case numCtx = "num_ctx"
        }
    }

    let model: String
    var messages: [Message]
    /// Nil leaves the setting out: a model that can't think rejects even `false`.
    var think: Bool?
    var stream = true
    /// How long the server keeps the model loaded after the last request.
    var keepAlive = "30m"
    var options = Options()
    /// Tools the model may call; nil sends none.
    var tools: [OllamaTool]?

    enum CodingKeys: String, CodingKey {
        case model, messages, think, stream, options, tools
        case keepAlive = "keep_alive"
    }
}

/// One line of a `/api/chat` stream.
struct OllamaChatChunk: Decodable, Sendable {
    struct Message: Decodable, Sendable {
        let content: String?
        let thinking: String?
        let toolCalls: [OllamaToolCall]?

        enum CodingKeys: String, CodingKey {
            case content, thinking
            case toolCalls = "tool_calls"
        }
    }

    let message: Message?
    let done: Bool?
    /// Why the model stopped, on the final line: "stop", "length" and so on.
    let doneReason: String?
    let promptEvalCount: Int?
    let evalCount: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case message, done, error
        case doneReason = "done_reason"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}

/// A tool the model may call, as `/api/chat` describes it.
struct OllamaTool: Encodable, Sendable {
    struct Function: Encodable, Sendable {
        let name: String
        let description: String
        let parameters: Parameters
    }

    struct Parameters: Encodable, Sendable {
        var type = "object"
        let properties: [String: Property]
        let required: [String]
    }

    struct Property: Encodable, Sendable {
        let type: String
        let description: String
    }

    var type = "function"
    let function: Function
}

/// A model's request to run a tool.
struct OllamaToolCall: Codable, Sendable, Equatable {
    struct Function: Codable, Sendable, Equatable {
        let name: String
        let arguments: [String: JSONValue]
    }

    let function: Function
}

/// Any JSON value: a tool call's arguments.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }
}

/// One `/api/web_search` hit.
struct OllamaWebResult: Decodable, Sendable {
    let title: String?
    let url: String
    let content: String?
}

/// A page read by `/api/web_fetch`.
struct OllamaWebPage: Decodable, Sendable {
    let title: String?
    let content: String?
}

/// A thin `URLSession` client for the parts of the Ollama API Dex uses.
/// Every request carries `headers`, so a server behind Cloudflare Access works.
struct OllamaClient: Sendable {
    let baseURL: URL
    var headers: [String: String] = [:]
    var session: URLSession = .shared

    enum Failure: LocalizedError {
        case http(status: Int, message: String)
        case accessDenied
        case stream(String)

        var errorDescription: String? {
            switch self {
            case .http(let status, let message):
                return message.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(message)"
            case .accessDenied:
                return "Access denied. Check the Access Client ID and Secret."
            case .stream(let message):
                return message
            }
        }
    }

    /// Cloudflare Access's service-token headers, when both halves are set.
    static func accessHeaders(id: String?, secret: String?) -> [String: String] {
        guard let id, let secret, !id.isEmpty, !secret.isEmpty else { return [:] }
        return ["CF-Access-Client-Id": id, "CF-Access-Client-Secret": secret]
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

    /// ollama.com, which runs web search and fetch for an account's API key.
    static func web(apiKey: String) -> OllamaClient? {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return nil }
        return OllamaClient(baseURL: URL(string: "https://ollama.com")!, headers: ["Authorization": "Bearer \(apiKey)"])
    }

    /// The server's version; doubles as the connection check.
    func version() async throws -> String {
        struct Response: Decodable { let version: String }
        let data = try await send(request(path: "api/version"))
        return try JSONDecoder().decode(Response.self, from: data).version
    }

    func models() async throws -> [OllamaModel] {
        struct Response: Decodable { let models: [OllamaModel] }
        let data = try await send(request(path: "api/tags"))
        return try JSONDecoder().decode(Response.self, from: data).models
            .sorted { $0.name.compare($1.name, options: .numeric) == .orderedAscending }
    }

    func delete(model: String) async throws {
        _ = try await send(request(path: "api/delete", method: "DELETE", body: ["model": model]))
    }

    /// Web search through ollama.com; needs a `web(apiKey:)` client.
    func webSearch(_ query: String, maxResults: Int = 5) async throws -> [OllamaWebResult] {
        struct Body: Encodable {
            let query: String
            let maxResults: Int
            enum CodingKeys: String, CodingKey {
                case query
                case maxResults = "max_results"
            }
        }
        struct Response: Decodable { let results: [OllamaWebResult] }
        let data = try await sendWeb(request(path: "api/web_search", method: "POST",
                                             body: Body(query: query, maxResults: maxResults), timeout: 30))
        return try JSONDecoder().decode(Response.self, from: data).results
    }

    /// A page's text through ollama.com; needs a `web(apiKey:)` client.
    func webFetch(_ url: String) async throws -> OllamaWebPage {
        let data = try await sendWeb(request(path: "api/web_fetch", method: "POST", body: ["url": url], timeout: 30))
        return try JSONDecoder().decode(OllamaWebPage.self, from: data)
    }

    /// Download progress, one line at a time, until the pull succeeds.
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        // A long idle timeout: big models go quiet for minutes while verifying.
        let request = request(path: "api/pull", method: "POST", body: ["model": model], timeout: 600)
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    let http = response as? HTTPURLResponse
                    let status = http?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw Self.failure(status: status, data: data)
                    }
                    if Self.isHTML(http) { throw Failure.accessDenied }
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

    /// The reply, one line at a time. Whether it finished is the caller's
    /// call: a dropped connection ends the stream cleanly too.
    func chat(_ body: OllamaChatRequest) -> AsyncThrowingStream<OllamaChatChunk, Error> {
        // Waits up to two minutes between bytes: a model still loading sends
        // nothing until it is ready.
        let request = request(path: "api/chat", method: "POST", body: body, timeout: 120)
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    let http = response as? HTTPURLResponse
                    let status = http?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw Self.failure(status: status, data: data)
                    }
                    if Self.isHTML(http) { throw Failure.accessDenied }
                    for try await line in bytes.lines {
                        guard let chunk = try? JSONDecoder().decode(OllamaChatChunk.self, from: Data(line.utf8)) else { continue }
                        if let error = chunk.error { throw Failure.stream(error) }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func request(path: String, method: String = "GET", body: (any Encodable)? = nil,
                         timeout: TimeInterval = 15) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard status == 200 else { throw Self.failure(status: status, data: data) }
        // A login page reached through a redirect is a 200 too: an access
        // gate that wants a browser sign-in, not Ollama.
        if Self.isHTML(http) { throw Failure.accessDenied }
        return data
    }

    /// `send` for ollama.com: nothing there is Cloudflare Access, so an HTML
    /// answer is reported as itself, with its status and page title. Judged
    /// by the body, not the header: ollama.com labels its JSON results
    /// text/html.
    private func sendWeb(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let body = String(decoding: data.prefix(64), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("<") {
            // Who answered (a filter or captive page may stand in for ollama.com) and what it said.
            let host = http?.url?.host().map { $0 == request.url?.host() ? "ollama.com" : $0 } ?? "ollama.com"
            let gist = (Self.pageTitle(data) ?? Self.pageText(data)).map { ": \($0)" } ?? ""
            throw Failure.http(status: status, message: "\(host) sent a web page instead of results\(gist)")
        }
        guard status == 200 else {
            if case .http(let status, let message) = Self.failure(status: status, data: data) {
                throw Failure.http(status: status, message: message)
            }
            throw Failure.http(status: status, message: "")
        }
        return data
    }

    /// An HTML page's `<title>`, trimmed.
    static func pageTitle(_ data: Data) -> String? {
        let html = String(decoding: data.prefix(20_000), as: UTF8.self)
        guard let range = html.range(of: #"(?is)<title[^>]*>(.*?)</title>"#, options: .regularExpression) else { return nil }
        let title = html[range]
            .replacingOccurrences(of: #"(?is)</?title[^>]*>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// An HTML page's first words, tags and scripts dropped.
    static func pageText(_ data: Data) -> String? {
        let html = String(decoding: data.prefix(20_000), as: UTF8.self)
        let text = html
            .replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.count > 80 ? String(text.prefix(80)) + "…" : text
    }

    private static func isHTML(_ response: HTTPURLResponse?) -> Bool {
        response?.value(forHTTPHeaderField: "Content-Type")?.localizedCaseInsensitiveContains("html") == true
    }

    /// Ollama's own reason, or a short plain-text one from whatever sits in
    /// front of it; Cloudflare Access's HTML refusal reads as access denied.
    private static func failure(status: Int, data: Data) -> Failure {
        struct ErrorBody: Decodable { let error: String }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            return .http(status: status, message: body.error)
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if (status == 401 || status == 403) && (text.isEmpty || text.hasPrefix("<")) { return .accessDenied }
        guard !text.hasPrefix("<"), text.count <= 200 else { return .http(status: status, message: "") }
        return .http(status: status, message: text)
    }
}
