//
//  ChatTranscriptView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// The open chat's messages: the user's in bubbles on the right, replies
/// full width as Markdown. Follows a growing reply while it is scrolled to
/// the bottom; scrolling up to read leaves it there.
struct ChatTranscriptView: View {
    @EnvironmentObject var chatVM: ChatVM
    @EnvironmentObject var globalVM: GlobalVM

    @State private var isAtBottom: Bool = true

    private static let bottomID = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24.0) {
                    ForEach(chatVM.messages) { message in
                        switch message.role {
                        case .user, .system:
                            UserBubble(text: message.content)
                        case .assistant:
                            ReplyView(message: message, isLast: message.id == chatVM.messages.last?.id)
                        }
                    }
                    Color.clear
                        .frame(height: 1.0)
                        .id(Self.bottomID)
                }
                .padding(.horizontal, 20.0)
                .padding(.vertical, 16.0)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40.0
            } action: { _, atBottom in
                isAtBottom = atBottom
            }
            // A new message always comes into view; a growing reply only
            // while the reader is at the bottom.
            .onChange(of: chatVM.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            .onChange(of: chatVM.messages.last?.content) {
                if isAtBottom {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
        }
    }
}

private struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48.0)
            Text(text)
                .padding(.horizontal, 16.0)
                .padding(.vertical, 10.0)
                .background(Color.composerChip, in: RoundedRectangle(cornerRadius: 20.0, style: .continuous))
                .contextMenu {
                    Button("Copy") {
                        UIPasteboard.general.string = text
                    }
                }
        }
    }
}

private struct ReplyView: View {
    @EnvironmentObject var chatVM: ChatVM
    @EnvironmentObject var globalVM: GlobalVM

    let message: ChatMessage
    let isLast: Bool

    @State private var showsThinking: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            if let thinking = message.thinking {
                thinkingSection(thinking)
            }
            if !message.content.isEmpty {
                ChatMarkdownView(text: message.content)
                    .equatable()
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Copy") {
                            UIPasteboard.general.string = message.content
                        }
                    }
            } else if message.status == .streaming && message.thinking == nil {
                WaitingDots()
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The model's reasoning, folded away under a "Thinking" row.
    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 8.0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsThinking.toggle()
                }
            } label: {
                HStack(spacing: 6.0) {
                    Text(isThinking ? "Thinking" : "Thought Process")
                        .font(.subheadline)
                        .fontDesign(.rounded)
                    IconlyIcon(.chevronDown, .disclosure)
                        .rotationEffect(.degrees(showsThinking ? 180.0 : 0.0))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if showsThinking {
                Text(thinking)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 12.0)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.drawerBorder).frame(width: 2.0)
                    }
            }
        }
    }

    /// Still reasoning: no answer text yet.
    private var isThinking: Bool {
        message.status == .streaming && message.content.isEmpty
    }

    @ViewBuilder
    private var footer: some View {
        switch message.status {
        case .failed:
            VStack(alignment: .leading, spacing: 8.0) {
                Text(message.error ?? "Something went wrong.")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                if isLast {
                    retryButton
                }
            }
        case .stopped:
            HStack(spacing: 12.0) {
                Text("Stopped")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isLast {
                    retryButton
                }
            }
        case .streaming, .done:
            EmptyView()
        }
    }

    private var retryButton: some View {
        Button {
            chatVM.retry(client: globalVM.client, model: globalVM.pickedModel)
        } label: {
            HStack(spacing: 6.0) {
                IconlyIcon(.refresh, .inlineButton)
                Text("Retry")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
            }
            .padding(.horizontal, 12.0)
            .padding(.vertical, 6.0)
            .background(Color.composerChip, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Three dots breathing in turn while a reply has yet to start.
private struct WaitingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6.0) {
                ForEach(0..<3) { index in
                    Circle()
                        .frame(width: 8.0, height: 8.0)
                        .opacity(0.3 + 0.7 * max(0, sin((time * 3.0) - Double(index) * 0.6)))
                }
            }
            .foregroundStyle(.secondary)
        }
        .frame(height: 22.0)
        .accessibilityLabel("Waiting for a reply")
    }
}
