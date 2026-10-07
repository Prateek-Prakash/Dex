//
//  ServerVM.swift
//  Dex
//
//  Created by Prateek Prakash on 1/24/25.
//

import SwiftUI

/// The Ollama server: its address and Cloudflare Access keys, and whether
/// it answers. Owns the server's `ModelsVM`, and tells it when the server
/// changes and when a connection comes up.
@MainActor
final class ServerVM: ObservableObject {
    @AppStorage("serverUrl") var serverUrl = ""

    @Published var accessClientID = KeychainService.load(KeychainService.accessClientID)
    @Published var accessClientSecret = KeychainService.load(KeychainService.accessClientSecret)

    @Published private(set) var isReachable: Bool = false
    @Published private(set) var serverStatus: String = "Not Set"

    /// The connection to the server, once its address is valid.
    private(set) var client: OllamaClient?
    /// The models on the server, and pulls of new ones.
    let models = ModelsVM()
    private var connectTask: Task<Void, Never>?

    init() {
        connect()
    }

    func saveAccess() {
        KeychainService.save(accessClientID.trimmingCharacters(in: .whitespacesAndNewlines), for: KeychainService.accessClientID)
        KeychainService.save(accessClientSecret.trimmingCharacters(in: .whitespacesAndNewlines), for: KeychainService.accessClientSecret)
        connect()
    }

    func connect() {
        connectTask?.cancel()
        guard let url = OllamaClient.serverURL(from: serverUrl) else {
            client = nil
            models.use(nil)
            isReachable = false
            serverStatus = serverUrl.isEmpty ? "Not Set" : "Invalid URL"
            return
        }
        let client = OllamaClient(baseURL: url, headers: OllamaClient.accessHeaders(
            id: accessClientID.trimmingCharacters(in: .whitespacesAndNewlines),
            secret: accessClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)))
        self.client = client
        models.use(client)
        serverStatus = "Connecting..."
        connectTask = Task {
            // Typing in the URL field reconnects per keystroke; let it settle.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let version = try await client.version()
                guard !Task.isCancelled else { return }
                isReachable = true
                serverStatus = "Ollama \(version)"
                await models.connected()
            } catch {
                guard !Task.isCancelled else { return }
                isReachable = false
                serverStatus = error.localizedDescription
            }
        }
    }
}
