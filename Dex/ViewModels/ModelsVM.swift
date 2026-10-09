//
//  ModelsVM.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// The models on the server, the one picked for chats, and pulls of new
/// ones through the server's Ollama. Owned by `ServerVM`, which hands it
/// each new connection.
@MainActor
final class ModelsVM: ObservableObject {
    @AppStorage("selectedModel") var selectedModel: String = "--"
    @AppStorage("currentPulls") var currentPulls: [String:String] = [:]

    @Published private(set) var models: [OllamaModel] = []

    /// The picked model, when the server has it. The choice itself persists
    /// in `selectedModel` and is cleared only once a model list without it loads.
    var pickedModel: OllamaModel? {
        Self.pickedModel(named: selectedModel, in: models)
    }

    nonisolated static func pickedModel(named name: String, in models: [OllamaModel]) -> OllamaModel? {
        models.first { $0.name == name }
    }

    /// The server's connection; nil while it isn't set up.
    private var client: WebUIClient?
    /// Running pulls by model name. Each belongs to the client it started on.
    private var pullTasks: [String: Task<Void, Never>] = [:]

    /// A new server, or none. Pulls on the old one stop; their entries stay
    /// and resume once this one connects.
    func use(_ client: WebUIClient?) {
        self.client = client
        pullTasks.values.forEach { $0.cancel() }
        pullTasks = [:]
    }

    /// The server answered: load its models and resume pulls.
    func connected() async {
        await fetchModels()
        await resumePulls()
    }

    /// The models Open WebUI lists, hidden and arena ones left out. With
    /// none picked, or the picked one gone, the server's default is picked.
    func fetchModels() async {
        guard let client else { return }
        do {
            models = try await client.models().filter(\.isListed).map(Self.model)
            let names = models.map { $0.name }
            if !names.contains(selectedModel) {
                let defaults = (try? await client.defaultModels()) ?? []
                selectedModel = defaults.first { names.contains($0) } ?? "--"
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
                    let status = Self.pullStatus(response)
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
                currentPulls[name] = Self.failedStatus(error.localizedDescription)
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

    /// A server model in the shape the model screens show.
    nonisolated static func model(_ model: WebUIModel) -> OllamaModel {
        OllamaModel(name: model.id, size: model.ollama?.size ?? 0, digest: model.ollama?.digest ?? "",
                    details: model.ollama?.details ?? .init(format: nil, family: nil, parameterSize: nil, quantizationLevel: nil),
                    capabilities: model.ollama?.capabilities)
    }

    /// "PULLING ABC... 25%" from one line of a pull; the percentage only
    /// once the server reports a size, and never past 100.
    nonisolated static func pullStatus(_ progress: OllamaPullProgress) -> String {
        var status = "\((progress.status ?? "").uppercased())..."
        if let completed = progress.completed, let total = progress.total, total > 0 {
            status += " \(min(100, Int(Double(completed) / Double(total) * 100)))%"
        }
        return status
    }

    /// A failed pull's entry; `resumePulls` skips entries that say FAILED.
    nonisolated static func failedStatus(_ reason: String) -> String {
        "FAILED... \(reason.uppercased())"
    }

    func resumePulls() async {
        for pull in currentPulls where !pull.value.contains("FAILED") {
            Task {
                await pullModel(pull.key)
            }
        }
    }
}
