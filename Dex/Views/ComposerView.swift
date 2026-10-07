//
//  ComposerView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// The message box at the bottom of the main screen. A mock until chat
/// exists: typing works, the picker sets the selected model, the microphone
/// and Send do nothing.
struct ComposerView: View {
    @EnvironmentObject var globalVM: GlobalVM
    
    var isFocused: FocusState<Bool>.Binding

    @State private var message: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            TextField("Ask Dex", text: $message, axis: .vertical)
                .lineLimit(1...6)
                .focused(isFocused)
                .fontDesign(.rounded)
            HStack {
                Menu {
                    ForEach(globalVM.models) { model in
                        Button(model.name) {
                            globalVM.selectedModel = model.name
                        }
                    }
                } label: {
                    HStack(spacing: 4.0) {
                        Text(globalVM.pickedModel?.name ?? "Model")
                            .font(.subheadline)
                            .fontDesign(.rounded)
                            .lineLimit(1)
                        IconlyIcon(.chevronDown, .disclosure)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12.0)
                    .padding(.vertical, 7.0)
                    .background(Color.composerChip, in: Capsule())
                }
                Spacer()
                Button {
                    // Mock: dictation arrives with chat.
                } label: {
                    IconlyIcon(.microphone, .field)
                        .padding(6.0)
                        .background(Color.composerChip, in: Circle())
                }
                .buttonStyle(.plain)
                Button {
                    // Mock: sending arrives with chat.
                } label: {
                    IconlyIcon(.send, .row)
                        .foregroundStyle(Color.appBackground)
                        .padding(8.0)
                        .background(Color.primary.opacity(message.isEmpty ? 0.3 : 1.0), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16.0)
        .glassRoundedRect(cornerRadius: 28.0)
        .padding(.horizontal, 12.0)
        .padding(.bottom, 8.0)
    }
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    ComposerView(isFocused: $isFocused)
        .environmentObject(GlobalVM())
}
