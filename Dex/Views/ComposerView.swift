//
//  ComposerView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// The message box at the bottom of the main screen: the message, the
/// model picker, and Send (Stop while a reply streams). The microphone is a mock until dictation exists.
struct ComposerView: View {
    @EnvironmentObject var globalVM: GlobalVM
    @EnvironmentObject var chatVM: ChatVM
    
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
                    // Mock: dictation comes later.
                } label: {
                    IconlyIcon(.microphone, .field)
                        .padding(6.0)
                        .background(Color.composerChip, in: Circle())
                }
                .buttonStyle(.plain)
                if chatVM.isStreaming {
                    Button {
                        chatVM.stop()
                    } label: {
                        // A plain square, like Claude's Stop; drawn, not an icon.
                        RoundedRectangle(cornerRadius: 3.0, style: .continuous)
                            .fill(Color.appBackground)
                            .frame(width: 12.0, height: 12.0)
                            .frame(width: 16.0, height: 16.0)
                            .padding(8.0)
                            .background(Color.primary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop")
                } else {
                    Button {
                        send()
                    } label: {
                        IconlyIcon(.send, .row)
                            .foregroundStyle(Color.appBackground)
                            .padding(8.0)
                            .background(Color.primary.opacity(canSend ? 1.0 : 0.3), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                }
            }
        }
        .padding(16.0)
        .glassRoundedRect(cornerRadius: 28.0)
        .padding(.horizontal, 12.0)
        .padding(.bottom, 8.0)
        .sensoryFeedback(.impact(weight: .light), trigger: chatVM.messages.count)
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && globalVM.pickedModel != nil
    }

    private func send() {
        guard canSend else { return }
        chatVM.send(message, client: globalVM.client, model: globalVM.pickedModel)
        message = ""
    }
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    ComposerView(isFocused: $isFocused)
        .environmentObject(GlobalVM())
        .environmentObject(ChatVM())
}
