//
//  SettingsView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("serverUrl") var serverUrl = ""

    @EnvironmentObject var globalVM: GlobalVM
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
                                globalVM.connect()
                            }
                        LabeledContent("Status", value: globalVM.serverStatus)
                    }
                    Section {
                        TextField("Access Client ID", text: $globalVM.accessClientID)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: globalVM.accessClientID) { globalVM.saveAccess() }
                        SecureField("Access Client Secret", text: $globalVM.accessClientSecret)
                            .onChange(of: globalVM.accessClientSecret) { globalVM.saveAccess() }
                    }
                    // After the connection settings it depends on, and only once
                    // a server answers: with none there's nothing to manage.
                    if globalVM.isReachable {
                        Section {
                            NavigationLink {
                                ModelsView()
                            } label: {
                                LabeledContent("Models", value: "\(globalVM.models.count)")
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
        .environmentObject(GlobalVM())
}
