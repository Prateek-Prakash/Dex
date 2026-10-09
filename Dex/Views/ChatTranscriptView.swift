//
//  ChatTranscriptView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// The open chat's messages: the user's in bubbles on the right, replies
/// full width as Markdown. Like Claude: each message sent is pinned to the
/// top, its reply growing below it into the room left and on past the
/// composer. Whenever the end is out of view a jump arrow shows; it, and
/// only it, scrolls to the end and follows (answer and thinking) until the
/// reader scrolls up.
///
/// A plain VStack, not a lazy one, gives the scroll view real heights:
/// lazy height guesses jumped on each message and sent scrolls into blank
/// space.
struct ChatTranscriptView: View {
    @EnvironmentObject var chatVM: ChatVM

    /// Keeps the end in view: set by the jump arrow only, cleared by the
    /// reader's own scroll up.
    @State private var isFollowing: Bool = false
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var position = ScrollPosition(edge: .bottom)
    /// True while this view animates a scroll itself, so it never counts
    /// as the reader's.
    @State private var isScrollingItself = false
    /// Within reach of the end, by the latest geometry.
    @State private var isNearBottom = true
    /// The message pinned to the top: the last one sent here.
    @State private var pinnedID: String?
    /// Each turn's measured height, by its first message: the pinned one's
    /// is known the moment it's pinned. Reset to 0 at the pin, the room came
    /// out too big, then shrank once the turn re-measured, and the shorter
    /// list dropped the message halfway down.
    @State private var turnHeights: [String: CGFloat] = [:]
    /// Each turn's top in the list's content, by its first message: the pin
    /// scrolls to it. Scrolling to the turn by id aimed short.
    @State private var turnTops: [String: CGFloat] = [:]
    /// The list's height, and the height between the toolbar and the
    /// composer: where the reply ends, and how much of it shows.
    @State private var contentHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0

    /// Where the reply ends: the list's height without the empty room.
    private var replyEnd: CGFloat { contentHeight - room }
    /// The pinned message and its replies' height, and the height between
    /// the toolbar and the composer: what's left is room for the reply.
    private var pinnedTurnHeight: CGFloat {
        pinnedID.flatMap { turnHeights[$0] } ?? 0
    }
    /// The scroll view's full height, the tallest seen (the keyboard shrinks
    /// it). The scroll range runs to it, under the toolbar and the composer
    /// too, so the room is sized from it: sized from just the gap between
    /// them, the room fell 277pt short and the message stopped mid-screen.
    @State private var viewportHeight: CGFloat = 0
    /// Keeps the pinned message at the top while the screen settles: the
    /// keyboard going away after a send grows the viewport, and the room
    /// with it. Ends when the reader touches the list or the reply fills it.
    @State private var isAligningPin = false

    private var room: CGFloat {
        guard pinnedID != nil else { return 0 }
        // Around the measured turn: its own top padding and the gap before
        // the room (measured on device: 613 - 99 - 24 left it exact).
        return TranscriptLayout.room(viewport: viewportHeight, turn: pinnedTurnHeight,
                                     padding: Space.xl + Space.m)
    }

    var body: some View {
        ScrollView {
            // Turns xxxl apart: m between them plus each one's own xl on top.
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(TranscriptLayout.turns(chatVM.messages), id: \.[0].id) { turn in
                    VStack(alignment: .leading, spacing: Space.xxxl) {
                        ForEach(turn) { message in
                            switch message.role {
                            case .user, .system:
                                UserBubble(text: message.content)
                            case .assistant:
                                ReplyView(message: message, isLast: message.id == chatVM.messages.last?.id)
                            }
                        }
                    }
                    // Part of the turn, so a pinned message keeps it above,
                    // clear of the toolbar.
                    .padding(.top, Space.xl)
                    .id(turn[0].id)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        turnHeights[turn[0].id] = height
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.content)).minY } action: { y in
                        turnTops[turn[0].id] = y
                    }
                }
                // Room for the pinned message's reply to grow into.
                Color.clear
                    .frame(height: room)
            }
            .padding(.horizontal, Space.xxl)
            // The first turn's own top padding stands in at the top.
            .padding(.bottom, Space.xl)
            .coordinateSpace(.named(Self.content))
            .scrollTargetLayout()
        }
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .toolbarGlassEdge()
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .onScrollPhaseChange { _, phase in
            scrollPhase = phase
            if phase == .interacting {
                isScrollingItself = false
                isAligningPin = false
            }
            guard phase == .idle else { return }
            isScrollingItself = false
            // The pin's own animation may have aimed short of a room that
            // grew meanwhile (the keyboard going away).
            if isAligningPin, let pinnedID { alignPin(pinnedID) }
            // Growth that came while it was moving.
            if isFollowing, !isNearBottom { revealEnd() }
        }
        // Following: each growth brings the reply's end into view, room
        // or no room.
        .onChange(of: replyEnd) {
            if isFollowing, !isNearBottom, scrollPhase == .idle { revealEnd() }
        }
        .onScrollGeometryChange(for: TranscriptScroll.self) { geometry in
            TranscriptScroll(
                offset: geometry.contentOffset.y,
                // The reply's end, not the empty room below it.
                isAtBottom: TranscriptLayout.isAtBottom(
                    visibleMaxY: geometry.visibleRect.maxY, bottomInset: geometry.contentInsets.bottom,
                    contentHeight: geometry.contentSize.height - room),
                container: geometry.containerSize.height,
                content: geometry.contentSize.height,
                visible: geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            )
        } action: { old, new in
            isNearBottom = new.isAtBottom
            viewportHeight = max(viewportHeight, new.container)
            contentHeight = new.content
            visibleHeight = new.visible
            // The reader's scroll up (a drag, a fling, a status bar tap).
            if TranscriptLayout.stopsFollowing(from: old.offset, to: new.offset,
                                               isReaderScrolling: scrollPhase != .idle && !isScrollingItself) {
                isFollowing = false
            }
        }
        .onChange(of: room) { _, room in
            guard isAligningPin, let pinnedID else { return }
            if room == 0 {
                isAligningPin = false
            } else if scrollPhase == .idle {
                alignPin(pinnedID)
            }
        }
        // One handler for both, since opening a chat changes the chat and
        // its messages at once: another chat shows its end, nothing pinned;
        // a message sent here (its reply streaming) is pinned to the top.
        .onChange(of: PinKey(chatID: chatVM.chat?.id, target: TranscriptLayout.pinTarget(chatVM.messages))) { old, new in
            if let oldChat = old.chatID, oldChat != new.chatID {
                pinnedID = nil
                isAligningPin = false
                isFollowing = false
                position.scrollTo(edge: .bottom)
            } else if let target = new.target, target != pinnedID {
                pin(target)
            }
        }
        .onAppear {
            if let target = TranscriptLayout.pinTarget(chatVM.messages) { pin(target) }
        }
        .overlay(alignment: .bottom) {
            // Whenever the end is out of view.
            if !isNearBottom {
                Button(action: follow) {
                    IconlyIcon(.arrowDown, .field)
                        .padding(Space.m)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .padding(.bottom, Space.xs)
                .transition(.opacity)
                .accessibilityLabel("Scroll to End")
            }
        }
        .animation(.easeOut(duration: 0.2), value: isNearBottom)
    }

    /// Pins a message to the top; its reply grows below, not followed. The
    /// scroll waits a layout pass for the room to exist; the room then
    /// shrinks as the reply grows, keeping the list's height.
    private func pin(_ id: String) {
        pinnedID = id
        isAligningPin = true
        isFollowing = false
        isScrollingItself = true
        DispatchQueue.main.async {
            // Superseded meanwhile (another chat opened): leave it.
            guard pinnedID == id else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                scrollToPin(id)
            }
        }
    }

    /// Puts a turn's top just under the toolbar: `scrollTo(y:)` already
    /// counts the toolbar's inset (subtracting it again left the message
    /// one toolbar-height low).
    private func scrollToPin(_ id: String) {
        guard let top = turnTops[id] else { return }
        position.scrollTo(y: top)
    }

    private static let content = "transcriptContent"

    /// Brings the pinned message back to the top, gliding, never popping.
    private func alignPin(_ id: String) {
        withAnimation(.easeOut(duration: 0.25)) {
            scrollToPin(id)
        }
    }

    /// The jump arrow (shown only while the reply's end is hidden): to that
    /// end, following from there.
    private func follow() {
        isAligningPin = false
        isFollowing = true
        isScrollingItself = true
        withAnimation(.easeOut(duration: 0.2)) { revealEnd() }
    }

    /// The reply's end just above the composer. `scrollTo(y:)` puts that
    /// content y at the visible top, toolbar counted; the room below the
    /// reply is never scrolled into.
    private func revealEnd() {
        position.scrollTo(y: max(0, replyEnd - visibleHeight))
    }
}

/// The transcript's scroll rules, kept pure so they can be tested.
enum TranscriptLayout {
    /// How close to the end counts as there: a reply can grow a line or two
    /// while the reader scrolls back down.
    static let nearBottom: CGFloat = 60

    /// The messages in turns: each message sent and the replies after it.
    static func turns(_ messages: [ChatMessage]) -> [[ChatMessage]] {
        var turns: [[ChatMessage]] = []
        for message in messages {
            if message.role == .assistant, !turns.isEmpty {
                turns[turns.count - 1].append(message)
            } else {
                turns.append([message])
            }
        }
        return turns
    }

    /// The message to pin: the last one sent, while its reply is coming.
    static func pinTarget(_ messages: [ChatMessage]) -> String? {
        guard let last = messages.last, last.role == .assistant, last.status == .streaming else { return nil }
        return messages.last { $0.role != .assistant }?.id
    }

    /// Room below the pinned turn so it can sit at the top: the viewport it
    /// doesn't fill yet. None once the reply fills it.
    static func room(viewport: CGFloat, turn: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, viewport - turn - padding)
    }

    /// At the end: the area under the composer doesn't count, text there
    /// is hidden.
    static func isAtBottom(visibleMaxY: CGFloat, bottomInset: CGFloat, contentHeight: CGFloat) -> Bool {
        visibleMaxY - bottomInset >= contentHeight - nearBottom
    }

    /// Whether a scroll stops following: the reader's, and upward.
    /// Growth never moves the offset, so it can't.
    static func stopsFollowing(from old: CGFloat, to new: CGFloat, isReaderScrolling: Bool) -> Bool {
        isReaderScrolling && new < old - 1
    }
}

/// What the pin follows: the chat on screen and the message to pin.
private struct PinKey: Equatable {
    let chatID: String?
    let target: String?
}

/// Where the transcript is scrolled, and the height it shows.
private struct TranscriptScroll: Equatable {
    let offset: CGFloat
    let isAtBottom: Bool
    /// The scroll view's full height, for sizing the room.
    let container: CGFloat
    let content: CGFloat
    let visible: CGFloat
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
                // Selected and copied like any text; menu actions come later.
                .textSelection(.enabled)
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
    @State private var showsLookups: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let thinking = message.thinking {
                thinkingSection(thinking)
            }
            if let lookups = message.lookups {
                lookupsSection(lookups)
            }
            if !message.content.isEmpty {
                ChatMarkdownView(text: message.content)
                    .equatable()
                    .textSelection(.enabled)
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

    /// The web searches and page reads behind the reply, folded away like
    /// its reasoning; each source opens in the browser.
    private func lookupsSection(_ lookups: [WebLookup]) -> some View {
        // A lookup left running by a reply that was cut off isn't searching.
        let isSearching = message.status == .streaming && lookups.contains { $0.state == .running }
        return VStack(alignment: .leading, spacing: Space.m) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsLookups.toggle()
                }
            } label: {
                HStack(spacing: Space.s) {
                    Text(isSearching ? "Searching Web" : "Searched Web")
                        .font(.subheadline)
                        .fontDesign(.rounded)
                    IconlyIcon(.chevronDown, .disclosure)
                        .rotationEffect(.degrees(showsLookups ? 180.0 : 0.0))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if showsLookups {
                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(Array(lookups.enumerated()), id: \.offset) { _, lookup in
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text(lookup.label)
                                .foregroundStyle(lookup.state == .failed ? Color.destructive : Color.ink)
                                .lineLimit(2)
                            if let error = lookup.error {
                                Text(error)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(lookup.sources.enumerated()), id: \.offset) { _, source in
                                if let url = URL(string: source.url) {
                                    Link(source.title, destination: url)
                                        .foregroundStyle(Color.link)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .font(.subheadline)
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
            chatVM.retry(model: modelsVM.pickedModel?.id, webSearch: serverVM.isWebSearchOn)
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
