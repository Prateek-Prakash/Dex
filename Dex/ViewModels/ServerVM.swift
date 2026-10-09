//
//  ServerVM.swift
//  Dex
//
//  Created by Prateek Prakash on 1/24/25.
//

import SwiftUI

/// The Open WebUI server: its address and the account Dex signs in with,
/// and whether it answers. Owns the server's `ModelsVM`, and tells it when
/// the server changes and when a connection comes up.
@MainActor
final class ServerVM: ObservableObject {
    @AppStorage("webUIServerURL") var serverUrl = ""
    @AppStorage("webUIEmail") var email = ""
    /// Kept in the Keychain; sent only to sign in.
    @Published var password = KeychainService.load(KeychainService.webUIPassword)
    /// Off keeps every model off the web.
    @AppStorage("webSearch") var isWebSearchOn = true

    @Published private(set) var isReachable: Bool = false
    @Published private(set) var serverStatus: String = "Not Set"

    /// The server replies run on, once its address and account are set.
    @Published private(set) var server: WebUIServer?
    /// The models on the server, and pulls of new ones.
    let models = ModelsVM()
    private var connectTask: Task<Void, Never>?

    init() {
        Self.removeOllamaSettings()
        connect()
    }

    /// A new password: the token signed in with the old one goes, so the
    /// next request checks the new one.
    func savePassword() {
        KeychainService.save(password, for: KeychainService.webUIPassword)
        KeychainService.save("", for: KeychainService.webUIToken)
        connect()
    }

    func connect() {
        connectTask?.cancel()
        server?.disconnect()
        guard let url = WebUIClient.serverURL(from: serverUrl) else {
            disconnected(serverUrl.isEmpty ? "Not Set" : "Invalid URL")
            return
        }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else {
            disconnected("Sign In Needed")
            return
        }
        let auth = WebUIAuth(baseURL: url, email: email)
        let client = WebUIClient(baseURL: url, auth: auth)
        let server = WebUIServer(client: client, socket: WebUISocket(baseURL: url, auth: auth))
        self.server = server
        models.use(client)
        isReachable = false
        serverStatus = "Connecting..."
        connectTask = Task {
            // Typing in a field reconnects per keystroke; let it settle.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let version = try await client.version()
                guard !Task.isCancelled else { return }
                isReachable = true
                serverStatus = "Open WebUI \(version)"
                await models.connected()
            } catch {
                guard !Task.isCancelled else { return }
                isReachable = false
                serverStatus = error.localizedDescription
            }
        }
    }

    private func disconnected(_ status: String) {
        server = nil
        models.use(nil)
        isReachable = false
        serverStatus = status
    }

    /// The direct-Ollama settings Dex used before Open WebUI.
    private static func removeOllamaSettings() {
        for account in ["ollama.access.id", "ollama.access.secret", "ollama.com.key"] {
            KeychainService.save("", for: account)
        }
        UserDefaults.standard.removeObject(forKey: "serverUrl")
    }
}
