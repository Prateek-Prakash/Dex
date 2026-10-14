//
//  SubAgentViews.swift
//  Dex
//
//  Created by Prateek Prakash on 10/13/26.
//

import SwiftUI

/// A sub-agent as the detail sheet shows it: with when its reply started
/// and the model it ran on.
struct SubAgentItem: Identifiable, Equatable {
    var agent: SubAgent
    var startedAt: Date
    var model: String?

    var id: String { agent.delegationID ?? agent.callID }
}

/// The sub-agents to show in the detail sheet, and which one first.
struct SubAgentSelection: Identifiable, Equatable {
    var items: [SubAgentItem]
    var index: Int

    var id: String { items.map(\.id).joined(separator: ",") + "#\(index)" }
}

private struct ShowSubAgentsKey: EnvironmentKey {
    static let defaultValue: (SubAgentSelection) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Opens the sub-agent detail sheet.
    var showSubAgents: (SubAgentSelection) -> Void {
        get { self[ShowSubAgentsKey.self] }
        set { self[ShowSubAgentsKey.self] = newValue }
    }
}

/// A reply's sub-agents, folded like its thinking: open while any runs.
struct AgentsSection: View {
    @EnvironmentObject var chatVM: ChatVM
    @Environment(\.showSubAgents) private var showSubAgents

    let agents: [SubAgent]
    let startedAt: Date
    let model: String?

    /// Nil follows the default: open while any runs.
    @State private var isOpen: Bool?

    private var isRunning: Bool { agents.contains { $0.state == .running } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOpen = !(isOpen ?? isRunning)
                }
            } label: {
                HStack(spacing: Space.s) {
                    Text(SubAgent.header(agents))
                        .font(.subheadline)
                        .fontDesign(.rounded)
                    IconlyIcon(.chevronDown, .disclosure)
                        .rotationEffect(.degrees((isOpen ?? isRunning) ? 180.0 : 0.0))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if isOpen ?? isRunning {
                // Rows apart like Searched Web's.
                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(Array(agents.enumerated()), id: \.offset) { index, agent in
                        Button {
                            let items = agents.map { SubAgentItem(agent: $0, startedAt: startedAt, model: model) }
                            showSubAgents(SubAgentSelection(items: items, index: index))
                        } label: {
                            AgentRow(agent: agent, startedAt: startedAt,
                                     step: agent.chatID.flatMap { chatVM.agentSteps[$0]?.current })
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, Space.l)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.border).frame(width: 2.0)
                }
            }
        }
    }
}

/// One sub-agent: how it's doing, its task, and its time.
private struct AgentRow: View {
    let agent: SubAgent
    let startedAt: Date
    /// What it's doing now, from the live channel.
    let step: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            AgentStateIcon(state: agent.state)
            VStack(alignment: .leading, spacing: Space.xxs) {
                // The model's own words, on one line.
                Text(agent.task.isEmpty ? "Starting…" : agent.task)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AgentTime(agent: agent, startedAt: startedAt)
        }
        .contentShape(Rectangle())
    }

    private var status: String {
        switch agent.state {
        case .running: step ?? "Working…"
        case .done: agent.isBackground ? "Finished" : "Finished in the reply"
        case .failed: agent.error ?? "Failed"
        }
    }
}

/// A spinner while it runs, a check once done, a cross if it failed.
struct AgentStateIcon: View {
    let state: SubAgent.State

    var body: some View {
        switch state {
        case .running:
            ProgressView()
                .controlSize(.mini)
                .frame(width: IconlyIcon.Context.inlineButton.points)
        case .done:
            IconlyIcon(.check, .inlineButton)
                .foregroundStyle(.secondary)
        case .failed:
            IconlyIcon(.close, .inlineButton)
                .foregroundStyle(Color.destructive)
        }
    }
}

/// A running clock while it runs; how long it took once done.
private struct AgentTime: View {
    let agent: SubAgent
    let startedAt: Date

    var body: some View {
        Group {
            if agent.state == .running {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(SubAgent.clock(context.date.timeIntervalSince(startedAt)))
                }
            } else if let duration = agent.duration {
                Text(SubAgent.format(duration))
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

/// The model's checklist, as it last stood: drawn like a task list in a
/// reply, at the fold rows' size.
struct TaskChecklist: View {
    let tasks: [AgentTask]
    @ScaledMetric(relativeTo: .subheadline) private var textSize: CGFloat = 15.0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(tasks) { task in
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    TaskBox(isChecked: task.isDone, size: textSize)
                    // The model's own words.
                    Text(task.content)
                        .font(.subheadline)
                        .foregroundStyle(task.isDone || task.isCancelled ? Color.textMuted : Color.ink)
                        .strikethrough(task.isDone || task.isCancelled)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checklist, \(tasks.filter(\.isDone).count) of \(tasks.count) done")
    }
}

/// A message the server added on its own, in place of a bubble that would
/// look like the user's: centered, between hairlines.
struct NoticeMarker: View {
    let notice: AgentNotice
    let action: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Rectangle().fill(Color.border).frame(height: 1.0)
            Button(action: action) {
                HStack(spacing: Space.s) {
                    if notice.kind == .subagent {
                        AgentStateIcon(state: notice.results.allSatisfy(\.isCompleted) ? .done : .failed)
                    }
                    Text(notice.label)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                .background(Color.surfaceCode, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(notice.kind == .timer)
            .fixedSize()
            Rectangle().fill(Color.border).frame(height: 1.0)
        }
    }
}

/// Above the composer while background sub-agents run in the chat on screen.
struct AgentsPill: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                ProgressView()
                    .controlSize(.mini)
                Text(count == 1 ? "1 Sub-Agent Running" : "\(count) Sub-Agents Running")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
                IconlyIcon(.chevronDown, .disclosure)
                    .rotationEffect(.degrees(-90.0))
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.m)
            .glassCapsule()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what they're doing")
    }
}

/// Every sub-agent of a reply, a pill or a marker, one page each: status,
/// time, task, the steps from its hidden chat, and the summary it gave.
struct SubAgentSheet: View {
    let selection: SubAgentSelection
    @State private var page: Int
    /// The way the last swipe went, for the page's slide.
    @State private var isForward = true

    init(selection: SubAgentSelection) {
        self.selection = selection
        _page = State(initialValue: selection.index)
    }

    var body: some View {
        // A resizable sheet: its grabber, no close button; dragging it down
        // closes it. The page's scroll view sits right under the bar, so the
        // bar knows it and its glass shows over what scrolls beneath; swipes
        // left and right change the page.
        NavigationStack {
            let item = selection.items[min(page, selection.items.count - 1)]
            SubAgentPage(item: item)
                .id(item.id)
                .transition(.push(from: isForward ? .trailing : .leading))
                .simultaneousGesture(swipe, including: selection.items.count > 1 ? .all : .subviews)
                // Which page, where iOS puts page dots: floating at the bottom.
                .overlay(alignment: .bottom) {
                    if selection.items.count > 1 {
                        PageDots(count: selection.items.count, current: page)
                            .padding(.horizontal, Space.m)
                            .padding(.vertical, Space.s)
                            .glassCapsule()
                            .padding(.bottom, Space.m)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Sub-Agent")
                            .font(.headline)
                            .fontDesign(.rounded)
                    }
                }
                .toolbarTitleDisplayMode(.inline)
        }
        .tint(Color.ink)
    }

    /// A mostly sideways swipe turns the page; vertical ones scroll.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24.0)
            .onEnded { drag in
                let (dx, dy) = (drag.translation.width, drag.translation.height)
                guard abs(dx) > 60.0, abs(dx) > abs(dy) * 1.5 else { return }
                let next = page + (dx < 0 ? 1 : -1)
                guard selection.items.indices.contains(next) else { return }
                isForward = dx < 0
                withAnimation(.easeInOut(duration: 0.25)) { page = next }
            }
    }
}

/// Which page is on show, as dots: the current one filled.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    // A fixed ink, not the adaptive one: glass tints that toward gray.
                    .fill(index == current ? Color.inkSoft : Color.textMuted)
                    .frame(width: 7.0, height: 7.0)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityElement()
        .accessibilityLabel("Sub-agent \(current + 1), \(count) in all")
    }
}

/// One sub-agent's page in the sheet.
private struct SubAgentPage: View {
    @EnvironmentObject var chatVM: ChatVM
    let item: SubAgentItem

    /// Read from its hidden chat; nil until read, or if it can't be.
    @State private var steps: AgentSteps?
    @State private var isReading = true
    /// Its hidden chat says it finished.
    @State private var isDoneThere = false

    /// The sub-agent as the chat on screen knows it now, not as it was when
    /// the sheet opened (its hidden chat may only have been named since).
    private var current: SubAgent {
        Self.current(item.agent, in: chatVM.messages)
    }

    static func current(_ agent: SubAgent, in messages: [ChatMessage]) -> SubAgent {
        SubAgentPageLookup.current(agent, in: messages)
    }

    /// The sub-agent as the main chat knows it; finished if its hidden chat
    /// finished with an answer, though the result never reached this branch.
    private var agent: SubAgent {
        var agent = current
        if agent.state != .done, isDoneThere, let answer = steps?.answer {
            agent.state = .done
            agent.error = nil
            if agent.result == nil { agent.result = answer }
        }
        return agent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxxl) {
                chips
                section("TASK") {
                    Text(agent.task)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                section("STEPS") { stepList }
                section("RESULT") { result }
            }
            // The chat's text column at the sides; below the bar, the gap every
            // screen leaves under its title bar.
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xl)
            // Room at the end for the floating page dots.
            .padding(.bottom, Space.xxxl + Space.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbarGlassEdge()
        .background(Color.surfaceBase.ignoresSafeArea())
        .task(id: current.chatID) { await read() }
    }

    private var chips: some View {
        HStack(spacing: Space.s) {
            chip(agent.stateLabel, tint: agent.state == .failed ? Color.destructive : Color.ink)
            if agent.state == .running {
                TimelineView(.periodic(from: item.startedAt, by: 1)) { context in
                    chip(SubAgent.clock(context.date.timeIntervalSince(item.startedAt)))
                }
            } else if let duration = agent.duration {
                chip(SubAgent.format(duration))
            }
            if let model = item.model { chip(model) }
            if agent.isBackground { chip("BACKGROUND") }
        }
    }

    private func chip(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xs)
            .background(Color.surfaceCode, in: Capsule())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
                .tracking(1.0)
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private var stepList: some View {
        let shown = (agent.chatID.flatMap { chatVM.agentSteps[$0] }).flatMap { live in
            live.steps.count > (steps?.steps.count ?? 0) ? live : nil
        } ?? steps
        if agent.chatID == nil {
            note(agent.isBackground ? "Starting…" : "Dex can't show the steps of a sub-agent that ran inside the reply.")
        } else if let shown, !shown.steps.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(Array(shown.steps.enumerated()), id: \.offset) { _, step in
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(step.label)
                            .foregroundStyle(step.isFailed ? Color.destructive : Color.ink)
                            .lineLimit(2)
                        ForEach(Array((step.lookup?.sources ?? []).enumerated()), id: \.offset) { _, source in
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
        } else if isReading {
            ProgressView()
                .controlSize(.small)
        } else {
            note(agent.state == .running ? "No steps yet." : "It didn't use any tools.")
        }
    }

    @ViewBuilder
    private var result: some View {
        if let text = agent.result ?? steps?.answer, !text.isEmpty {
            ChatMarkdownView(text: text)
                .equatable()
                .textSelection(.enabled)
        } else {
            switch agent.state {
            case .running: note("Waiting for its summary.")
            case .done: note("It finished without a summary.")
            case .failed: note(agent.error ?? "It didn't finish.")
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    /// Reads its hidden chat; again every few seconds while it runs.
    private func read() async {
        guard let chatID = current.chatID else {
            isReading = false
            return
        }
        while !Task.isCancelled {
            if let detail = await chatVM.agentDetail(chatID: chatID) {
                steps = detail.steps
                isDoneThere = detail.isDone
                isReading = false
                if detail.isDone { return }
            } else {
                isReading = false
            }
            // Read afresh each round: the reply may have finished it meanwhile.
            guard Self.current(item.agent, in: chatVM.messages).state == .running else { return }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}

/// Finds a sub-agent as the chat now knows it, by the call that started it.
enum SubAgentPageLookup {
    static func current(_ agent: SubAgent, in messages: [ChatMessage]) -> SubAgent {
        SubAgentBoard.agents(in: messages).values.lazy.flatMap { $0 }.first { $0.callID == agent.callID } ?? agent
    }
}
