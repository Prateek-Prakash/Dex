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

    private func request(path: String, method: String = "GET", body: [String: String]? = nil,
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
