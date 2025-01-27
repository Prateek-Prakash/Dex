//
//  AboutView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import SwiftUI

struct AboutView: View {
    @AppStorage("serverUrl") var serverUrl = ""
    
    @EnvironmentObject var globalVM: GlobalVM
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Server URL", text: $serverUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: serverUrl) {
                            globalVM.initOllamaKit()
                        }
                }
                Section {
                    LabeledContent("Name", value: "Dex")
                    LabeledContent("Version", value: "1.0.0+1")
                    LabeledContent("Bundle ID", value: "Teekzilla.Dex")
                    LabeledContent("Developer", value: "Teekzilla")
                }
                Section {
                    LabeledContent("Model", value: UIDevice.current.model)
                    LabeledContent("System Name", value: UIDevice.current.systemName)
                    LabeledContent("System Version", value: UIDevice.current.systemVersion)
                    LabeledContent("User Interface", value: UIDevice.current.userInterfaceIdiom.toString())
                }
                
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("About")
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

#Preview {
    AboutView()
        .environmentObject(GlobalVM())
}

