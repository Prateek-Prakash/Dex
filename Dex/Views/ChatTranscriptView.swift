//
//  ChatTranscriptView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// The open chat's messages: the user's in bubbles on the right, replies
/// full width as Markdown. Follows whatever grows at the bottom (a reply's
/// answer, its thinking, a Thinking row opened) until the reader scrolls up
/// to read; scrolling back to the end, or sending, follows again.
struct ChatTranscriptView: View {
    @EnvironmentObject var chatVM: ChatVM

    /// Keeps the bottom in view. Only the reader's own scroll turns it off:
    /// content growing faster than the view keeps up must not count as
    /// scrolling up.
    @State private var isFollowing: Bool = true
    @State private var scrollPhase: ScrollPhase = .idle
    /// True while this view animates to the bottom itself: that scroll
    /// passes through "not at the bottom" without being the reader's.
    @State private var isScrollingToBottom = false

    private static let bottomID = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xxxl) {
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
                .padding(.horizontal, Space.xxl)
                .padding(.vertical, Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onScrollPhaseChange { _, phase in
                scrollPhase = phase
                // The reader's finger takes over from any scroll of ours.
                if phase == .interacting { isScrollingToBottom = false }
                guard phase == .idle else { return }
                isScrollingToBottom = false
                // Growth that came while it was moving.
                if isFollowing { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40.0
            } action: { _, atBottom in
                if atBottom {
                    isFollowing = true
                } else if scrollPhase != .idle, !isScrollingToBottom {
                    // The reader's scroll: a drag, a fling, a status bar tap.
                    isFollowing = false
                }
            }
            // Anything growing at the bottom, while following: the answer,
            // its thinking, a Thinking row opened.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height
            } action: { _, _ in
                if isFollowing, scrollPhase == .idle {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            // A new message always comes into view, and follows again; by the
            // last message's id, so a retry (one reply for another) counts.
            .onChange(of: chatVM.messages.last?.id) {
                isFollowing = true
                isScrollingToBottom = true
                withAnimation(.easeOut(duration: 0.2)) {
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
                .padding(.horizontal, Space.xl)
                // spacing: a bubble's top and bottom, between the m and l steps by design
                .padding(.vertical, 10.0)
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
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
    @EnvironmentObject var serverVM: ServerVM
    @EnvironmentObject var modelsVM: ModelsVM

    let message: ChatMessage
    let isLast: Bool

    @State private var showsThinking: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
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
        VStack(alignment: .leading, spacing: Space.m) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsThinking.toggle()
                }
            } label: {
                HStack(spacing: Space.s) {
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
                    .padding(.leading, Space.l)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.border).frame(width: 2.0)
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
            VStack(alignment: .leading, spacing: Space.m) {
                Text(message.error ?? "Something went wrong.")
                    .font(.subheadline)
                    .foregroundStyle(Color.destructive)
                if isLast {
                    retryButton
                }
            }
        case .stopped:
            HStack(spacing: Space.l) {
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
            chatVM.retry(client: serverVM.client, model: modelsVM.pickedModel)
        } label: {
            HStack(spacing: Space.s) {
                IconlyIcon(.refresh, .inlineButton)
                Text("Retry")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .background(Color.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Three dots breathing in turn while a reply has yet to start.
private struct WaitingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: Space.s) {
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
