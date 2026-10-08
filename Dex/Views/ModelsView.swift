//
//  ModelsView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var modelsVM: ModelsVM
    
    @State var showPullDialog: Bool = false
    @State var modelName: String = ""
    @State var modelToDelete: OllamaModel?
    
    var body: some View {
        List {
            Group {
                // Failed
                ForEach(Array(modelsVM.currentPulls.filter { $0.value.contains("FAILED") }).sorted { $0.key < $1.key }, id: \.key) { entry in
                    LabeledContent {
                        HStack {
                            Button {
                                Task {
                                    await modelsVM.pullModel(entry.key)
                                }
                            } label: {
                                IconlyIcon(.refresh, .inlineButton)
                            }
                            .buttonStyle(.bordered)
                            Button {
                                modelsVM.currentPulls.removeValue(forKey: entry.key)
                            } label: {
                                IconlyIcon(.close, .inlineButton)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.destructive)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.key.split(separator: ":")[0].uppercased())
                                .font(.system(size: 12.0, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.destructive)
                            Text(entry.key.split(separator: ":").count > 1 ? entry.key.split(separator: ":")[1].uppercased() : "LATEST")
                                .font(.system(size: 10.0, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.destructive.opacity(0.65))
                            Text(entry.value)
                                .font(.system(size: 9.0, weight: .thin, design: .monospaced))
                                .foregroundStyle(Color.destructive.opacity(0.65))
                        }
                    }
                }
                // In-Progress
                ForEach(Array(modelsVM.currentPulls.filter { !$0.value.contains("FAILED") }).sorted { $0.key < $1.key }, id: \.key) { entry in
                    LabeledContent {
                        ProgressView()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.key.split(separator: ":")[0].uppercased())
                                .font(.system(size: 12.0, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.textPrimary)
                            Text(entry.key.split(separator: ":").count > 1 ? entry.key.split(separator: ":")[1].uppercased() : "LATEST")
                                .font(.system(size: 10.0, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.textSecondary)
                            Text(entry.value)
                                .font(.system(size: 9.0, weight: .thin, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                // Completed
                ForEach(modelsVM.models) { model in
                    NavigationLink {
                        ModelDetailsView(model: model)
                    } label: {
                        LabeledContent {
                            Text(model.size.byteSize)
                                .fontWeight(.bold)
                                .fontDesign(.rounded)
                                .foregroundStyle(.tertiary)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(model.baseName.uppercased())
                                    .font(.system(size: 12.0, weight: .bold, design: .rounded))
                                Text(model.tag.uppercased())
                                    .font(.system(size: 10.0, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(model.digest.prefix(12).uppercased())
                                    .font(.system(size: 9.0, weight: .thin, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete") {
                            modelToDelete = model
                        }
                        .tint(Color.destructive)
                    }
                }
            }
            .settingsRows(background: .clear)
        }
        .settingsList()
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
                    IconlyIcon(.download, .action)
                }
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .alert("Pull Model", isPresented: $showPullDialog) {
            TextField("Model Name", text: $modelName)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Button {
                Task {
                    let name = modelName
                    modelName = ""
                    await modelsVM.pullModel(name)
                }
            } label: {
                Text("Pull")
                    .fontDesign(.rounded)
            }
            .disabled(modelName.isEmpty)
            Button("Cancel", role: .cancel) {}
            
        }
        .alert("Delete Model", isPresented: Binding(
            get: { modelToDelete != nil },
            set: { if !$0 { modelToDelete = nil } }
        ), presenting: modelToDelete) { model in
            Button("Delete", role: .destructive) {
                modelsVM.deleteModel(named: model.name)
            }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text("\(model.baseName.uppercased())\n\(model.tag.uppercased())\n\(model.digest.prefix(12).uppercased())\n\(model.size.byteSize)")
        }
        .tint(Color.ink)
    }
}

#Preview {
    ModelsView()
        .environmentObject(ModelsVM())
}

