//
//  OllamaClientTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/6/26.
//

import Foundation
import Testing
@testable import Dex

/// Answers every request from `handler` and records what was sent.
final class OllamaStubProtocol: URLProtocol {
    struct Reply {
        var status: Int = 200
        var contentType: String = "application/json"
        var body: String = ""
    }

    nonisolated(unsafe) static var handler: (URLRequest) -> Reply = { _ in Reply() }
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        // URLSession moves the body into a stream; read it back for assertions.
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            stream.close()
            request.httpBody = data
        }
        Self.requests.append(request)
        let reply = Self.handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": reply.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func client(headers: [String: String] = [:], _ handler: @escaping (URLRequest) -> Reply) -> OllamaClient {
        Self.handler = handler
        Self.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OllamaStubProtocol.self]
        return OllamaClient(baseURL: URL(string: "https://ollama.example.com")!, headers: headers,
                            session: URLSession(configuration: configuration))
    }
}

@Suite(.serialized)
struct OllamaClientTests {
    @Test(arguments: [
        ("https://ollama.teek.dev", "https://ollama.teek.dev"),
        ("ollama.teek.dev/", "https://ollama.teek.dev"),
        ("  http://192.168.1.5:11434  ", "http://192.168.1.5:11434"),
        ("HTTP://host:11434//", "HTTP://host:11434"),
    ])
    func serverURLAcceptsServerRoots(_ text: String, _ expected: String) {
        #expect(OllamaClient.serverURL(from: text)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "ftp://host", "http://", "https:///api"])
    func serverURLRejectsOthers(_ text: String) {
        #expect(OllamaClient.serverURL(from: text) == nil)
    }

    @Test func accessHeadersNeedBothHalves() {
        #expect(OllamaClient.accessHeaders(id: "id", secret: "secret")
                == ["CF-Access-Client-Id": "id", "CF-Access-Client-Secret": "secret"])
        #expect(OllamaClient.accessHeaders(id: "id", secret: "").isEmpty)
        #expect(OllamaClient.accessHeaders(id: nil, secret: "secret").isEmpty)
    }

    @Test func requestsCarryHeaders() async throws {
        let client = OllamaStubProtocol.client(headers: ["CF-Access-Client-Id": "id"]) { _ in
            .init(body: #"{"version":"0.35.1"}"#)
        }
        #expect(try await client.version() == "0.35.1")
        #expect(OllamaStubProtocol.requests.first?.value(forHTTPHeaderField: "CF-Access-Client-Id") == "id")
        #expect(OllamaStubProtocol.requests.first?.url?.path == "/api/version")
    }

    @Test func modelsDecodeAndSort() async throws {
        let client = OllamaStubProtocol.client { _ in
            .init(body: """
            {"models":[
              {"name":"qwen3.5:9b","model":"qwen3.5:9b","modified_at":"2026-10-06T01:02:03.123456789-07:00",
               "size":6600000000,"digest":"abcdef0123456789","capabilities":["completion","tools","thinking"],
               "details":{"parent_model":"","format":"gguf","family":"qwen3","families":["qwen3"],
                          "parameter_size":"9B","quantization_level":"Q4_K_M"}},
              {"name":"gemma4:12b","size":8100000000,"digest":"0123","details":{}},
              {"name":"gemma4:2b","size":1,"digest":"4567","details":{"family":"gemma4"},"remote_model":"x"}
            ]}
            """)
        }
        let models = try await client.models()
        #expect(models.map(\.name) == ["gemma4:2b", "gemma4:12b", "qwen3.5:9b"])
        #expect(models[2].details.quantizationLevel == "Q4_K_M")
        #expect(models[2].capabilities == ["completion", "tools", "thinking"])
        #expect(models[1].details.format == nil)
    }

    @Test(arguments: [
        ("gemma4:12b", "gemma4", "12b"),
        ("gemma4", "gemma4", "latest"),
        ("hf.co/user/model:Q4_K_M", "hf.co/user/model", "Q4_K_M"),
    ])
    func modelNameParts(_ name: String, _ baseName: String, _ tag: String) {
        let model = OllamaModel(name: name, size: 0, digest: "", details: .init(format: nil, family: nil, parameterSize: nil, quantizationLevel: nil), capabilities: nil)
        #expect(model.baseName == baseName)
        #expect(model.tag == tag)
    }

    @Test func accessRefusalReadsAsAccessDenied() async {
        let client = OllamaStubProtocol.client { _ in
            .init(status: 403, contentType: "text/html", body: "<!DOCTYPE html><html>Forbidden</html>")
        }
        await #expect {
            try await client.version()
        } throws: { error in
            if case .accessDenied = error as? OllamaClient.Failure { return true }
            return false
        }
    }

    @Test func loginPageBehindRedirectReadsAsAccessDenied() async {
        let client = OllamaStubProtocol.client { _ in
            .init(status: 200, contentType: "text/html; charset=utf-8", body: "<html>Sign in</html>")
        }
        await #expect {
            try await client.models()
        } throws: { error in
            if case .accessDenied = error as? OllamaClient.Failure { return true }
            return false
        }
    }

    @Test func ollamaErrorKeepsItsMessage() async {
        let client = OllamaStubProtocol.client { _ in
            .init(status: 404, body: #"{"error":"model 'nope' not found"}"#)
        }
        await #expect {
            try await client.delete(model: "nope")
        } throws: { error in
            error.localizedDescription == "HTTP 404: model 'nope' not found"
        }
    }

    @Test func deleteSendsModelName() async throws {
        let client = OllamaStubProtocol.client { _ in .init() }
        try await client.delete(model: "gemma4:12b")
        let request = try #require(OllamaStubProtocol.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/delete")
        let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
        #expect(body == ["model": "gemma4:12b"])
    }

    @Test func pullStreamsProgress() async throws {
        let client = OllamaStubProtocol.client { _ in
            .init(contentType: "application/x-ndjson", body: """
            {"status":"pulling manifest"}
            {"status":"pulling abc","digest":"abc","total":200,"completed":50}
            {"status":"success"}

            """)
        }
        var statuses: [String] = []
        for try await progress in client.pull(model: "gemma4:12b") {
            statuses.append(progress.status ?? "")
        }
        #expect(statuses == ["pulling manifest", "pulling abc", "success"])
        let body = try JSONDecoder().decode([String: String].self, from: OllamaStubProtocol.requests.first?.httpBody ?? Data())
        #expect(body == ["model": "gemma4:12b"])
    }

    @Test func pullStopsOnStreamedError() async {
        let client = OllamaStubProtocol.client { _ in
            .init(contentType: "application/x-ndjson", body: """
            {"status":"pulling manifest"}
            {"error":"pull model manifest: file does not exist"}

            """)
        }
        await #expect {
            for try await _ in client.pull(model: "nope") {}
        } throws: { error in
            error.localizedDescription == "pull model manifest: file does not exist"
        }
    }

    @Test func pullCutShortFails() async {
        let client = OllamaStubProtocol.client { _ in
            .init(contentType: "application/x-ndjson", body: """
            {"status":"pulling manifest"}
            {"status":"pulling abc","digest":"abc","total":200,"completed":50}

            """)
        }
        await #expect {
            for try await _ in client.pull(model: "gemma4:12b") {}
        } throws: { error in
            error.localizedDescription == "Pull ended before it finished"
        }
    }

    @Test func pullRefusedByAccess() async {
        let client = OllamaStubProtocol.client { _ in
            .init(status: 403, contentType: "text/html", body: "<html></html>")
        }
        await #expect {
            for try await _ in client.pull(model: "gemma4:12b") {}
        } throws: { error in
            if case .accessDenied = error as? OllamaClient.Failure { return true }
            return false
        }
    }
}
