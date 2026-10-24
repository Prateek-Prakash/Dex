//
//  ModelRegistry.swift
//  Dex
//
//  Created by Prateek Prakash on 10/23/26.
//

import CryptoKit
import Foundation

/// Ollama's public model library, asked whether a model has a newer build.
/// A model's digest is the SHA-256 of its manifest, so the library's current
/// manifest hashes to the server's digest exactly when nothing changed.
struct ModelRegistry: Sendable {
    static let host = "registry.ollama.ai"

    var session: URLSession = .shared

    /// The library's manifest for "gemma4:12b", "user/model" or
    /// "registry.ollama.ai/user/model:tag"; nil for another registry's
    /// model (hf.co and the like), which can't be checked here.
    nonisolated static func manifestURL(for model: String) -> URL? {
        var parts = model.split(separator: "/").map(String.init)
        if parts.count == 3 {
            guard parts.removeFirst() == host else { return nil }
        }
        guard (1...2).contains(parts.count), let last = parts.popLast() else { return nil }
        let nameAndTag = last.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let namespace = parts.first ?? "library"
        let tag = nameAndTag.count > 1 ? nameAndTag[1] : "latest"
        guard let name = nameAndTag.first, !name.isEmpty, !namespace.isEmpty, !tag.isEmpty else { return nil }
        return URL(string: "https://\(host)/v2/\(namespace)/\(name)/manifests/\(tag)")
    }

    /// Whether the library's build differs from `digest`; nil when it can't
    /// say (another registry, a model the library doesn't have, no network).
    func hasUpdate(model: String, digest: String?) async -> Bool? {
        guard let digest = digest.map(Self.bareDigest), !digest.isEmpty,
              let url = Self.manifestURL(for: model) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.docker.distribution.manifest.v2+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        let latest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return latest != digest
    }

    /// "sha256:ABC" -> "abc".
    nonisolated static func bareDigest(_ digest: String) -> String {
        let lowered = digest.lowercased()
        return lowered.hasPrefix("sha256:") ? String(lowered.dropFirst("sha256:".count)) : lowered
    }
}
