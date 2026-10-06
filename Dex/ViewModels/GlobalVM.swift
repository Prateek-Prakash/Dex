//
//  GlobalVM.swift
//  Dex
//
//  Created by Prateek Prakash on 1/24/25.
//

import Combine
import SwiftUI

@MainActor
final class GlobalVM: ObservableObject {
    @AppStorage("serverUrl") var serverUrl = ""
    @AppStorage("selectedModel") var selectedModel: String = "--"
    @AppStorage("currentPulls") var currentPulls: [String:String] = [:]

    @Published var accessClientID = KeychainService.load(KeychainService.accessClientID)
    @Published var accessClientSecret = KeychainService.load(KeychainService.accessClientSecret)

    @Published var isReachable: Bool = false
    @Published var serverStatus: String = "Not Set"
    @Published var models: [OllamaModel] = []

    private var client: OllamaClient?
    private var connectTask: Task<Void, Never>?
    /// Running pulls by model name. Each belongs to the client it started on.
    private var pullTasks: [String: Task<Void, Never>] = [:]

    init() {
        UITextField.appearance().clearButtonMode = .whileEditing
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
            isReachable = false
            serverStatus = serverUrl.isEmpty ? "Not Set" : "Invalid URL"
            return
        }
        let client = OllamaClient(baseURL: url, headers: OllamaClient.accessHeaders(
            id: accessClientID.trimmingCharacters(in: .whitespacesAndNewlines),
            secret: accessClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)))
        self.client = client
        // Pulls on the old server stop; their entries stay and resume on this one.
        pullTasks.values.forEach { $0.cancel() }
        pullTasks = [:]
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
                await fetchModels()
                await resumePulls()
            } catch {
                guard !Task.isCancelled else { return }
                isReachable = false
                serverStatus = error.localizedDescription
            }
        }
    }

    func fetchModels() async {
        guard let client else { return }
        do {
            models = try await client.models()
            let names = models.map { $0.name }
            if !names.contains(selectedModel) {
                selectedModel = "--"
            }
        } catch {
            print("Error Fetching Models: \(error.localizedDescription)")
        }
    }

    func deleteModel(named name: String) {
        guard let client else { return }
        models.removeAll { $0.name == name }
        Task {
            do {
                try await client.delete(model: name)
            } catch {
                print("Error Deleting Model: \(error.localizedDescription)")
            }
            await fetchModels()
        }
    }

    func pullModel(_ name: String) async {
        guard let client else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, pullTasks[name] == nil else { return }
        currentPulls[name] = "STARTING..."
        let task = Task {
            do {
                for try await response in client.pull(model: name) {
                    guard !Task.isCancelled else { return }
                    var status = "\((response.status ?? "").uppercased())..."
                    if let completed = response.completed, let total = response.total, total > 0 {
                        status += " \(Int(Double(completed) / Double(total) * 100))%"
                    }
                    if currentPulls[name] != status {
                        currentPulls[name] = status
                    }
                }
                guard !Task.isCancelled else { return }
                currentPulls.removeValue(forKey: name)
            } catch {
                // Cancelled by a server switch: leave the entry for the new server.
                guard !Task.isCancelled else { return }
                print("Error Pulling Model: \(error.localizedDescription)")
                currentPulls[name] = "FAILED... \(error.localizedDescription.uppercased())"
            }
            await fetchModels()
        }
        pullTasks[name] = task
        await task.value
        // A server switch may have replaced this pull with a new one.
        if pullTasks[name] == task {
            pullTasks[name] = nil
        }
    }

    func resumePulls() async {
        for pull in currentPulls where !pull.value.contains("FAILED") {
            Task {
                await pullModel(pull.key)
            }
        }
    }
}
