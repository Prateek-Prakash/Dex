//
//  ModelDetailsView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/26/25.
//

import OllamaKit
import SwiftUI
import Swollama

struct ModelDetailsView: View {
    let okModel: OKModelResponse.Model
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Name", value: okModel.name.split(separator: ":")[0])
                        .fontDesign(.rounded)
                    LabeledContent("Tag", value: okModel.name.split(separator: ":")[1])
                        .fontDesign(.rounded)
                    LabeledContent("Hash", value: okModel.digest.prefix(12))
                        .fontDesign(.rounded)
                    LabeledContent("Size", value: okModel.size.byteSize)
                        .fontDesign(.rounded)
                }
                Section {
                    LabeledContent("Format", value: okModel.details.format)
                        .fontDesign(.rounded)
                    LabeledContent("Family", value: okModel.details.family)
                        .fontDesign(.rounded)
                    LabeledContent("Parameter Size", value: okModel.details.parameterSize)
                        .fontDesign(.rounded)
                    LabeledContent("Quantization Level", value: okModel.details.quantizationLevel)
                        .fontDesign(.rounded)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Model Details")
                        .font(.headline)
                        .fontDesign(.rounded)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarTitleDisplayMode(.inline)
        }
        .tint(Color.primary)
    }
}
