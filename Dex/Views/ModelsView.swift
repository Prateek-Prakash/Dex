//
//  ModelsView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import OllamaKit
import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var globalVM: GlobalVM
    
    @State var showPullDialog: Bool = false
    @State var modelName: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                // Failed
                ForEach(Array(globalVM.currentPulls.filter { $0.value.contains("FAILED") }).sorted { $0.key < $1.key }, id: \.key) { entry in
                    LabeledContent {
                        HStack {
                            Button {
                                Task {
                                    await globalVM.pullModel(entry.key)
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(.bordered)
                            Button {
                                globalVM.currentPulls.removeValue(forKey: entry.key)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.red)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.key.split(separator: ":")[0].uppercased())
                                .font(.system(size: 12.0, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.red)
                            Text(entry.key.split(separator: ":").count > 1 ? entry.key.split(separator: ":")[1].uppercased() : "LATEST")
                                .font(.system(size: 10.0, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.red.opacity(0.65))
                            Text(entry.value)
                                .font(.system(size: 9.0, weight: .thin, design: .monospaced))
                                .foregroundStyle(Color.red.opacity(0.65))
                        }
                    }
                }
                // In-Progress
                ForEach(Array(globalVM.currentPulls.filter { !$0.value.contains("FAILED") }).sorted { $0.key < $1.key }, id: \.key) { entry in
                    LabeledContent {
                        ProgressView()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.key.split(separator: ":")[0].uppercased())
                                .font(.system(size: 12.0, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.primary)
                            Text(entry.key.split(separator: ":").count > 1 ? entry.key.split(separator: ":")[1].uppercased() : "LATEST")
                                .font(.system(size: 10.0, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.secondary)
                            Text(entry.value)
                                .font(.system(size: 9.0, weight: .thin, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                // Completed
                ForEach(globalVM.okModels, id: \.name) { model in
                    NavigationLink {
                        ModelDetailsView(okModel: model)
                    } label: {
                        LabeledContent {
                            Text(model.size.byteSize)
                                .fontWeight(.bold)
                                .fontDesign(.rounded)
                                .foregroundStyle(.tertiary)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(model.name.split(separator: ":")[0].uppercased())
                                    .font(.system(size: 12.0, weight: .bold, design: .rounded))
                                Text(model.name.split(separator: ":")[1].uppercased())
                                    .font(.system(size: 10.0, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(model.digest.prefix(12).uppercased())
                                    .font(.system(size: 9.0, weight: .thin, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: globalVM.deleteModel)
            }
            .listStyle(.plain)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Models")
                        .font(.headline)
                        .fontDesign(.rounded)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPullDialog.toggle()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarTitleDisplayMode(.inline)
            .alert("Pull Model", isPresented: $showPullDialog) {
                TextField("Model Name", text: $modelName)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button {
                    Task {
                        let name = modelName
                        modelName = ""
                        await globalVM.pullModel(name)
                    }
                } label: {
                    Text("Pull")
                        .fontDesign(.rounded)
                }
                .disabled(modelName.isEmpty)
                Button("Cancel", role: .cancel) {}
                
            }
        }
        .tint(Color.primary)
    }
}

#Preview {
    ModelsView()
        .environmentObject(GlobalVM())
}

