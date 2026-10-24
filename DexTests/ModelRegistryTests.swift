//
//  ModelRegistryTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/23/26.
//

import CryptoKit
import Foundation
import Testing
@testable import Dex

extension StubbedNetworkTests {
    @Suite(.serialized)
    struct ModelRegistryTests {
        static let manifest = #"{"schemaVersion":2,"layers":[]}"#
        static let manifestDigest = SHA256.hash(data: Data(manifest.utf8)).map { String(format: "%02x", $0) }.joined()

        @Test(arguments: [
            ("gemma4:12b", "https://registry.ollama.ai/v2/library/gemma4/manifests/12b"),
            ("gemma4", "https://registry.ollama.ai/v2/library/gemma4/manifests/latest"),
            ("someone/model:q4", "https://registry.ollama.ai/v2/someone/model/manifests/q4"),
            ("registry.ollama.ai/someone/model:q4", "https://registry.ollama.ai/v2/someone/model/manifests/q4"),
        ])
        func manifestURLFollowsOllamaNames(model: String, url: String) {
            #expect(ModelRegistry.manifestURL(for: model)?.absoluteString == url)
        }

        @Test(arguments: ["hf.co/someone/model:Q4_K_M", "a/b/c/d", ":tag", ""])
        func otherRegistriesCantBeChecked(model: String) {
            #expect(ModelRegistry.manifestURL(for: model) == nil)
        }

        @Test func bareDigestDropsPrefixAndCase() {
            #expect(ModelRegistry.bareDigest("sha256:ABC123") == "abc123")
            #expect(ModelRegistry.bareDigest("abc123") == "abc123")
        }

        @Test func sameManifestIsUpToDate() async throws {
            let registry = ModelRegistry(session: StubProtocol.session { _ in .init(body: Self.manifest) })
            #expect(await registry.hasUpdate(model: "gemma4:12b", digest: Self.manifestDigest) == false)
            let request = try #require(StubProtocol.requests.last)
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.docker.distribution.manifest.v2+json")
        }

        @Test func prefixedUppercaseDigestStillMatches() async {
            let registry = ModelRegistry(session: StubProtocol.session { _ in .init(body: Self.manifest) })
            #expect(await registry.hasUpdate(model: "gemma4:12b", digest: "sha256:" + Self.manifestDigest.uppercased()) == false)
        }

        @Test func changedManifestIsAnUpdate() async {
            let registry = ModelRegistry(session: StubProtocol.session { _ in .init(body: Self.manifest) })
            #expect(await registry.hasUpdate(model: "gemma4:12b", digest: String(repeating: "0", count: 64)) == true)
        }

        @Test func unknownModelOrErrorSaysNothing() async {
            let registry = ModelRegistry(session: StubProtocol.session { _ in .init(status: 404, body: "{}") })
            #expect(await registry.hasUpdate(model: "mine:latest", digest: Self.manifestDigest) == nil)
        }

        @Test func noDigestOrOtherRegistryNeverAsks() async {
            let registry = ModelRegistry(session: StubProtocol.session { _ in .init(body: Self.manifest) })
            #expect(await registry.hasUpdate(model: "gemma4:12b", digest: nil) == nil)
            #expect(await registry.hasUpdate(model: "hf.co/someone/model:Q4", digest: Self.manifestDigest) == nil)
            #expect(StubProtocol.requests.isEmpty)
        }
    }
}
