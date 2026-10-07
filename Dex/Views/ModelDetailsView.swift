//
//  ModelDetailsView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/26/25.
//

import SwiftUI

struct ModelDetailsView: View {
    let model: OllamaModel
    
    var body: some View {
        List {
            Group {
                Section {
                    LabeledContent("Name", value: model.baseName)
                        .fontDesign(.rounded)
                    LabeledContent("Tag", value: model.tag)
                        .fontDesign(.rounded)
                    LabeledContent("Hash", value: model.digest.prefix(12))
                        .fontDesign(.rounded)
                    LabeledContent("Size", value: model.size.byteSize)
                        .fontDesign(.rounded)
                }
                Section {
                    LabeledContent("Format", value: model.details.format ?? "—")
                        .fontDesign(.rounded)
                    LabeledContent("Family", value: model.details.family ?? "—")
                        .fontDesign(.rounded)
                    LabeledContent("Parameter Size", value: model.details.parameterSize ?? "—")
                        .fontDesign(.rounded)
                    LabeledContent("Quantization Level", value: model.details.quantizationLevel ?? "—")
                        .fontDesign(.rounded)
                }
            }
            .settingsRows()
        }
        .settingsList()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Model Details")
                    .font(.headline)
                    .fontDesign(.rounded)
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .tint(Color.primary)
    }
}
