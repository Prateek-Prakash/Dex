//
//  StubProtocol.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/6/26.
//

import Foundation
import Testing
@testable import Dex

/// Answers every request from `handler` and records what was sent.
final class StubProtocol: URLProtocol {
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

    /// A session whose every request `handler` answers.
    static func session(_ handler: @escaping (URLRequest) -> Reply) -> URLSession {
        Self.handler = handler
        Self.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// Every suite that answers requests through `StubProtocol`. Its
/// handler is one static, so these suites must not run alongside each other;
/// `.serialized` on a parent covers every suite nested in it.
@Suite(.serialized)
enum StubbedNetworkTests {}

