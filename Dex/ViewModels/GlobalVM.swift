//
//  GlobalVM.swift
//  Dex
//
//  Created by Prateek Prakash on 1/24/25.
//

import Combine
import OllamaKit
import SwiftUI

@MainActor
final class GlobalVM: ObservableObject {
    @AppStorage("serverUrl") var serverUrl = ""
    @AppStorage("selectedModel") var selectedModel: String = "--"
    @AppStorage("currentPulls") var currentPulls: [String:String] = [:]
    
    var ollamaKit = OllamaKit()
    
    @Published var isReachable: Bool = false
    @Published var okModels: [OKModelResponse.Model] = []
    
    init() {
        UITextField.appearance().clearButtonMode = .whileEditing
        initOllamaKit()
    }
    
    func initOllamaKit() {
        if !serverUrl.isEmpty && serverUrl.split(separator: ":").count == 3 {
            ollamaKit = OllamaKit(baseURL: URL(string: serverUrl)!)
            Task {
                isReachable = await ollamaKit.reachable()
                if isReachable {
                    await fetchModels()
                    await resumePulls()
                }
            }
        } else {
            isReachable = false
        }
    }
    
    func fetchModels() async {
        do {
            okModels = try await ollamaKit.models().models.sorted { $0.name < $1.name }
            let names = okModels.map { $0.name }
            if !names.contains(selectedModel) {
                selectedModel = "--"
            }
        } catch {
            print("Error Fetching Models: \(error.localizedDescription)")
        }
    }
    
    func deleteModel(atOffsets offsets: IndexSet) {
        for offset in offsets {
            let model = okModels[offset]
            okModels.remove(atOffsets: offsets)
            Task {
                do {
                    try await ollamaKit.deleteModel(data: .init(name: model.name))
                    await fetchModels()
                } catch {
                    print("Error Deleting Model: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func pullModel(_ name: String) async {
        do {
            for try await response in ollamaKit.pullModel(data: .init(model: name)) {
                var progress = response.completed
                if let completed = response.completed, let total = response.total {
                    progress = Int(Double(completed) / Double(total) * 100)
                }
                var status = "\(response.status.uppercased())..."
                if progress != nil {
                    status += " \(progress!)%"
                }
                if currentPulls[name] != status {
                    currentPulls[name] = status
                }
            }
            currentPulls.removeValue(forKey: name)
            await fetchModels()
        } catch {
            print("Error Pulling Model: \(error.localizedDescription)")
            currentPulls[name] = "FAILED..."
            await fetchModels()
        }
    }
    
    func resumePulls() async {
        for pull in currentPulls {
            Task {
                await pullModel(pull.key)
            }
        }
    }
}
