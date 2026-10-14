//
//  ChatWidthTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/14/26.
//

import SwiftUI
import Testing
@testable import Dex

/// Nothing in a reply comes out wider than the chat's column: even a third
/// of a point over lets the whole chat scroll sideways.
@MainActor
struct ChatWidthTests {
    /// The text column on a 393pt-wide phone: 20pt in from each side.
    static let column: CGFloat = 353

    private func width<V: View>(_ view: V) -> CGFloat {
        let host = UIHostingController(rootView: view.environmentObject(ChatVM()))
        return host.sizeThatFits(in: CGSize(width: Self.column, height: 4000)).width
    }

    private static let long = String(repeating: "Research and compare the battery life of the M4 and M5 MacBook Pro ", count: 3)

    @Test func taskListsFitTheColumn() {
        #expect(width(ChatMarkdownView(text: "- [ ] " + Self.long + "\n- [x] Done")) <= Self.column)
        #expect(width(TaskChecklist(tasks: [AgentTask(id: "1", content: Self.long, status: "pending"),
                                            AgentTask(id: "2", content: Self.long, status: "completed")])) <= Self.column)
    }

    @Test func subAgentPartsFitTheColumn() {
        let agents = [SubAgent(callID: "a", task: Self.long, isBackground: true, delegationID: "d"),
                      SubAgent(callID: "b", task: Self.long, isBackground: true, state: .done, duration: 143)]
        let notice = AgentNotice(kind: .subagent, results: [.init(delegationID: "d", status: "completed", duration: 98, text: "x")])
        #expect(width(AgentsSection(agents: agents, startedAt: .now, model: "gemma4:12b")) <= Self.column)
        #expect(width(NoticeMarker(notice: notice) {}) <= Self.column)
    }
}
