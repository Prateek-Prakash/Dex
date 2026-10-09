//
//  SettingsView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var serverVM: ServerVM
    @EnvironmentObject var modelsVM: ModelsVM
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        TextField("Server URL", text: $serverVM.serverUrl)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .onChange(of: serverVM.serverUrl) { serverVM.connect() }
                        TextField("Email", text: $serverVM.email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .onChange(of: serverVM.email) { serverVM.connect() }
                        SecureField("Password", text: $serverVM.password)
                            .textContentType(.password)
                            .onChange(of: serverVM.password) { serverVM.savePassword() }
                        LabeledContent("Status", value: serverVM.serverStatus)
                    }
                    Section {
                        Toggle("Web Search", isOn: $serverVM.isWebSearchOn)
                            .toggleStyle(.ink)
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
        .tint(Color.ink)
    }
}

#Preview {
    SettingsView()
        .environmentObject(ServerVM())
        .environmentObject(ModelsVM())
}
