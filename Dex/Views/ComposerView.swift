//
//  ComposerView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// The message box at the bottom of the main screen: the message, the
/// model picker, the microphone, and Send (Stop while a reply streams).
/// While dictating, like Claude's, the row becomes cancel, a live waveform,
/// stop and send, and the words type into the box as they're heard. Stop
/// keeps them for editing; cancel puts the box back as it was.
struct ComposerView: View {
    @EnvironmentObject var serverVM: ServerVM
    @EnvironmentObject var modelsVM: ModelsVM
    @EnvironmentObject var chatVM: ChatVM
    
    var isFocused: FocusState<Bool>.Binding

    @State private var message: String = ""
    @StateObject private var dictation = Dictation()
    /// Rebuilds the text field after each send: iOS can leave a multi-line
    /// field showing text it was told to clear, mid keyboard suggestion.
    @State private var fieldID = UUID()
    /// The box's text when dictation started; heard words follow it.
    @State private var textBeforeDictation: String = ""
    /// What dictation last put in the box, to tell typing apart from it.
    @State private var dictatedMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            TextField("Ask Dex", text: $message, axis: .vertical)
                .id(fieldID)
                .lineLimit(1...6)
                .focused(isFocused)
                .fontDesign(.rounded)
            if dictation.isActive {
                recordingRow
            } else {
                controlsRow
            }
        }
        .padding(Space.xl)
        .glassRoundedRect(cornerRadius: Radius.composer)
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.m)
        .sensoryFeedback(.impact(weight: .light), trigger: chatVM.messages.count)
        .sensoryFeedback(.start, trigger: dictation.state == .recording)
        // Leaving the screen ends a recording; the words heard stay.
        .onDisappear { dictation.stop() }
        .onChange(of: dictation.transcript) {
            guard dictation.isActive else { return }
            dictatedMessage = Dictation.joined(textBeforeDictation, dictation.transcript)
            message = dictatedMessage
        }
        // Typing while dictating ends the recording, keeping the edit; the
        // next heard words would otherwise overwrite it.
        .onChange(of: message) {
            if dictation.isActive, message != dictatedMessage {
                dictation.stop()
            }
        }
        .alert("Dictation", isPresented: Binding(
            get: { dictation.error != nil },
            set: { if !$0 { dictation.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dictation.error ?? "")
        }
    }

    /// Cancel, the waveform, stop and send, while dictating.
    private var recordingRow: some View {
        HStack(spacing: Space.l) {
            Button {
                dictation.stop()
                message = textBeforeDictation
            } label: {
                IconlyIcon(.close, .field)
                    .padding(Space.s)
                    .background(Color.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel Dictation")
            WaveformView(levels: dictation.levels, lastSample: dictation.lastSample)
                .frame(maxWidth: .infinity)
            Button {
                dictation.stop()
            } label: {
                stopSquare
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop Dictation")
            sendButton {
                dictation.stop()
                send()
            }
        }
    }

    /// The model picker, microphone and Send or Stop.
    private var controlsRow: some View {
        HStack {
            Menu {
                ForEach(modelsVM.models) { model in
                    Button(model.name) {
                        modelsVM.selectedModel = model.name
                    }
                }
            } label: {
                HStack(spacing: Space.xs) {
                    Text(modelsVM.pickedModel?.name ?? "Model")
                        .font(.subheadline)
                        .fontDesign(.rounded)
                        .lineLimit(1)
                    IconlyIcon(.chevronDown, .disclosure)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, Space.l)
                // spacing: the model pill's height beside the microphone circle, by design
                .padding(.vertical, 7.0)
                .background(Color.surfaceRaised, in: Capsule())
            }
            Spacer()
            Button {
                textBeforeDictation = message
                dictatedMessage = message
                isFocused.wrappedValue = true
                Task { await dictation.start() }
            } label: {
                IconlyIcon(.microphone, .field)
                    .padding(Space.s)
                    .background(Color.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dictate")
            // A reply coming on another device can't be stopped here; Send
            // stays off until it finishes.
            if chatVM.isReplyingHere {
                Button {
                    chatVM.stop()
                } label: {
                    stopSquare
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop")
            } else {
                sendButton { send() }
            }
        }
    }

    /// A plain square, like Claude's Stop; drawn, not an icon. On the
    /// microphone's chip.
    private var stopSquare: some View {
        RoundedRectangle(cornerRadius: Radius.stopSquare, style: .continuous)
            .fill(Color.inkSoft)
            .frame(width: 12.0, height: 12.0)
            .frame(width: 16.0, height: 16.0)
            .padding(Space.m)
            .background(Color.surfaceRaised, in: Circle())
    }

    private func sendButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconlyIcon(.send, .row)
                .foregroundStyle(Color.surfaceBase)
                .padding(Space.m)
                .background(Color.ink.opacity(canSend ? 1.0 : 0.3), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel("Send")
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && modelsVM.pickedModel != nil && !chatVM.isStreaming
    }

    private func send() {
        guard canSend else { return }
        chatVM.send(message, client: serverVM.client, model: modelsVM.pickedModel, web: serverVM.webClient)
        message = ""
        fieldID = UUID()
        // Like Claude: the keyboard closes on send, the reply in full view.
        isFocused.wrappedValue = false
    }
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    ComposerView(isFocused: $isFocused)
        .environmentObject(ServerVM())
        .environmentObject(ModelsVM())
        .environmentObject(ChatVM())
}
