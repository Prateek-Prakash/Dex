//
//  SubAgentTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/13/26.
//

import Foundation
import Testing
@testable import Dex

/// Sub-agents, the checklist and server notices: parsed from what Open
/// WebUI saves and streams, matched up, and labeled.
struct SubAgentTests {
    /// A background result as the server writes it.
    static func resultText(_ delegation: String, chat: String = "s1", status: String = "completed",
                           duration: String = "98.0s", text: String = "The summary") -> String {
        """
        [ASYNC SUBAGENT COMPLETE - \(delegation)]
        A background subagent you dispatched earlier has finished. The original task source is included so you can decide whether to use the result or continue without it.

        Original task: Research battery life
        Subagent chat: \(chat)
        Status: \(status)   Duration: \(duration)
        --- RESULT ---
        \(text)
        """
    }

    @Test func delegateCallsBecomeSubAgents() {
        let agent = SubAgent(callID: "c1", name: "delegate_task", arguments: #"{"background": true, "task": "Research battery life"}"#)
        #expect(agent == SubAgent(callID: "c1", task: "Research battery life", isBackground: true))
        #expect(SubAgent(callID: "c1", name: "delegate_task", arguments: "")?.task == "")
        #expect(SubAgent(callID: "c1", name: "search_web", arguments: #"{"query":"q"}"#) == nil)
    }

    @Test func outputDispatchesFinishesOrFails() {
        var background = SubAgent(callID: "c1", task: "T", isBackground: false)
        background.finish(output: #"{"status": "dispatched", "delegation_id": "deleg_1", "subagent_chat_id": "s1", "mode": "background", "task": "T"}"#)
        #expect(background.state == .running)
        #expect(background.isBackground)
        #expect(background.delegationID == "deleg_1")
        #expect(background.chatID == "s1")

        var foreground = SubAgent(callID: "c2", task: "T", isBackground: false)
        foreground.finish(output: "  The summary \n")
        #expect(foreground.state == .done)
        #expect(foreground.result == "The summary")

        var refused = SubAgent(callID: "c3", task: "T", isBackground: true)
        refused.finish(output: "Error: background sub-agents are disabled in settings.")
        #expect(refused.state == .failed)
        #expect(refused.error == "background sub-agents are disabled in settings.")
    }

    @Test func noticesCarryEachResult() {
        let one = AgentNotice.results(in: Self.resultText("deleg_1", text: "Line one\n--- RESULT --- inside"))
        #expect(one == [.init(delegationID: "deleg_1", chatID: "s1", status: "completed", duration: 98,
                              text: "Line one\n--- RESULT --- inside")])
        // Results that land together come as one message.
        let batched = AgentNotice.results(in: Self.resultText("deleg_1") + "\n\n"
                                          + Self.resultText("deleg_2", chat: "s2", status: "error", duration: "3.5s",
                                                            text: "The subagent did not complete successfully."))
        #expect(batched.map(\.delegationID) == ["deleg_1", "deleg_2"])
        #expect(batched[1].isCompleted == false)
        #expect(batched[1].duration == 3.5)
        #expect(AgentNotice.results(in: "Plain text").isEmpty)
    }

    @Test(arguments: [
        (AgentNotice(kind: .timer), "Timer Fired"),
        (AgentNotice(kind: .subagent, results: [.init(delegationID: "d", status: "completed", duration: 98, text: "")]),
         "Sub-Agent Finished · 1M 38S"),
        (AgentNotice(kind: .subagent, results: [.init(delegationID: "d", status: "completed", text: "")]), "Sub-Agent Finished"),
        (AgentNotice(kind: .subagent, results: [.init(delegationID: "d", status: "error", duration: 4, text: "")]),
         "Sub-Agent Failed · 4S"),
        (AgentNotice(kind: .subagent, results: [.init(delegationID: "a", status: "completed", text: ""),
                                                .init(delegationID: "b", status: "completed", text: "")]),
         "2 Sub-Agents Finished"),
    ])
    func noticeLabels(_ notice: AgentNotice, _ label: String) {
        #expect(notice.label == label)
    }

    @Test func headersAndTimes() {
        let running = SubAgent(callID: "a", task: "T", isBackground: true)
        var done = running
        done.state = .done
        done.duration = 127
        #expect(SubAgent.header([running, done]) == "Running 2 Sub-Agents")
        #expect(SubAgent.header([done]) == "Ran 1 Sub-Agent · 2M 7S")
        var noTime = done
        noTime.duration = nil
        #expect(SubAgent.header([noTime, noTime]) == "Ran 2 Sub-Agents")
        #expect(SubAgent.format(42.4) == "42S")
        #expect(SubAgent.clock(65) == "1:05")
        #expect(SubAgent.clock(-3) == "0:00")
        #expect(done.stateLabel == "FINISHED")
    }

    /// A reply that started `agents`, and messages after it.
    private static func chat(agents: [SubAgent], replyStatus: ChatMessage.Status = .done, startedAt: Date = .now,
                             notices: [AgentNotice] = []) -> [ChatMessage] {
        var messages = [ChatMessage(id: "u", role: .user, content: "Q", sequence: 0),
                        ChatMessage(id: "r", role: .assistant, agents: agents, createdAt: startedAt, sequence: 1, status: replyStatus)]
        for (index, notice) in notices.enumerated() {
            messages.append(ChatMessage(id: "n\(index)", role: .user, notice: notice, sequence: 2 + index))
        }
        return messages
    }

    @Test func boardMatchesBackgroundResults() {
        let agent = SubAgent(callID: "c1", task: "T", isBackground: true, delegationID: "deleg_1", chatID: "s1")
        #expect(SubAgentBoard.agents(in: Self.chat(agents: [agent]))["r"]?.first?.state == .running)
        #expect(SubAgentBoard.running(in: Self.chat(agents: [agent])).count == 1)

        let notice = AgentNotice(kind: .subagent, results: AgentNotice.results(in: Self.resultText("deleg_1")))
        let finished = SubAgentBoard.agents(in: Self.chat(agents: [agent], notices: [notice]))["r"]?.first
        #expect(finished?.state == .done)
        #expect(finished?.result == "The summary")
        #expect(finished?.duration == 98)
        #expect(SubAgentBoard.running(in: Self.chat(agents: [agent], notices: [notice])).isEmpty)
    }

    @Test func unansweredSubAgentsEnd() {
        // A foreground one ends with its reply.
        let foreground = SubAgent(callID: "c1", task: "T", isBackground: false)
        #expect(SubAgentBoard.agents(in: Self.chat(agents: [foreground], replyStatus: .streaming))["r"]?.first?.state == .running)
        #expect(SubAgentBoard.agents(in: Self.chat(agents: [foreground]))["r"]?.first?.state == .failed)
        // A background one gets an hour.
        let background = SubAgent(callID: "c2", task: "T", isBackground: true, delegationID: "d")
        let old = Date.now.addingTimeInterval(-SubAgent.patience - 1)
        #expect(SubAgentBoard.agents(in: Self.chat(agents: [background], startedAt: old))["r"]?.first?.state == .failed)
    }

    @MainActor
    @Test func theSheetFollowsTheAgentAsTheChatLearnsMore() {
        // Opened before the server named its hidden chat.
        let first = SubAgent(callID: "c1", task: "T", isBackground: true)
        var named = first
        named.delegationID = "deleg_1"
        named.chatID = "s1"
        #expect(SubAgentPageLookup.current(first, in: Self.chat(agents: [named], replyStatus: .streaming)).chatID == "s1")
        // Gone from the chat: the copy it opened with.
        #expect(SubAgentPageLookup.current(first, in: []).chatID == nil)
    }

    @Test func checklistIsTheLatestList() {
        var messages = Self.chat(agents: [])
        #expect(SubAgentBoard.tasks(in: messages) == nil)
        messages[1].tasks = [AgentTask(id: "1", content: "A", status: "pending")]
        messages.append(ChatMessage(id: "r2", role: .assistant, tasks: [AgentTask(id: "1", content: "A", status: "completed")], sequence: 9))
        #expect(SubAgentBoard.tasks(in: messages)?.first?.isDone == true)
    }

    @Test func replyPartsKeepSubAgentsAndChecklist() {
        let parts = ReplyParts(output: [
            .functionCall(id: "f1", callID: "t1", name: "create_tasks", arguments: #"{"tasks":[]}"#),
            .functionCallOutput(callID: "t1", text: #"{"tasks": [{"id": "perf", "content": "Research performance", "status": "pending"}], "summary": {}}"#),
            .functionCall(id: "f2", callID: "d1", name: "delegate_task", arguments: #"{"background": true, "task": "Research performance"}"#),
            .functionCallOutput(callID: "d1", text: #"{"status": "dispatched", "delegation_id": "deleg_1", "subagent_chat_id": "s1"}"#),
            .functionCall(id: "f3", callID: "w1", name: "search_web", arguments: #"{"query":"m5"}"#),
            .message(id: "m", text: "Started."),
        ])
        #expect(parts.tasks == [AgentTask(id: "perf", content: "Research performance", status: "pending")])
        #expect(parts.agents == [SubAgent(callID: "d1", task: "Research performance", isBackground: true,
                                          delegationID: "deleg_1", chatID: "s1")])
        #expect(parts.lookups.map(\.subject) == ["m5"])
        var message = ChatMessage(role: .assistant, sequence: 0)
        parts.apply(to: &message)
        #expect(message.agents?.count == 1)
        #expect(message.tasks?.count == 1)
    }

    @Test func liveCallsFillInTheirTask() {
        var parts = ReplyParts()
        parts.apply(.functionCall(id: "f", callID: "d1", name: "delegate_task", arguments: ""), isDone: false)
        #expect(parts.agents.first?.task == "")
        parts.apply(.functionCall(id: "f", callID: "d1", name: "delegate_task", arguments: #"{"task":"T","background":true}"#), isDone: true)
        #expect(parts.agents == [SubAgent(callID: "d1", task: "T", isBackground: true)])
    }

    @Test func stepsListEveryToolCall() {
        var steps = AgentSteps(output: [
            .functionCall(id: "a", callID: "g", name: "google_search", arguments: #"{"queries":["x"]}"#),
            .functionCallOutput(callID: "g", text: #"Error: Tool "google_search" not found."#),
            .functionCall(id: "b", callID: "s", name: "search_web", arguments: #"{"query":"m5 battery"}"#),
            .functionCallOutput(callID: "s", text: #"[{"title":"Apple","link":"https://apple.com"}]"#),
            .message(id: "m", text: " Summary "),
        ])
        #expect(steps.steps.map(\.label) == ["Couldn't Use google_search", "Searched “m5 battery”"])
        #expect(steps.steps[1].lookup?.sources.first?.url == "https://apple.com")
        #expect(steps.answer == "Summary")
        steps.apply(.functionCall(id: "c", callID: "n", name: "search_notes", arguments: "{}"), isDone: false)
        #expect(steps.current == "Using search_notes…")
    }

    @Test func internalMessagesDecodeAsNotices() throws {
        let content = String(decoding: try JSONEncoder().encode(Self.resultText("deleg_1")), as: UTF8.self)
        let json = #"{"id":"n","parentId":"r","childrenIds":[],"role":"user","content":\#(content),"meta":{"internal":true,"type":"subagent","delegation_id":"deleg_1","subagent_chat_id":"s1"}}"#
        let remote = try JSONDecoder().decode(WebUIMessage.self, from: Data(json.utf8))
        let message = CacheSync.message(remote, sequence: 0)
        #expect(message.notice?.kind == .subagent)
        #expect(message.notice?.results.first?.chatID == "s1")
        let timer = try JSONDecoder().decode(WebUIMessage.self, from: Data(#"{"id":"t","role":"user","content":"Check back","meta":{"internal":true,"type":"timer"}}"#.utf8))
        #expect(timer.notice == AgentNotice(kind: .timer))
        let plain = try JSONDecoder().decode(WebUIMessage.self, from: Data(#"{"id":"p","role":"user","content":"Hi"}"#.utf8))
        #expect(plain.notice == nil)
    }

    @Test func reloadEventsDecode() {
        let data = Data(#"{"chat_id":"c1","message_id":"a9","data":{"type":"chat:reload"}}"#.utf8)
        #expect(WebUIEvent.decode(data) == .reload(chatID: "c1", messageID: "a9"))
    }

    @MainActor
    @Test func storedMessagesKeepSubAgents() throws {
        let agent = SubAgent(callID: "c1", task: "T", isBackground: true, delegationID: "d", chatID: "s")
        let notice = AgentNotice(kind: .subagent, results: [.init(delegationID: "d", status: "completed", duration: 1, text: "x")])
        let original = ChatMessage(id: "m", role: .assistant, agents: [agent],
                                   tasks: [AgentTask(id: "1", content: "A", status: "pending")], notice: notice, sequence: 0)
        let record = Message(id: "m")
        record.update(from: original)
        let restored = ChatMessage(record)
        #expect(restored.agents == [agent])
        #expect(restored.tasks == original.tasks)
        #expect(restored.notice == notice)
    }
}
