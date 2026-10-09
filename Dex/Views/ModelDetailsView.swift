//
//  ModelDetailsView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/26/25.
//

import SwiftUI

/// One model: what the server's model list says, then its base model,
/// maker and license, asked for when the page opens.
struct ModelDetailsView: View {
    @EnvironmentObject var modelsVM: ModelsVM
    let model: WebUIModel

    /// Nil until asked for; the rows show "—" meanwhile and if it fails.
    @State private var info: WebUIModelInfo?

    var body: some View {
        List {
            Group {
                Section {
                    row("Name", model.baseName)
                    row("Tag", model.tag)
                    row("Hash", model.digest == nil ? nil : model.shortDigest)
                    row("Size", model.size.map(\.byteSize))
                    row("Updated", model.modifiedAt.map { $0.formatted(date: .abbreviated, time: .omitted) })
                }
                Section {
                    row("Format", model.details?.format)
                    row("Family", model.details?.family)
                    row("Parameter Size", model.details?.parameterSize)
                    row("Quantization Level", model.details?.quantizationLevel)
                    row("Max Context", model.details?.contextLength.map(Self.contextLabel))
                }
                Section {
                    row("Capabilities", Self.capabilitiesLabel(model.capabilities))
                    row("Loaded", model.isLoaded ? "Yes" : "No")
                }
                Section {
                    row("Base Model", info?.baseModel)
                    row("Maker", info?.maker)
                    row("License", info?.license)
                }
            }
            .settingsRows()
        }
        .settingsList()
        .task { info = await modelsVM.info(for: model) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Model Details")
                    .font(.headline)
                    .fontDesign(.rounded)
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .tint(Color.ink)
    }

    private func row(_ title: String, _ value: String?) -> some View {
        LabeledContent(title, value: value ?? "—")
            .fontDesign(.rounded)
    }

    /// 262,144 tokens -> "256K".
    nonisolated static func contextLabel(_ tokens: Int) -> String {
        tokens >= 1024 && tokens % 1024 == 0 ? "\(tokens / 1024)K" : tokens.formatted()
    }

    /// The server's names, capitalized, in a fixed order; plain text
    /// generation goes without saying.
    nonisolated static func capabilitiesLabel(_ capabilities: [String]) -> String? {
        let order = ["thinking", "tools", "vision", "audio", "embedding"]
        let shown = capabilities.filter { $0 != "completion" }
            .sorted { (order.firstIndex(of: $0) ?? order.count) < (order.firstIndex(of: $1) ?? order.count) }
            .map(\.capitalized)
        return shown.isEmpty ? nil : shown.joined(separator: " • ")
    }
}
