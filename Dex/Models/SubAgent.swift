//
//  SubAgent.swift
//  Dex
//
//  Created by Prateek Prakash on 10/13/26.
//

import Foundation

/// A sub-agent a reply started with Open WebUI's `delegate_task`: a hidden
/// chat on the server doing one task, whose summary comes back to the
/// main chat. Run in the foreground, the summary is the call's own output;
/// in the background, it arrives later as an internal message (`AgentNotice`).
struct SubAgent: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case running, done, failed
    }

    /// The tool call that started it; identifies it within its reply.
    var callID: String
    /// The task as the model wrote it.
    var task: String
    var isBackground: Bool
    var state: State = .running
    /// The server's handle for a background run, which its result names.
    var delegationID: String?
    /// The hidden chat it works in.
    var chatID: String?
    /// The summary it handed back.
    var result: String?
    /// Seconds it ran, when the server says.
    var duration: Double?
    /// Why it didn't finish.
    var error: String?

    /// The server's tool name.
    static let toolName = "delegate_task"

    /// A `delegate_task` call; nil for any other tool. Started with empty
    /// arguments, the task comes once the call is done.
    init?(callID: String, name: String, arguments: String) {
        guard name == Self.toolName else { return nil }
        let arguments = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any]
        self.init(callID: callID, task: (arguments?["task"] as? String) ?? "",
                  isBackground: (arguments?["background"] as? Bool) ?? false)
    }

    init(callID: String, task: String, isBackground: Bool, state: State = .running, delegationID: String? = nil,
         chatID: String? = nil, result: String? = nil, duration: Double? = nil, error: String? = nil) {
        self.callID = callID
        self.task = task
        self.isBackground = isBackground
        self.state = state
        self.delegationID = delegationID
        self.chatID = chatID
        self.result = result
        self.duration = duration
        self.error = error
    }

    /// The call's output. A background run answers with a handle and goes
    /// on; a foreground one with its summary; either with "Error: …".
    mutating func finish(output: String) {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("Error:") {
            state = .failed
            error = String(text.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces)
            return
        }
        struct Dispatch: Decodable {
            let status: String?
            let delegationID: String?
            let chatID: String?
            enum CodingKeys: String, CodingKey {
                case status
                case delegationID = "delegation_id"
                case chatID = "subagent_chat_id"
            }
        }
        if let dispatch = try? JSONDecoder().decode(Dispatch.self, from: Data(text.utf8)), dispatch.status == "dispatched" {
            isBackground = true
            delegationID = dispatch.delegationID
            chatID = dispatch.chatID
            return
        }
        state = .done
        result = text
    }

    /// Takes in its background result.
    mutating func take(_ result: AgentNotice.Result) {
        state = result.isCompleted ? .done : .failed
        self.result = result.text
        duration = result.duration
        chatID = chatID ?? result.chatID
        if !result.isCompleted { error = result.status }
    }
}

/// An item of the checklist a model keeps with Open WebUI's `create_tasks`
/// and `update_task`.
struct AgentTask: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var content: String
    /// "pending", "in_progress", "completed" or "cancelled".
    var status: String

    var isDone: Bool { status == "completed" }
    var isCancelled: Bool { status == "cancelled" }

    static let toolNames: Set<String> = ["create_tasks", "update_task"]

    /// The whole list, from either tool's output; nil for an error.
    static func list(output: String) -> [AgentTask]? {
        struct Body: Decodable { let tasks: [AgentTask]? }
        return (try? JSONDecoder().decode(Body.self, from: Data(output.utf8)))?.tasks
    }
}

/// A message the server adds to a chat on its own: a background sub-agent's
/// result, or a timer the model set. Stored as a user message, which Dex
/// shows as a marker, not a bubble.
struct AgentNotice: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case subagent, timer
    }

    struct Result: Codable, Equatable, Sendable {
        var delegationID: String
        var chatID: String?
        /// "completed", "interrupted" or "error".
        var status: String
        var duration: Double?
        var text: String

        var isCompleted: Bool { status == "completed" }
    }

    var kind: Kind
    /// Every result it carries: the server batches results that land together.
    var results: [Result] = []

    /// The header each result starts with.
    static let marker = "[ASYNC SUBAGENT COMPLETE - "

    /// The results in a notice's text, as the server writes them:
    ///
    ///     [ASYNC SUBAGENT COMPLETE - deleg_1]
    ///     …
    ///     Subagent chat: c1
    ///     Status: completed   Duration: 98.0s
    ///     --- RESULT ---
    ///     The summary
    static func results(in content: String) -> [Result] {
        content.components(separatedBy: marker).dropFirst().compactMap { block in
            guard let close = block.firstIndex(of: "]") else { return nil }
            let delegationID = String(block[..<close])
            let body = String(block[block.index(after: close)...])
            let parts = body.components(separatedBy: "--- RESULT ---")
            let head = parts[0]
            let text = parts.dropFirst().joined(separator: "--- RESULT ---").trimmingCharacters(in: .whitespacesAndNewlines)
            var result = Result(delegationID: delegationID, status: "completed", text: text)
            for line in head.split(separator: "\n") {
                if line.hasPrefix("Subagent chat: ") {
                    result.chatID = String(line.dropFirst("Subagent chat: ".count)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Status: ") {
                    let fields = line.dropFirst("Status: ".count).components(separatedBy: "Duration:")
                    result.status = fields[0].trimmingCharacters(in: .whitespaces)
                    if fields.count > 1 {
                        let seconds = fields[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "s"))
                        result.duration = Double(seconds)
                    }
                }
            }
            return result
        }
    }

    /// Its marker in the transcript.
    var label: String {
        switch kind {
        case .timer:
            return "Timer Fired"
        case .subagent:
            let failed = results.contains { !$0.isCompleted }
            let verb = failed ? "Failed" : "Finished"
            guard results.count == 1, let result = results.first else {
                return results.isEmpty ? "Sub-Agent \(verb)" : "\(results.count) Sub-Agents \(verb)"
            }
            return result.duration.map { "Sub-Agent \(verb) · \(SubAgent.format($0))" } ?? "Sub-Agent \(verb)"
        }
    }
}

extension SubAgent {
    /// How long one ran, as shown: "42S", "1M 38S".
    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total < 60 ? "\(total)S" : "\(total / 60)M \(total % 60)S"
    }

    /// A running clock: "0:42", "12:05".
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// How long a background run is waited for before it counts as lost: the
    /// server's result never came (it restarted, or the chat moved on).
    static let patience: TimeInterval = 60 * 60

    /// The fold over a reply's sub-agents.
    static func header(_ agents: [SubAgent]) -> String {
        let noun = agents.count == 1 ? "Sub-Agent" : "Sub-Agents"
        if agents.contains(where: { $0.state == .running }) {
            return "Running \(agents.count) \(noun)"
        }
        let longest = agents.compactMap(\.duration).max()
        return "Ran \(agents.count) \(noun)" + (longest.map { " · \(format($0))" } ?? "")
    }

    /// Its status chip in the detail sheet.
    var stateLabel: String {
        switch state {
        case .running: "RUNNING"
        case .done: "FINISHED"
        case .failed: "FAILED"
        }
    }
}

/// Every sub-agent in a chat, background results matched to the replies
/// that started them.
enum SubAgentBoard {
    /// The chat's sub-agents by reply id, with each background result taken
    /// in. One still waiting past `SubAgent.patience` counts as failed.
    static func agents(in messages: [ChatMessage], now: Date = .now) -> [String: [SubAgent]] {
        var results: [String: AgentNotice.Result] = [:]
        for message in messages {
            for result in message.notice?.results ?? [] { results[result.delegationID] = result }
        }
        var board: [String: [SubAgent]] = [:]
        for message in messages {
            guard var agents = message.agents, !agents.isEmpty else { continue }
            for index in agents.indices where agents[index].state == .running {
                if let id = agents[index].delegationID, let result = results[id] {
                    agents[index].take(result)
                } else if message.status != .streaming,
                          !agents[index].isBackground || now.timeIntervalSince(message.createdAt) > SubAgent.patience {
                    // A foreground one ends with its reply; a background one may take a while.
                    agents[index].state = .failed
                    agents[index].error = agents[index].isBackground ? "No result came back." : "The reply ended first."
                }
            }
            board[message.id] = agents
        }
        return board
    }

    /// Background sub-agents still running, oldest first, with when their
    /// reply started and its model.
    static func running(in messages: [ChatMessage], now: Date = .now) -> [(agent: SubAgent, startedAt: Date, model: String?)] {
        let board = agents(in: messages, now: now)
        return messages.flatMap { message in
            (board[message.id] ?? []).filter { $0.state == .running && $0.isBackground }
                .map { ($0, message.createdAt, message.model) }
        }
    }

    /// The checklist as it last stood: the latest list any reply wrote.
    static func tasks(in messages: [ChatMessage]) -> [AgentTask]? {
        messages.last { $0.tasks != nil }?.tasks
    }
}

/// What a sub-agent did in its hidden chat, one row per tool call: built
/// live from the server's events, or whole from its saved chat.
struct AgentSteps: Equatable, Sendable {
    struct Step: Equatable, Sendable {
        var callID: String
        var name: String
        /// A web search or page read, with its sources once done.
        var lookup: WebLookup?
        var isDone = false
        var isFailed = false

        var label: String {
            if let lookup { return lookup.label }
            if isFailed { return "Couldn't Use \(name)" }
            return isDone ? "Used \(name)" : "Using \(name)…"
        }
    }

    private(set) var steps: [Step] = []
    /// Its final answer, once it gave one.
    private(set) var answer: String?

    init() {}

    /// A saved hidden chat's reply.
    init(output: [WebUIOutputItem]) {
        for item in output { apply(item, isDone: true) }
    }

    /// The latest step, for its row while it runs.
    var current: String? {
        guard let last = steps.last else { return nil }
        return last.label
    }

    mutating func apply(_ item: WebUIOutputItem, isDone: Bool) {
        switch item {
        case .functionCall(_, let callID, let name, let arguments):
            let lookup = WebLookup(name: name, arguments: arguments)
            if let index = steps.firstIndex(where: { $0.callID == callID }) {
                if let lookup { steps[index].lookup = steps[index].lookup.map { var kept = $0; kept.subject = lookup.subject; return kept } ?? lookup }
            } else {
                steps.append(Step(callID: callID, name: name, lookup: lookup))
            }
        case .functionCallOutput(let callID, let text):
            guard let index = steps.firstIndex(where: { $0.callID == callID }) else { return }
            steps[index].isDone = true
            if text.hasPrefix("Error") { steps[index].isFailed = true }
            if steps[index].lookup != nil {
                steps[index].lookup?.finish(output: text)
                if steps[index].isFailed { steps[index].lookup?.state = .failed }
            }
        case .message(_, let text):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { answer = text }
        case .reasoning, .other:
            break
        }
    }
}
