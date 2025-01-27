//
//  ContentView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject var globalVM = GlobalVM()
    
    @State var showModelsView: Bool = false
    @State var showAboutview: Bool = false
    @State var hapticTrigger: Bool = false
    
    @State var searchText: String = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                ContentUnavailableView("Work-In-Progress", systemImage: "wrench.and.screwdriver", description: Text("ContentView"))
                    .fontDesign(.rounded)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 0.0) {
                        Image(systemName: "livephoto")
                            .foregroundStyle(Color.primary)
                            .symbolEffect(.bounce, options: .speed(0.5), isActive: globalVM.isReachable)
                            .onTapGesture {
                                withAnimation {
                                    hapticTrigger.toggle()
                                }
                            }
                            .sensoryFeedback(.error, trigger: hapticTrigger)
                            .padding(.trailing, 8.0)
                        Menu {
                            ForEach(globalVM.okModels, id: \.name) { model in
                                Button {
                                    globalVM.selectedModel = model.name
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Label(model.name, systemImage: globalVM.selectedModel == model.name ? "brain.fill" : "brain")
                                }
                                .disabled(globalVM.selectedModel == model.name)
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text("Dex")
                                    .font(.system(size: 12.0, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .fontDesign(.rounded)
                                Text(globalVM.selectedModel.uppercased().replacingOccurrences(of: ":", with: " • "))
                                    .font(.system(size: 10.0, weight: .light, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showModelsView.toggle()
                    } label: {
                        Image(systemName: "archivebox")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAboutview.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $showModelsView) {
                ModelsView()
                    .environmentObject(globalVM)
                    .interactiveDismissDisabled(false)
            }
            .sheet(isPresented: Binding(
                get: { showAboutview || !globalVM.isReachable },
                set: { newValue in showAboutview = newValue }
            )) {
                AboutView()
                    .environmentObject(globalVM)
                    .interactiveDismissDisabled(!globalVM.isReachable)
            }
            .searchable(text: $searchText, prompt: Text("Search")) {
                // Something
            }
        }
        .tint(Color.primary)
    }
}

#Preview {
    ContentView()
}
