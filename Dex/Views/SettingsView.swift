//
//  SettingsView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("serverUrl") var serverUrl = ""

    @EnvironmentObject var serverVM: ServerVM
    @EnvironmentObject var modelsVM: ModelsVM
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        TextField("Server URL", text: $serverUrl)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: serverUrl) {
                                serverVM.connect()
                            }
                        LabeledContent("Status", value: serverVM.serverStatus)
                    }
                    Section {
                        TextField("Access Client ID", text: $serverVM.accessClientID)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: serverVM.accessClientID) { serverVM.saveAccess() }
                        SecureField("Access Client Secret", text: $serverVM.accessClientSecret)
                            .onChange(of: serverVM.accessClientSecret) { serverVM.saveAccess() }
                    }
                    // After the connection settings it depends on, and only once
                    // a server answers: with none there's nothing to manage.
                    if serverVM.isReachable {
                        Section {
                            NavigationLink {
                                ModelsView()
                            } label: {
                                LabeledContent("Models", value: "\(modelsVM.models.count)")
                            }
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
                .settingsRows()
            }
            .settingsList()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        IconlyIcon(.close, .action)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.headline)
                        .fontDesign(.rounded)
                }
            }
            .toolbarTitleDisplayMode(.inline)
        }
        .tint(Color.primary)
    }
}

#Preview {
    SettingsView()
        .environmentObject(ServerVM())
        .environmentObject(ModelsVM())
}
